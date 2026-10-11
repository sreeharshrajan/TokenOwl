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

    private(set) var snapshot: AntigravitySnapshot?
    private(set) var loadingState: LoadingState = .idle
    private(set) var lastSuccessfulRefresh: Date?
    private(set) var isRefreshing = false

    /// Read by the periodic loop on every cycle, so it can be tuned later.
    var refreshInterval: TimeInterval = QuotaStore.defaultRefreshInterval

    private let service: AntigravityService
    private var refreshTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    init(service: AntigravityService = AntigravityService()) {
        self.service = service

        // Debug override only; the product default stays at 5 minutes.
        if let raw = ProcessInfo.processInfo.environment["TOKENOWL_REFRESH_INTERVAL"],
           let interval = TimeInterval(raw), interval > 0 {
            self.refreshInterval = interval
        }
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

        // Rendered once `isRefreshing` has been reset, so the captured UI
        // matches the settled state.
        MenuPreviewRenderer.renderIfRequested(store: self)
    }

    private func performRefresh() async {
        let hasCachedSnapshot = snapshot != nil
        isRefreshing = true
        if !hasCachedSnapshot {
            loadingState = .loading
            MenuPreviewRenderer.renderLoadingIfRequested(store: self)
            RedactedLogger.log("Refreshing quota; menu bar label is \(menuBarLabel)")
        }
        defer { isRefreshing = false }

        do {
            let snapshot = try await fetchSnapshot()
            self.snapshot = snapshot
            lastSuccessfulRefresh = snapshot.fetchedAt
            loadingState = .loaded
            RedactedLogger.log("Quota refreshed; menu bar label is \(menuBarLabel)")
        } catch {
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

        return try await service.fetchSnapshot()
    }

    // MARK: Derived UI state

    var headlinePercent: Int? {
        snapshot?.quota.mostConstrainedPercent
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
        snapshot != nil && hasFailed
    }

    var updatedText: String {
        UpdatedText.text(updatedAt: lastSuccessfulRefresh)
    }

    var lastSuccessfulClockText: String? {
        lastSuccessfulRefresh.map(TimeFormatting.clockString(for:))
    }
}
