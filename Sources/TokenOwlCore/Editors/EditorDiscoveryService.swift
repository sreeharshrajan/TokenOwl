import AppKit
import Foundation

// MARK: - Probe

/// Read-only facts discovery may consult.
///
/// The protocol deliberately exposes no way to execute or open anything:
/// installation detection never launches an editor or any of its binaries.
public protocol EditorProbe: Sendable {
    /// Launch Services record for a bundle identifier, if registered.
    func registeredApplicationPath(bundleIdentifier: String) -> String?
    func fileExists(atPath path: String) -> Bool
    func isDirectory(atPath path: String) -> Bool
    func isExecutableFile(atPath path: String) -> Bool
    /// Entries of the process `PATH`.
    func pathDirectories() -> [String]
}

/// Production probe: Launch Services, FileManager, and the process PATH.
/// Query-only; nothing is launched.
public struct SystemEditorProbe: EditorProbe {
    public init() {}

    public func registeredApplicationPath(bundleIdentifier: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)?.path
    }

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func pathDirectories() -> [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
    }
}

// MARK: - Discovery

/// Detects which supported AI editors are installed.
///
/// Discovery is installation detection only, by design:
/// - known bundle identifiers (Launch Services), standard application
///   locations, and executable names on the user's PATH plus a small set of
///   standard executable locations;
/// - it never executes a discovered binary to identify it;
/// - it never scans the whole filesystem, chat histories, workspace files,
///   or authentication databases;
/// - it reads no credentials — installation is independent of authentication.
public struct EditorDiscoveryService: Sendable {
    private let probe: any EditorProbe

    public init(probe: any EditorProbe = SystemEditorProbe()) {
        self.probe = probe
    }

    /// Application locations checked when Launch Services has no record.
    public static let standardApplicationDirectories = [
        "/Applications",
        "/Applications/Utilities",
        "~/Applications",
    ].map { ($0 as NSString).expandingTildeInPath }

    /// Executable locations checked in addition to PATH.
    public static let standardExecutableDirectories = [
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "~/.local/bin",
    ].map { ($0 as NSString).expandingTildeInPath }

    /// Installation state for every supported editor.
    public func discoverInstallations() -> [AIEditor: EditorInstallation] {
        var result: [AIEditor: EditorInstallation] = [:]
        for editor in AIEditor.allCases {
            result[editor] = discoverInstallation(of: editor)
        }
        return result
    }

    public func discoverInstallation(of editor: AIEditor) -> EditorInstallation {
        if editor == .codex {
            let probe = self.probe
            let resolver = CodexBinaryResolver(
                fileExists: { !probe.isDirectory(atPath: $0) && probe.isExecutableFile(atPath: $0) },
                pathDirectories: { probe.pathDirectories() }
            )
            return resolver.resolve().map { .installed(location: $0) } ?? .notInstalled
        }
        for bundleIdentifier in editor.bundleIdentifiers {
            if let path = probe.registeredApplicationPath(bundleIdentifier: bundleIdentifier) {
                return .installed(location: path)
            }
        }

        for directory in Self.standardApplicationDirectories {
            for bundleName in editor.applicationBundleNames {
                let candidate = directory + "/" + bundleName
                if probe.fileExists(atPath: candidate) {
                    return .installed(location: candidate)
                }
            }
        }

        if let executable = findExecutable(editor.cliExecutableNames) {
            return .installed(location: executable)
        }

        return .notInstalled
    }

    /// First executable file named like the tool, searched on PATH (in order)
    /// and then the standard executable locations.
    private func findExecutable(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }

        for directory in probe.pathDirectories() + Self.standardExecutableDirectories {
            for name in names {
                let candidate = directory + "/" + name
                // A directory that merely contains the tool's name (PATH on
                // this Mac includes `…/codex.system/…`) must never count:
                // the candidate has to be an executable file.
                if !probe.isDirectory(atPath: candidate),
                   probe.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }
}
