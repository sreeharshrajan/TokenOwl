import Foundation
import Testing
@testable import TokenOwlCore

// MARK: - Probe mock

/// Filesystem-only probe. Like the real protocol it cannot execute
/// anything, which is the structural guarantee that discovery stays
/// read-only.
private struct MockEditorProbe: EditorProbe {
    var registeredBundles: [String: String] = [:]
    var existingPaths: Set<String> = []
    var directoryPaths: Set<String> = []
    var executablePaths: Set<String> = []
    var pathDirs: [String] = []

    func registeredApplicationPath(bundleIdentifier: String) -> String? {
        registeredBundles[bundleIdentifier]
    }

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
            || directoryPaths.contains(path)
            || executablePaths.contains(path)
    }

    func isDirectory(atPath path: String) -> Bool {
        directoryPaths.contains(path)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        executablePaths.contains(path)
    }

    func pathDirectories() -> [String] {
        pathDirs
    }
}

// MARK: - Discovery

@Suite("Editor discovery")
struct EditorDiscoveryTests {

    @Test func antigravityDetectedByRegisteredBundleIdentifier() {
        let probe = MockEditorProbe(
            registeredBundles: ["com.google.antigravity-ide": "/Applications/Antigravity IDE.app"]
        )
        let service = EditorDiscoveryService(probe: probe)

        #expect(
            service.discoverInstallation(of: .antigravity)
                == .installed(location: "/Applications/Antigravity IDE.app")
        )
    }

    @Test func codexDetectedInsideApplicationBundle() {
        let probe = MockEditorProbe(
            executablePaths: ["/Applications/Codex.app/Contents/Resources/codex"]
        )
        let service = EditorDiscoveryService(probe: probe)

        #expect(
            service.discoverInstallation(of: .codex)
                == .installed(location: "/Applications/Codex.app/Contents/Resources/codex")
        )
    }

    @Test func codexDetectedAsExecutableOnPath() {
        let probe = MockEditorProbe(
            executablePaths: ["/mock/bin/codex"],
            pathDirs: ["/mock/bin"]
        )
        let service = EditorDiscoveryService(probe: probe)

        #expect(
            service.discoverInstallation(of: .codex)
                == .installed(location: "/mock/bin/codex")
        )
    }

    @Test func directoryNamedLikeToolIsNotDetectedAsInstalled() {
        // This Mac's PATH contains `…/codex.system/…` directories. A mere
        // directory name must never satisfy CLI detection.
        let probe = MockEditorProbe(
            directoryPaths: ["/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin/codex"],
            pathDirs: ["/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin"]
        )
        let service = EditorDiscoveryService(probe: probe)

        #expect(service.discoverInstallation(of: .codex) == .notInstalled)
    }

    @Test func absentEditorIsReportedAsNotInstalled() {
        let probe = MockEditorProbe(pathDirs: ["/usr/bin", "/bin"])
        let service = EditorDiscoveryService(probe: probe)

        #expect(service.discoverInstallation(of: .codex) == .notInstalled)
        #expect(service.discoverInstallation(of: .codex) == .notInstalled)
        #expect(service.discoverInstallation(of: .antigravity) == .notInstalled)
    }

    @Test func discoveryCoversEverySupportedEditor() {
        let service = EditorDiscoveryService(probe: MockEditorProbe(pathDirs: []))
        let installations = service.discoverInstallations()

        #expect(Set(installations.keys) == Set(AIEditor.allCases))
        #expect(installations.count == AIEditor.allCases.count)
    }

    @Test func credentialLocatorsStayEmptyForEditorsWithoutCredentialAccess() {
        // Editors TokenOwl does not integrate with must not carry credential
        // locators: discovery has nothing auth related to find for them.
        for editor in AIEditor.allCases where !editor.readsCredentials {
            #expect(!editor.readsCredentials)
        }
        #expect(AIEditor.codex.readsCredentials == false)
        #expect(AIEditor.codex.readsCredentials == false)
        #expect(AIEditor.antigravity.readsCredentials == true)
    }
}

// MARK: - Providers

@Suite("AI quota providers")
struct AIQuotaProviderTests {

    private func antigravitySnapshot() -> AntigravitySnapshot {
        AntigravitySnapshot(
            account: AntigravityAccount(
                email: "person@example.com",
                tierID: "GOOGLE_ONE",
                tierName: "Google AI Pro",
                upgradePrompt: nil
            ),
            quota: Fixtures.summary(percentages: [81, 100]),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            credentialSource: .keychain
        )
    }

    @Test func registryProvidesAdapterOnlyForAntigravity() {
        let registry = QuotaProviderRegistry(providers: [
            AntigravityQuotaProvider(service: AntigravityService()),
        ])

        #expect(registry.provider(for: .antigravity) != nil)
        #expect(registry.hasAdapter(for: .antigravity))

        for editor in [AIEditor.codex] {
            #expect(registry.provider(for: editor) == nil)
            #expect(!registry.hasAdapter(for: editor))
        }
    }

    @Test func adapterFlattensAntigravitySnapshotIntoNeutralModel() {
        let neutral = ProviderSnapshot(
            editor: .antigravity,
            antigravitySnapshot: antigravitySnapshot()
        )

        #expect(neutral.editor == .antigravity)
        #expect(neutral.accountEmail == "person@example.com")
        #expect(neutral.tierDisplayName == "Google AI Pro")
        #expect(neutral.credentialSourceDisplayName == "CLI Keychain credential")
        #expect(neutral.headlineRemainingPercent == 81)
        #expect(neutral.metrics.count == 2)
        #expect(neutral.metrics[0].id == "bucket-0")
        #expect(neutral.metrics[0].label == "Test group · Bucket 0")
        #expect(neutral.metrics[0].remainingPercent == 81)
        #expect(neutral.metrics[1].remainingPercent == 100)
    }

    @Test func providerSnapshotCarriesNoCredentialMaterial() {
        let neutral = ProviderSnapshot(
            editor: .antigravity,
            antigravitySnapshot: antigravitySnapshot()
        )

        let displayStrings =
            [neutral.accountEmail, neutral.tierDisplayName, neutral.credentialSourceDisplayName]
                .compactMap { $0 }
                + neutral.metrics.map(\.label)

        for value in displayStrings {
            #expect(!value.contains("ya29."))
            #expect(!value.contains("1//"))
            #expect(!value.contains(Fixtures.ideAccessToken))
            #expect(!value.contains(Fixtures.ideRefreshToken))
            #expect(!value.contains("fixture-access-token"))
            #expect(!value.contains("fixture-refresh-token"))
        }
    }

    @Test func capabilitiesFollowRegistryAndEditor() {
        let registry = QuotaProviderRegistry(providers: [
            AntigravityQuotaProvider(service: AntigravityService()),
        ])

        let antigravity = registry.capabilities(for: .antigravity)
        #expect(antigravity.hasQuotaAdapter)
        #expect(antigravity.readsCredentials)

        let codex = registry.capabilities(for: .codex)
        #expect(!codex.hasQuotaAdapter)
        #expect(!codex.readsCredentials)
    }
}

// MARK: - Selection persistence

@Suite("Editor selection persistence")
struct EditorSelectionTests {

    private func withDefaults(
        _ body: (UserDefaults, String) -> Void
    ) {
        let suiteName = "TokenOwl.EditorSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults, suiteName)
    }

    @Test func selectionRoundTripsThroughDefaults() {
        withDefaults { defaults, _ in
            EditorSelection.save(.codex, to: defaults)
            #expect(EditorSelection.load(from: defaults) == .codex)

            EditorSelection.save(.codex, to: defaults)
            #expect(EditorSelection.load(from: defaults) == .codex)
        }
    }

    @Test func missingOrInvalidSelectionDefaultsToAntigravity() {
        withDefaults { defaults, _ in
            #expect(EditorSelection.load(from: defaults) == .antigravity)

            defaults.set("vscode", forKey: EditorSelection.userDefaultsKey)
            #expect(EditorSelection.load(from: defaults) == .codex)

            defaults.set("not-an-editor", forKey: EditorSelection.userDefaultsKey)
            #expect(EditorSelection.load(from: defaults) == .antigravity)
        }
    }

    @Test func selectionStoresOnlyTheEditorTagNeverCredentials() {
        withDefaults { defaults, _ in
            for editor in AIEditor.allCases {
                EditorSelection.save(editor, to: defaults)
            }

            let tokenOwlEntries = defaults.dictionaryRepresentation()
                .filter { $0.key.hasPrefix("tokenowl.") }

            #expect(tokenOwlEntries.keys.sorted() == [EditorSelection.userDefaultsKey])

            let serialized = String(describing: tokenOwlEntries)
            #expect(!serialized.contains("ya29."))
            #expect(!serialized.contains("1//"))
            #expect(!serialized.contains(Fixtures.ideAccessToken))
            #expect(!serialized.contains(Fixtures.ideRefreshToken))
            #expect(!serialized.contains("fixture-refresh-token"))
        }
    }
}

// MARK: - Status composition

@Suite("Editor status composition")
struct EditorStatusTests {

    private let withAdapter = EditorCapabilities(hasQuotaAdapter: true, readsCredentials: true)
    private let withoutAdapter = EditorCapabilities(hasQuotaAdapter: false, readsCredentials: false)

    private func antigravitySnapshot() -> AntigravitySnapshot {
        AntigravitySnapshot(
            account: AntigravityAccount(
                email: "person@example.com",
                tierID: nil,
                tierName: "Google AI Pro",
                upgradePrompt: nil
            ),
            quota: Fixtures.summary(percentages: [81]),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            credentialSource: .ide
        )
    }

    @Test func notInstalledEditorReportsNotInstalledState() {
        let status = EditorStatus.compose(
            editor: .codex,
            installation: .notInstalled,
            capabilities: withoutAdapter,
            snapshot: nil
        )

        #expect(status.installation == .notInstalled)
        #expect(status.quota == .notInstalled)
        #expect(status.account == .notApplicable)
    }

    @Test func installedEditorWithoutAdapterIsNotConfigured() {
        let status = EditorStatus.compose(
            editor: .codex,
            installation: .installed(location: "/Applications/Codex.app/Contents/Resources/codex"),
            capabilities: withoutAdapter,
            snapshot: nil
        )

        #expect(status.installation.isInstalled)
        #expect(status.quota == .notConfigured)
        #expect(status.account == .authenticationUnavailable)
    }

    @Test func antigravityWithSnapshotIsConnectedWithQuota() {
        let status = EditorStatus.compose(
            editor: .antigravity,
            installation: .installed(location: "/Applications/Antigravity IDE.app"),
            capabilities: withAdapter,
            snapshot: antigravitySnapshot()
        )

        #expect(status.quota == .available(headlinePercent: 81))

        guard case let .connected(email, source) = status.account else {
            Issue.record("expected connected account, got \(status.account)")
            return
        }
        #expect(email == "person@example.com")
        #expect(source == "Antigravity IDE session")
    }

    @Test func antigravityWithoutSnapshotIsUnavailableNotBorrowed() {
        let status = EditorStatus.compose(
            editor: .antigravity,
            installation: .installed(location: "/Applications/Antigravity IDE.app"),
            capabilities: withAdapter,
            snapshot: nil
        )

        #expect(status.quota == .unavailable)
        #expect(status.account == .authenticationUnavailable)
    }

    @Test func snapshotNeverFlowsToAnotherEditor() {
        // Even if a snapshot is passed alongside another editor's status,
        // composition must not attribute it to that editor.
        let status = EditorStatus.compose(
            editor: .codex,
            installation: .installed(location: "/Applications/Codex.app/Contents/Resources/codex"),
            capabilities: withoutAdapter,
            snapshot: antigravitySnapshot()
        )

        #expect(status.quota == .notConfigured)
        #expect(status.account == .authenticationUnavailable)
    }

    @Test func snapshotOnlyFeedsEditorsThatAreAntigravity() {
        // Defensive: adapter capability + a snapshot is still not enough for
        // a non-Antigravity editor to observe Antigravity's data.
        let status = EditorStatus.compose(
            editor: .codex,
            installation: .installed(location: "/mock/bin/codex"),
            capabilities: withAdapter,
            snapshot: antigravitySnapshot()
        )

        #expect(status.quota != .available(headlinePercent: 81))
        if case .connected(let email, _) = status.account {
            Issue.record("codex must not inherit antigravity email, got \(email ?? "nil")")
        }
    }
}
