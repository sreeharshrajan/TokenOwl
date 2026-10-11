import Testing
@testable import TokenOwlCore

struct GoogleOAuthConfigurationTests {
    @Test func readsMatchingClientFromIDEModule() {
        let source = #"unrelated="999-other.apps.googleusercontent.com";q({"out-build/vs/platform/cloudCode/common/oauthClient.js"(){id="123-fixture.apps.googleusercontent.com",secret="GOCSPX-fixture",other="456-other.apps.googleusercontent.com",otherSecret="GOCSPX-other"}})"#
        #expect(GoogleOAuthConfiguration.parse(source) == GoogleOAuthConfiguration(
            clientID: "123-fixture.apps.googleusercontent.com", clientSecret: "GOCSPX-fixture"
        ))
    }

    @Test func rejectsUnrelatedOrIncompleteConfiguration() {
        #expect(GoogleOAuthConfiguration.parse(#"id="123-fixture.apps.googleusercontent.com",secret="GOCSPX-fixture""#) == nil)
        #expect(GoogleOAuthConfiguration.parse(#"vs/platform/cloudCode/common/oauthClient.js id="123-fixture.apps.googleusercontent.com""#) == nil)
    }

    @Test func pairedOverridesWorkWithoutInstallation() {
        #expect(GoogleOAuthConfiguration.resolve(
            environment: ["GOOGLE_OAUTH_CLIENT_ID": "custom-id", "GOOGLE_OAUTH_CLIENT_SECRET": "custom-secret"],
            installation: .notInstalled
        ) == GoogleOAuthConfiguration(clientID: "custom-id", clientSecret: "custom-secret"))
        #expect(GoogleOAuthConfiguration.resolve(
            environment: ["GOOGLE_OAUTH_CLIENT_ID": "custom-id"], installation: .notInstalled
        ) == nil)
    }
}
