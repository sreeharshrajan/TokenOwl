import Foundation

/// Debug logging that is off unless `TOKENOWL_DEBUG=1` and that scrubs any
/// token-shaped material before it can reach a terminal or a log file.
///
/// Invariants: no access token, refresh token, or Authorization header is ever
/// emitted by TokenOwl, even in debug builds.
public enum RedactedLogger {

    /// Debug logging is a debug-build affordance only: release builds never
    /// log, regardless of the process environment.
    public static var isEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TOKENOWL_DEBUG"] == "1"
        #else
        return false
        #endif
    }

    public static func log(_ message: String) {
        guard isEnabled else { return }

        // stderr keeps diagnostics off the CLI's normal output stream and is
        // unbuffered, so debug lines show up immediately in a redirected log.
        let line = "[TokenOwl] \(redact(message))\n"
        if let data = line.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }

    public static func redact(_ message: String) -> String {
        var result = message

        for pattern in RedactionPattern.all {
            result = result.replacingOccurrences(
                of: pattern.pattern,
                with: pattern.replacement,
                options: .regularExpression
            )
        }

        return result
    }

    private struct RedactionPattern {
        let pattern: String
        let replacement: String

        static let all: [RedactionPattern] = [
            // Authorization: Bearer <token>
            RedactionPattern(
                pattern: #"(?i)(authorization[^\S\r\n]*[:=][^\S\r\n]*)(?:bearer[^\S\r\n]+)?\S+"#,
                replacement: "$1<redacted>"
            ),
            // access_token=... / refresh_token=... in form bodies
            RedactionPattern(
                pattern: #"(?i)\b(access_token|refresh_token|id_token|client_secret)=[^&\s]+"#,
                replacement: "$1=<redacted>"
            ),
            // "access_token": "..." in JSON payloads
            RedactionPattern(
                pattern: #"(?i)("(?:access_token|refresh_token|id_token|client_secret)"\s*:\s*")[^"]*"#,
                replacement: "$1<redacted>"
            ),
            // Google access tokens are prefixed with `ya29.`
            RedactionPattern(
                pattern: #"ya29\.[A-Za-z0-9._\-]+"#,
                replacement: "<redacted>"
            ),
            // Bare refresh tokens (`1//…`), as carried in OAuth form bodies
            // and inside the IDE session envelope, even without a
            // `refresh_token=` label around them.
            RedactionPattern(
                pattern: #"\b1//[A-Za-z0-9._\-]{20,}"#,
                replacement: "<redacted>"
            ),
            // OpenAI / Codex API key tokens (`sk-...`)
            RedactionPattern(
                pattern: #"\bsk-[A-Za-z0-9._\-]{8,}"#,
                replacement: "<redacted>"
            ),
            // token=... / token: ... in diagnostic output or URLs
            RedactionPattern(
                pattern: #"(?i)\btoken[^\S\r\n]*[:=][^\S\r\n]*\S+"#,
                replacement: "token=<redacted>"
            ),
            // Generic Bearer <token>
            RedactionPattern(
                pattern: #"(?i)\bBearer\s+\S+"#,
                replacement: "Bearer <redacted>"
            ),
            // JWT-like structures (header.payload.signature)
            RedactionPattern(
                pattern: #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+"#,
                replacement: "<redacted>"
            ),
            // Emails
            RedactionPattern(
                pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
                replacement: "<redacted>"
            ),
        ]
    }
}
