import Foundation
import Observation
import TokenOwlCore

/// UI-facing state for the menu bar. Exposes only safe display state:
/// snapshots, loading status and timestamps. Credentials and tokens never
/// reach this type.
@MainActor
@Observable
final class QuotaStore {

    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Conservative MVP refresh cadence.
    static let defaultRefreshInterval: TimeInterval = 5 * 60

    private(set) var providerSnapshots: [AIEditor: ProviderSnapshot] = [:]
    var selectedProviderSnapshot: ProviderSnapshot? { providerSnapshots[selectedEditor] }

    private(set) var snapshot: AntigravitySnapshot?
    private(set) var loadingState: LoadingState = .idle
    private(set) var lastSuccessfulRefresh: Date?
    private(set) var isRefreshing = false

    // MARK: AI editor selection

    /// Installed-state facts from read-only discovery. Independent of
    /// credentials: discovery never reads authentication material.
    private(set) var installations: [AIEditor: EditorInstallation]

    /// Persists across launches; the observer stores the plain raw enum value.
    /// The property is assigned during `init`, where observers do not run, so
    /// a debug preview override is never written to defaults.
    var selectedEditor: AIEditor {
        didSet {
            loadingState = selectedProviderSnapshot == nil ? .idle : .loaded
            lastSuccessfulRefresh = selectedProviderSnapshot?.fetchedAt
            Task {
                while isRefreshing { try? await Task.sleep(for: .milliseconds(25)) }
                await refresh()
            }
            EditorSelection.save(selectedEditor)
            // Re-check installation so switching editors shows fresh facts.
            installations = discovery.discoverInstallations()
            RedactedLogger.log(
                "Selected editor: \(selectedEditor.displayName); \(Self.discoverySummary(installations))"
            )
        }
    }

    /// Editors discovered on this system (including the currently active one).
    var installedEditors: [AIEditor] {
        let detected = AIEditor.allCases.filter { installations[$0]?.isInstalled == true }
        if !detected.contains(selectedEditor) {
            return [selectedEditor] + detected
        }
        return detected
    }

    /// Whether more than one AI editor exists on this system.
    var hasMultipleEditors: Bool {
        installedEditors.count > 1
    }

    /// Read by the periodic loop on every cycle, so it can be tuned later.
    var refreshInterval: TimeInterval = QuotaStore.defaultRefreshInterval

    // MARK: Preferences

    private static let modelPrefKey = "tokenowl.highlight.model"
    private static let periodPrefKey = "tokenowl.highlight.period"

    var selectedModel: HighlightFilter.ModelSelection {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.modelPrefKey)
        }
    }

    var selectedPeriod: HighlightFilter.PeriodSelection {
        didSet {
            UserDefaults.standard.set(selectedPeriod.rawValue, forKey: Self.periodPrefKey)
        }
    }

    private let service: AntigravityService
    private let discovery: EditorDiscoveryService
    let providerRegistry: QuotaProviderRegistry
    private var refreshTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    init(service: AntigravityService = AntigravityService()) {
        let discoveryService = EditorDiscoveryService()
        self.service = service
        self.discovery = discoveryService
        self.providerRegistry = QuotaProviderRegistry()

        if let rawModel = UserDefaults.standard.string(forKey: Self.modelPrefKey),
           let model = HighlightFilter.ModelSelection(rawValue: rawModel) {
            self.selectedModel = model
        } else {
            self.selectedModel = .gemini
        }

        if let rawPeriod = UserDefaults.standard.string(forKey: Self.periodPrefKey),
           let period = HighlightFilter.PeriodSelection(rawValue: rawPeriod) {
            self.selectedPeriod = period
        } else {
            self.selectedPeriod = .fiveHours
        }

        // Installation facts only — discovery reads no credentials.
        self.installations = discoveryService.discoverInstallations()

        var initialEditor = EditorSelection.load()
        #if DEBUG
        // Debug-only preview switch; ignored by release builds. Applied as a
        // plain init assignment, so the property observer never persists it.
        if let raw = ProcessInfo.processInfo.environment["TOKENOWL_PREVIEW_EDITOR"],
           let previewEditor = AIEditor(rawValue: raw) {
            initialEditor = previewEditor
        }
        #endif
        self.selectedEditor = initialEditor

        // Debug override only; the product default stays at 5 minutes.
        // Honored in debug builds only — release builds ignore it.
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["TOKENOWL_REFRESH_INTERVAL"],
           let interval = TimeInterval(raw), interval > 0 {
            self.refreshInterval = interval
        }
        #endif

        RedactedLogger.log("Editor discovery: \(Self.discoverySummary(installations))")
    }

    /// One-line, redaction-safe summary of discovery results for logs.
    private static func discoverySummary(
        _ installations: [AIEditor: EditorInstallation]
    ) -> String {
        AIEditor.allCases.map { editor in
            switch installations[editor] ?? .notInstalled {
            case .notInstalled:
                return "\(editor.displayName)=not-installed"
            case .installed(let location):
                return "\(editor.displayName)=installed(\(location))"
            case .error(let message):
                return "\(editor.displayName)=error(\(message))"
            }
        }
        .joined(separator: ", ")
    }

    // MARK: Editor status

    /// Per-editor UI state: read-only discovery facts, registry capabilities,
    /// and the live Antigravity snapshot. The snapshot is passed only for
    /// Antigravity, so no other editor can inherit its account or quota.
    var editorStatuses: [EditorStatus] {
        AIEditor.allCases.map { editor in
            if let value = providerSnapshots[editor] {
                return EditorStatus(editor: editor, installation: installations[editor] ?? .notInstalled,
                    capabilities: providerRegistry.capabilities(for: editor),
                    account: .connected(email: value.accountEmail, sourceDisplayName: value.credentialSourceDisplayName ?? editor.displayName),
                    quota: value.metrics.isEmpty ? .unavailable : .available(headlinePercent: value.headlineRemainingPercent))
            }
            return EditorStatus.compose(
                editor: editor,
                installation: installations[editor] ?? .notInstalled,
                capabilities: providerRegistry.capabilities(for: editor),
                snapshot: editor == .antigravity ? snapshot : nil
            )
        }
    }

    var selectedEditorStatus: EditorStatus? {
        editorStatuses.first { $0.editor == selectedEditor }
    }

    // MARK: Lifecycle

    /// Starts the initial load and exactly one periodic refresh timer.
    /// Safe to call more than once.
    func start() {
        guard periodicTask == nil else { return }

        Task { await refresh() }

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.refreshInterval

                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    // MARK: Refresh

    /// Manual or periodic refresh. Overlapping requests are coalesced, so a
    /// burst of UI actions results in a single network round trip.
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
        if selectedProviderSnapshot == nil && loadingState == .idle { await refresh() }

        // Rendered once `isRefreshing` has been reset, so the captured UI
        // matches the settled state.
        MenuPreviewRenderer.renderIfRequested(store: self)
    }

    private func performRefresh() async {
        let editor = selectedEditor
        let hasCachedSnapshot = providerSnapshots[editor] != nil
        isRefreshing = true
        if !hasCachedSnapshot {
            loadingState = .loading
            MenuPreviewRenderer.renderLoadingIfRequested(store: self)
            RedactedLogger.log("Refreshing quota; menu bar label is \(menuBarLabel)")
        }
        defer { isRefreshing = false }

        do {
            let result: ProviderSnapshot
            if editor == .antigravity {
                let snapshot = try await fetchSnapshot()
                self.snapshot = snapshot
                result = ProviderSnapshot(editor: editor, antigravitySnapshot: snapshot)
            } else {
                guard let provider = providerRegistry.provider(for: editor) else { throw CodexError.rateLimitsUnavailable }
                result = try await provider.fetchSnapshot()
            }
            providerSnapshots[editor] = result
            guard editor == selectedEditor else { return }
            lastSuccessfulRefresh = result.fetchedAt
            loadingState = .loaded
            RedactedLogger.log("Quota refreshed; menu bar label is \(menuBarLabel)")
        } catch {
            guard editor == selectedEditor else { return }
            // The last successful snapshot is intentionally preserved.
            loadingState = .failed(ErrorPresentation.message(for: error))
            RedactedLogger.log("Quota refresh failed: \(ErrorPresentation.message(for: error))")
        }
    }

    /// Debug affordance for verifying the failure UI without breaking the
    /// real credential or network:
    /// - `TOKENOWL_SIMULATE_FAILURE=stale` fails every refresh *after* the
    ///   first successful one (exercises stale-data preservation);
    /// - `TOKENOWL_SIMULATE_FAILURE=always` fails from the start (exercises
    ///   the empty-state error card).
    private func fetchSnapshot() async throws -> AntigravitySnapshot {
        #if DEBUG
        // Debug-only simulation switch; release builds never take this path.
        switch ProcessInfo.processInfo.environment["TOKENOWL_SIMULATE_FAILURE"] {
        case "always":
            throw OAuthError.httpError(401)
        case "stale", "1":
            if snapshot != nil {
                throw OAuthError.httpError(401)
            }
        default:
            break
        }
        #endif

        return try await service.fetchSnapshot()
    }

    // MARK: Derived UI state

    var highlightBucket: QuotaBucket? {
        HighlightFilter.resolveBucket(
            in: snapshot?.quota,
            model: selectedModel,
            period: selectedPeriod
        )
    }

    var headlinePercent: Int? {
        guard selectedEditor == .antigravity else { return selectedProviderSnapshot?.headlineRemainingPercent }
        return highlightBucket?.remainingPercent ?? snapshot?.quota.mostConstrainedPercent
    }

    var highlightLabel: String {
        HighlightFilter.label(model: selectedModel, period: selectedPeriod)
    }

    var menuBarLabel: String {
        if let headlinePercent {
            return "🦉 \(headlinePercent)%"
        }

        switch loadingState {
        case .loading, .idle:
            return "🦉 …"
        case .loaded, .failed:
            return "🦉 —"
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = loadingState {
            return message
        }
        return nil
    }

    var hasFailed: Bool {
        errorMessage != nil
    }

    /// Failed refresh while a previously loaded snapshot is still on screen.
    var isStale: Bool {
        selectedProviderSnapshot != nil && hasFailed
    }

    var updatedText: String {
        UpdatedText.text(updatedAt: lastSuccessfulRefresh)
    }

    var lastSuccessfulClockText: String? {
        lastSuccessfulRefresh.map(TimeFormatting.clockString(for:))
    }
}
