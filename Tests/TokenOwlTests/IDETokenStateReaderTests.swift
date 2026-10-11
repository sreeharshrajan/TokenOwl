import Foundation
import SQLite3
import Testing
@testable import TokenOwlCore

/// `SQLITE_TRANSIENT`: SQLite copies bound values immediately.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct IDETokenStateReaderTests {

    private let envelope = Fixtures.ideSessionEnvelope

    @Test func readsBothTokensFromTheStoredEnvelope() throws {
        let database = try makeDatabase(
            entries: [IDETokenStateReader.oauthTokenKey: envelope]
        )
        defer { try? FileManager.default.removeItem(at: database) }

        let session = try IDETokenStateReader(databasePath: database.path).readSession()

        #expect(session.accessToken == Fixtures.ideAccessToken)
        #expect(session.refreshToken == Fixtures.ideRefreshToken)
    }

    @Test func readsAnAccessOnlyEnvelope() throws {
        let database = try makeDatabase(
            entries: [IDETokenStateReader.oauthTokenKey: Fixtures.ideSessionEnvelopeAccessOnly]
        )
        defer { try? FileManager.default.removeItem(at: database) }

        let session = try IDETokenStateReader(databasePath: database.path).readSession()

        #expect(session.accessToken == Fixtures.ideAccessToken)
        #expect(session.refreshToken == nil)
    }

    @Test func readsABareTokenValue() throws {
        // The earlier format: a plain access token with no envelope.
        let database = try makeDatabase(
            entries: [IDETokenStateReader.oauthTokenKey: Fixtures.ideAccessToken]
        )
        defer { try? FileManager.default.removeItem(at: database) }

        let session = try IDETokenStateReader(databasePath: database.path).readSession()

        #expect(session.accessToken == Fixtures.ideAccessToken)
        #expect(session.refreshToken == nil)
    }

    @Test func missingDatabaseThrows() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenowl-absent-\(UUID().uuidString).vscdb")
            .path

        #expect(throws: IDETokenStateError.databaseUnreadable) {
            try IDETokenStateReader(databasePath: path).readSession()
        }
    }

    @Test func absentKeyThrows() throws {
        let database = try makeDatabase(entries: ["some.other.key": "value"])
        defer { try? FileManager.default.removeItem(at: database) }

        #expect(throws: IDETokenStateError.rowNotFound) {
            try IDETokenStateReader(databasePath: database.path).readSession()
        }
    }

    @Test func emptyValueThrows() throws {
        let database = try makeDatabase(
            entries: [IDETokenStateReader.oauthTokenKey: ""]
        )
        defer { try? FileManager.default.removeItem(at: database) }

        #expect(throws: IDETokenStateError.emptyToken) {
            try IDETokenStateReader(databasePath: database.path).readSession()
        }
    }

    @Test func valueWithoutAnyTokenThrows() throws {
        let database = try makeDatabase(
            entries: [IDETokenStateReader.oauthTokenKey: "just some ordinary text"]
        )
        defer { try? FileManager.default.removeItem(at: database) }

        #expect(throws: IDETokenStateError.tokenNotRecognized) {
            try IDETokenStateReader(databasePath: database.path).readSession()
        }
    }

    @Test func unreadableRowTypeThrows() throws {
        // A blob with no valid text representation is not a usable token.
        let database = try makeBlobDatabase(
            entries: [IDETokenStateReader.oauthTokenKey: Data([0x00, 0x01, 0x02])]
        )
        defer { try? FileManager.default.removeItem(at: database) }

        // sqlite3_column_text converts blobs best-effort; a leading NUL
        // truncates to an empty C string, which we treat as unusable.
        #expect(throws: IDETokenStateError.emptyToken) {
            try IDETokenStateReader(databasePath: database.path).readSession()
        }
    }

    @Test func readsOnlyTheConfiguredKey() throws {
        let database = try makeDatabase(
            entries: [
                IDETokenStateReader.oauthTokenKey: Fixtures.ideSessionEnvelope,
                "some.other.key": Fixtures.ideAccessToken
            ]
        )
        defer { try? FileManager.default.removeItem(at: database) }

        let reader = IDETokenStateReader(
            databasePath: database.path,
            key: "some.other.key"
        )

        #expect(try reader.readSession().accessToken == Fixtures.ideAccessToken)
    }

    @Test func defaultPathLookupIsOverridableForDevelopment() throws {
        // No real IDE database is opened here: the environment override is
        // exercised against a fixture path instead.
        let database = try makeDatabase(
            entries: [IDETokenStateReader.oauthTokenKey: envelope]
        )
        defer { try? FileManager.default.removeItem(at: database) }

        setenv("TOKENOWL_IDE_STATE_PATH", database.path, 1)
        defer { unsetenv("TOKENOWL_IDE_STATE_PATH") }

        #expect(try IDETokenStateReader().readSession().accessToken == Fixtures.ideAccessToken)
    }

    @Test func errorDescriptionsNeverCarryDatabaseDetails() {
        // User-facing copy only: no path, no key, no token.
        let message = ErrorPresentation.message(
            for: IDETokenStateError.databaseNotFound(path: "/Users/person/Library/secret.vscdb")
        )

        #expect(message == "The Antigravity IDE session was not found.")
        #expect(!message.contains("secret.vscdb"))
        #expect(!message.contains("person"))

        #expect(
            ErrorPresentation.message(for: IDETokenStateError.tokenNotRecognized)
                == "The Antigravity IDE session token could not be read."
        )
    }

    // MARK: Fixtures

    /// Creates a minimal VS Code-compatible state database.
    private func makeDatabase(entries: [String: String]) throws -> URL {
        let url = try createDatabaseFile()
        guard let database = open(url: url, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) else {
            throw IDETokenStateError.databaseUnreadable
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(
            database,
            "CREATE TABLE ItemTable (key TEXT UNIQUE, value BLOB)",
            nil, nil, nil
        ) == SQLITE_OK else {
            throw IDETokenStateError.databaseUnreadable
        }

        for (key, value) in entries {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
                -1, &statement, nil
            ) == SQLITE_OK, let statement else {
                throw IDETokenStateError.databaseUnreadable
            }
            sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, value, -1, sqliteTransient)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_finalize(statement)
                throw IDETokenStateError.databaseUnreadable
            }
            sqlite3_finalize(statement)
        }

        return url
    }

    private func makeBlobDatabase(entries: [String: Data]) throws -> URL {
        let url = try createDatabaseFile()
        guard let database = open(url: url, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) else {
            throw IDETokenStateError.databaseUnreadable
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(
            database,
            "CREATE TABLE ItemTable (key TEXT UNIQUE, value BLOB)",
            nil, nil, nil
        ) == SQLITE_OK else {
            throw IDETokenStateError.databaseUnreadable
        }

        for (key, value) in entries {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
                -1, &statement, nil
            ) == SQLITE_OK, let statement else {
                throw IDETokenStateError.databaseUnreadable
            }
            sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
            value.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                sqlite3_finalize(statement)
                throw IDETokenStateError.databaseUnreadable
            }
            sqlite3_finalize(statement)
        }

        return url
    }

    private func createDatabaseFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenowl-fixture-\(UUID().uuidString).vscdb")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw IDETokenStateError.databaseUnreadable
        }
        return url
    }

    private func open(url: URL, flags: Int32) -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        return database
    }
}
