import Foundation
import SQLite3

/// Errors from reading the IDE's state database.
///
/// Messages are safe to show in the UI. They never contain the token value,
/// the database contents, or raw SQLite error text.
public enum IDETokenStateError: Error, Equatable, LocalizedError {
    case databaseNotFound(path: String)
    case databaseUnreadable
    case rowNotFound
    case emptyToken
    case tokenNotRecognized

    public var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "The Antigravity IDE session was not found."
        case .databaseUnreadable:
            return "The Antigravity IDE session could not be read."
        case .rowNotFound:
            return "No session token was found in the Antigravity IDE state."
        case .emptyToken:
            return "The Antigravity IDE session token is empty."
        case .tokenNotRecognized:
            return "The Antigravity IDE session token could not be read."
        }
    }
}

/// The token material recovered from the IDE's stored session.
///
/// Either part can be missing: an envelope that only carries an access token
/// yields a refresh token of `nil`, and the credential then cannot renew
/// itself (the service falls back to the next source instead).
public struct IDESessionState: Equatable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?

    public init(accessToken: String? = nil, refreshToken: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

/// The single capability `IDECredentialProvider` needs.
public protocol IDETokenStateReading: Sendable {
    func readSession() throws -> IDESessionState
}

/// Reads the IDE's active session from its state database.
///
/// Scope, deliberately narrow:
/// - **read-only** — opens the database with `SQLITE_OPEN_READONLY` and never
///   writes, migrates, or locks it for writing;
/// - **one key** — `antigravityUnifiedStateSync.oauthToken`;
/// - **no decryption** — Electron Safe Storage is never touched. The stored
///   value is a base64 envelope whose nested blob carries the session tokens
///   as plaintext, so unwrapping is decoding, not decryption;
/// - **no logging of the value** — tokens leave this type only as the return
///   value, never through `RedactedLogger` or `ErrorPresentation`.
public struct IDETokenStateReader: IDETokenStateReading {

    /// The single state-sync key this reader understands.
    public static let oauthTokenKey = "antigravityUnifiedStateSync.oauthToken"

    /// Where the Antigravity IDE keeps its VS Code-compatible state database.
    public static let defaultDatabasePath =
        "/Library/Application Support/Antigravity IDE/User/globalStorage/state.vscdb"

    private let databasePathOverride: String?
    private let key: String

    public init(
        databasePath: String? = nil,
        key: String = IDETokenStateReader.oauthTokenKey
    ) {
        self.databasePathOverride = databasePath
        self.key = key
    }

    public func readSession() throws -> IDESessionState {
        try Self.parseSession(from: try readStoredValue())
    }

    // MARK: Parsing

    /// Unwraps the stored value and recovers the session tokens.
    ///
    /// Two shapes are accepted so a format change degrades to
    /// "token not recognized" instead of to a wrong token:
    /// - a **bare** `ya29.…` / `1//…` value (as observed in an earlier phase);
    /// - the **base64 envelope** observed now: outer base64 → JSON state with
    ///   `oauthTokenInfoSentinelKey` → nested base64 blob → tokens.
    ///
    /// A layer only answers for itself: both tokens are taken from the same
    /// decoded layer when possible, and deeper layers are preferred over
    /// shallower ones, so a token-shaped coincidence inside base64 text (for
    /// example `1//…`) can never shadow the real nested token.
    static func parseSession(from value: String) throws -> IDESessionState {
        guard !value.isEmpty else {
            throw IDETokenStateError.emptyToken
        }

        // Shallowest (the raw stored value) to deepest (fully unwrapped).
        var candidates = [Data(value.utf8)]
        candidates.append(contentsOf: envelopeLayers(from: value))

        // Pass 1: one layer holding both tokens — the real session blob.
        for layer in candidates {
            let text = Self.text(of: layer)
            if firstMatch(Self.accessTokenPattern, in: text) != nil,
               firstMatch(Self.refreshTokenPattern, in: text) != nil {
                return IDESessionState(
                    accessToken: firstMatch(Self.accessTokenPattern, in: text),
                    refreshToken: firstMatch(Self.refreshTokenPattern, in: text)
                )
            }
        }

        // Pass 2: deepest layer first, accepting whichever token it carries.
        for layer in candidates.reversed() {
            let text = Self.text(of: layer)
            let access = firstMatch(Self.accessTokenPattern, in: text)
            let refresh = firstMatch(Self.refreshTokenPattern, in: text)
            if access != nil || refresh != nil {
                return IDESessionState(accessToken: access, refreshToken: refresh)
            }
        }

        throw IDETokenStateError.tokenNotRecognized
    }

    /// Decodes further base64 layers inside `value`, shallowest first.
    ///
    /// Bounded to three rounds and de-duplicated: a malformed or hostile
    /// value can never send this into an unbounded decode loop.
    private static func envelopeLayers(from value: String) -> [Data] {
        var layers: [Data] = []
        var frontier = [Data(value.utf8)]
        var seen = Set<Data>()
        var rounds = 0

        while !frontier.isEmpty, rounds < 3 {
            rounds += 1
            var next: [Data] = []

            for data in frontier {
                guard seen.insert(data).inserted else { continue }

                // Lossy on purpose: the stored JSON carries a few bytes that
                // are not valid UTF-8, and a failed whole-buffer decode used
                // to stop the unwrapping before the nested session blob.
                // U+FFFD matches neither token pattern nor the base64 run.
                let text = Self.text(of: data)

                if let decoded = decodeBase64(text), decoded != data {
                    next.append(decoded)
                }
                for run in base64Runs(in: text) {
                    if let decoded = decodeBase64(run), decoded != data {
                        next.append(decoded)
                    }
                }
            }

            layers.append(contentsOf: next)
            frontier = next
        }

        return layers
    }

    private static func decodeBase64(_ raw: String) -> Data? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 16 else { return nil }

        let remainder = text.count % 4
        if remainder != 0 {
            text += String(repeating: "=", count: 4 - remainder)
        }

        if let data = Data(base64Encoded: text), !data.isEmpty {
            return data
        }

        let translated = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if translated != text,
           let data = Data(base64Encoded: translated), !data.isEmpty {
            return data
        }

        return nil
    }

    private static func base64Runs(in text: String) -> [String] {
        let matches = base64RunRegex.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func firstMatch(
        _ regex: NSRegularExpression,
        in text: String
    ) -> String? {
        guard let match = regex.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ), let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }

    /// Decoding with replacement characters: binary blobs become searchable
    /// text and a token-shaped byte sequence is never dropped by a decode
    /// failure. Replacement characters cannot match either token pattern.
    private static func text(of data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    // MARK: Patterns

    /// Google access tokens: `ya29.` plus base64url-ish characters. The dot
    /// after `ya29` cannot appear inside base64 text, which makes a
    /// coincidental match in an outer layer very unlikely.
    private static let accessTokenPattern = try! NSRegularExpression(
        pattern: #"ya29\.[A-Za-z0-9_.\-]{10,}"#
    )

    /// Google refresh tokens: `1//` plus a long opaque tail. The `{25,}`
    /// floor keeps a short coincidence inside base64 text from matching.
    private static let refreshTokenPattern = try! NSRegularExpression(
        pattern: #"1//[A-Za-z0-9_.\-]{25,}"#
    )

    /// Long base64-ish runs, used to find nested layers.
    private static let base64RunRegex = try! NSRegularExpression(
        pattern: #"[A-Za-z0-9+/_-]{40,}={0,2}"#
    )

    // MARK: Database

    private func readStoredValue() throws -> String {
        let path = try resolveDatabasePath()

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            sqlite3_close(database)
            throw IDETokenStateError.databaseUnreadable
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM ItemTable WHERE key = ? LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw IDETokenStateError.databaseUnreadable
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw IDETokenStateError.rowNotFound
        }

        guard let cString = sqlite3_column_text(statement, 0) else {
            throw IDETokenStateError.emptyToken
        }

        let value = String(cString: cString)
        guard !value.isEmpty else {
            throw IDETokenStateError.emptyToken
        }

        return value
    }

    // MARK: Paths

    func resolveDatabasePath() throws -> String {
        if let override = databasePathOverride {
            return override
        }

        // Diagnostic path override, honored in debug builds only — a
        // release build always reads the real IDE state location.
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["TOKENOWL_IDE_STATE_PATH"],
           !env.isEmpty {
            return env
        }
        #endif

        let path = FileManager.default.homeDirectoryForCurrentUser.path
            + Self.defaultDatabasePath

        guard FileManager.default.isReadableFile(atPath: path) else {
            throw IDETokenStateError.databaseNotFound(path: path)
        }

        return path
    }
}

/// `SQLITE_TRANSIENT`: SQLite copies the bound text immediately, so the Swift
/// string buffer does not need to outlive the statement.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
