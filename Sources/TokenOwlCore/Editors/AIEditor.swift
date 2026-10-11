import Foundation

// MARK: - Editors

/// The AI editors TokenOwl can present.
///
/// Selecting an editor fetches only its registered provider.
public enum AIEditor: String, CaseIterable, Identifiable, Sendable, Equatable {
    case antigravity
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .antigravity: return "Antigravity IDE"
        case .codex: return "Codex"
        }
    }

    /// Short label for compact UI contexts.
    public var shortDisplayName: String {
        switch self {
        case .antigravity: return "Antigravity"
        case .codex: return "Codex"
        }
    }

    /// Whether TokenOwl reads credential material associated with this
    /// editor directly. Codex delegates authentication to its app-server.
    public var readsCredentials: Bool {
        self == .antigravity
    }

    // MARK: Installation locators (read-only discovery)

    /// Bundle identifiers registered by this editor's installer, checked in order.
    public var bundleIdentifiers: [String] {
        switch self {
        case .antigravity: return ["com.google.antigravity-ide", "com.google.antigravity"]
        case .codex: return []
        }
    }

    /// Application bundle names checked in standard locations as a fallback
    /// when Launch Services has no record.
    public var applicationBundleNames: [String] {
        switch self {
        case .antigravity: return ["Antigravity IDE.app", "Antigravity.app"]
        case .codex: return []
        }
    }

    /// Executable names for editors distributed as command line tools.
    /// Detection checks for an actual executable file at each location —
    /// a directory that merely contains the name (e.g. `codex.system/…`)
    /// never counts.
    public var cliExecutableNames: [String] {
        switch self {
        case .codex: return ["codex"]
        case .antigravity: return []
        }
    }
}

// MARK: - Status model

/// Installation result for one editor. Gathered without touching
/// credentials, chat histories, workspace files, or auth databases.
public enum EditorInstallation: Sendable, Equatable {
    case notInstalled
    case installed(location: String)
    case error(String)

    public var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

/// What TokenOwl can do for an editor right now, derived from the provider
/// registry. Independent from installation: an installed editor may still
/// have no quota adapter.
public struct EditorCapabilities: Sendable, Equatable {
    public let hasQuotaAdapter: Bool
    public let readsCredentials: Bool

    public init(hasQuotaAdapter: Bool, readsCredentials: Bool) {
        self.hasQuotaAdapter = hasQuotaAdapter
        self.readsCredentials = readsCredentials
    }
}

/// Account availability — an axis independent of installation and quota.
public enum EditorAccountState: Sendable, Equatable {
    /// TokenOwl has no integration with this editor's account at all.
    case notApplicable
    /// An account is being displayed, with the source it came from.
    case connected(email: String?, sourceDisplayName: String)
    /// Installed, but TokenOwl cannot establish or verify an account.
    case authenticationUnavailable
}

/// Quota availability — an axis independent of installation and account.
public enum EditorQuotaState: Sendable, Equatable {
    case notInstalled
    /// Installed, but no verified quota adapter exists yet. The UI must say
    /// so instead of borrowing another editor's numbers.
    case notConfigured
    case available(headlinePercent: Int?)
    /// An adapter exists but has no data right now.
    case unavailable
}

/// Composed, UI-facing status for one editor, built from the three
/// independent facts above.
public struct EditorStatus: Sendable, Equatable, Identifiable {
    public let editor: AIEditor
    public let installation: EditorInstallation
    public let capabilities: EditorCapabilities
    public let account: EditorAccountState
    public let quota: EditorQuotaState

    public var id: String { editor.id }

    public init(
        editor: AIEditor,
        installation: EditorInstallation,
        capabilities: EditorCapabilities,
        account: EditorAccountState,
        quota: EditorQuotaState
    ) {
        self.editor = editor
        self.installation = installation
        self.capabilities = capabilities
        self.account = account
        self.quota = quota
    }

    /// Composes independently gathered facts into one status:
    /// - `installation` from read-only discovery (no credentials involved);
    /// - `capabilities` from the quota-provider registry;
    /// - `snapshot` live Antigravity data. It is only consumed when the
    ///   editor both has a quota adapter and is Antigravity itself, so no
    ///   editor can ever inherit another's account or quota.
    public static func compose(
        editor: AIEditor,
        installation: EditorInstallation,
        capabilities: EditorCapabilities,
        snapshot: AntigravitySnapshot?
    ) -> EditorStatus {
        guard installation.isInstalled else {
            return EditorStatus(
                editor: editor,
                installation: installation,
                capabilities: capabilities,
                account: .notApplicable,
                quota: .notInstalled
            )
        }

        if capabilities.hasQuotaAdapter, editor == .antigravity, let snapshot {
            return EditorStatus(
                editor: editor,
                installation: installation,
                capabilities: capabilities,
                account: .connected(
                    email: snapshot.account.email,
                    sourceDisplayName: snapshot.credentialSource.displayName
                ),
                quota: .available(headlinePercent: snapshot.quota.mostConstrainedPercent)
            )
        }

        if capabilities.hasQuotaAdapter {
            // Adapter exists but no data has arrived (loading or failed) —
            // report honestly instead of inventing numbers.
            return EditorStatus(
                editor: editor,
                installation: installation,
                capabilities: capabilities,
                account: .authenticationUnavailable,
                quota: .unavailable
            )
        }

        // Installed, but no verified adapter — quota stays unconfigured and
        // no other editor's account is ever attributed to it.
        return EditorStatus(
            editor: editor,
            installation: installation,
            capabilities: capabilities,
            account: .authenticationUnavailable,
            quota: .notConfigured
        )
    }
}

// MARK: - Selection persistence

/// Persists the selected editor across launches.
///
/// Only the editor's plain raw value ever touches `UserDefaults` — no
/// account, credential, or quota data is written.
public enum EditorSelection {
    public static let userDefaultsKey = "tokenowl.selected.editor"

    public static func load(from defaults: UserDefaults = .standard) -> AIEditor {
        if defaults.string(forKey: userDefaultsKey) == "vscode" { return .codex }
        guard let raw = defaults.string(forKey: userDefaultsKey),
              let editor = AIEditor(rawValue: raw) else {
            return .antigravity
        }
        return editor
    }

    public static func save(_ editor: AIEditor, to defaults: UserDefaults = .standard) {
        defaults.set(editor.rawValue, forKey: userDefaultsKey)
    }
}
