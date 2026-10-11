import Foundation

/// OAuth application metadata, not user credentials. Read only from the IDE
/// whose login issued our refresh token; never persist or log the values.
struct GoogleOAuthConfiguration: Equatable, Sendable {
    let clientID: String
    let clientSecret: String

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        installation: EditorInstallation = EditorDiscoveryService().discoverInstallation(of: .antigravity)
    ) -> Self? {
        // Overrides must be a pair: mixing clients makes refresh tokens fail.
        if let id = environment["GOOGLE_OAUTH_CLIENT_ID"], !id.isEmpty,
           let secret = environment["GOOGLE_OAUTH_CLIENT_SECRET"], !secret.isEmpty {
            return Self(clientID: id, clientSecret: secret)
        }
        guard case .installed(let path) = installation,
              let source = try? String(contentsOfFile: path + "/Contents/Resources/app/out/main.js", encoding: .utf8)
        else { return nil }
        return parse(source)
    }

    static func parse(_ source: String) -> Self? {
        // Bound the search to the IDE's OAuth module. It may contain other
        // Google clients, so select the first complete ID/secret pair together.
        guard let module = source.range(of: "vs/platform/cloudCode/common/oauthClient.js") else { return nil }
        let section = String(source[module.upperBound...].prefix(4096))
        let pattern = #"["']([0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com)["']\s*,\s*[A-Za-z0-9_$]+\s*=\s*["'](GOCSPX-[A-Za-z0-9_-]+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: section, range: NSRange(section.startIndex..., in: section)),
              let id = Range(match.range(at: 1), in: section),
              let secret = Range(match.range(at: 2), in: section)
        else { return nil }
        return Self(clientID: String(section[id]), clientSecret: String(section[secret]))
    }
}
