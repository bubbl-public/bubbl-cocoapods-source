import Foundation
import Security
import SQLite3

struct BubblStoredState: Codable, Sendable, Equatable {
    var installId: String
    var correlationId: String?
    var segments: [String]
    var pushToken: String?

    static func fresh() -> BubblStoredState {
        BubblStoredState(installId: UUID().uuidString, correlationId: nil, segments: [], pushToken: nil)
    }
}

struct BubblQueuedRequest: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var path: String
    var body: Data
    var idempotencyKey: String
    var attempts: Int
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        path: String,
        body: Data,
        idempotencyKey: String = UUID().uuidString,
        attempts: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.body = body
        self.idempotencyKey = idempotencyKey
        self.attempts = attempts
        self.createdAt = createdAt
    }
}

struct BubblPersistentStore: Sendable {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let secureStateStore: BubblKeychainStateStore

    init(directory: URL? = nil) {
        let resolvedDirectory = directory ?? Self.defaultDirectory()
        self.directory = resolvedDirectory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        self.secureStateStore = BubblKeychainStateStore(service: Self.keychainService(for: resolvedDirectory))
    }

    func loadState() throws -> BubblStoredState {
        try ensureDirectory()

        if let state = try secureStateStore.loadState() {
            return state
        }

        let migratedState = try migrateLegacyFileState()
        try saveState(migratedState)
        return migratedState
    }

    func saveState(_ state: BubblStoredState) throws {
        try ensureDirectory()
        try secureStateStore.saveState(state)
    }

    func loadConfig() throws -> BubblConfig? {
        try ensureDirectory()
        let url = configURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(BubblConfig.self, from: data)
    }

    func saveConfig(_ config: BubblConfig) throws {
        try ensureDirectory()
        try encoder.encode(config).write(to: configURL, options: [.atomic])
    }

    func append(_ request: BubblQueuedRequest) throws {
        try queueStore.insert(request)
    }

    func loadQueue() throws -> [BubblQueuedRequest] {
        try queueStore.loadAll()
    }

    func saveQueue(_ queue: [BubblQueuedRequest]) throws {
        try queueStore.replaceAll(queue)
    }

    func saveRuntimeCache(_ data: Data, named name: String) throws {
        try ensureDirectory()
        try data.write(to: runtimeCacheURL(name), options: [.atomic])
    }

    func loadRuntimeCache(named name: String) throws -> Data? {
        try ensureDirectory()
        let url = runtimeCacheURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return try Data(contentsOf: url)
    }

    func pendingCount() throws -> Int {
        try queueStore.count()
    }

    func deleteSecureStateForTests() throws {
        try secureStateStore.deleteState()
    }

    private var queueStore: BubblSQLiteQueueStore {
        BubblSQLiteQueueStore(databaseURL: queueURL)
    }

    private func migrateLegacyFileState() throws -> BubblStoredState {
        guard FileManager.default.fileExists(atPath: legacyStateURL.path) else {
            return BubblStoredState.fresh()
        }

        let data = try Data(contentsOf: legacyStateURL)
        return try decoder.decode(BubblStoredState.self, from: data)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return base.appendingPathComponent("tech.bubbl.sdk", isDirectory: true)
    }

    private static func keychainService(for directory: URL) -> String {
        let suffix = directory.path.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "_"
        }

        return "tech.bubbl.sdk." + String(suffix).suffix(180)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var legacyStateURL: URL {
        directory.appendingPathComponent("state.json")
    }

    private var queueURL: URL {
        directory.appendingPathComponent("ingest-queue.sqlite")
    }

    private var configURL: URL {
        directory.appendingPathComponent("config.json")
    }

    private func runtimeCacheURL(_ name: String) -> URL {
        directory.appendingPathComponent("runtime-\(name).json")
    }
}

private struct BubblKeychainStateStore: Sendable {
    private let service: String
    private let account = "state"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String) {
        self.service = service
    }

    func loadState() throws -> BubblStoredState? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw BubblError.storage("Keychain read failed with status \(status).")
        }

        guard let data = item as? Data else {
            throw BubblError.storage("Keychain state was not data.")
        }

        return try decoder.decode(BubblStoredState.self, from: data)
    }

    func saveState(_ state: BubblStoredState) throws {
        let data = try encoder.encode(state)
        var query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw BubblError.storage("Keychain update failed with status \(updateStatus).")
        }

        query[kSecValueData as String] = data
        let addStatus = SecItemAdd(query as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw BubblError.storage("Keychain add failed with status \(addStatus).")
        }
    }

    func deleteState() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BubblError.storage("Keychain delete failed with status \(status).")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct BubblSQLiteQueueStore: Sendable {
    private let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func insert(_ request: BubblQueuedRequest) throws {
        try withDatabase { database in
            try execute(
                database,
                """
                INSERT OR REPLACE INTO ingest_queue
                (id, path, body, idempotency_key, attempts, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(request.id),
                    .text(request.path),
                    .blob(request.body),
                    .text(request.idempotencyKey),
                    .int(request.attempts),
                    .text(Self.formatDate(request.createdAt))
                ]
            )
        }
    }

    func loadAll() throws -> [BubblQueuedRequest] {
        try withDatabase { database in
            var statement: OpaquePointer?
            let sql = """
                SELECT id, path, body, idempotency_key, attempts, created_at
                FROM ingest_queue
                ORDER BY created_at ASC
                """

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw sqliteError(database, fallback: "Failed to prepare queue load.")
            }

            defer { sqlite3_finalize(statement) }

            var requests: [BubblQueuedRequest] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = columnText(statement, 0)
                let path = columnText(statement, 1)
                let body = columnBlob(statement, 2)
                let idempotencyKey = columnText(statement, 3)
                let attempts = Int(sqlite3_column_int(statement, 4))
                let createdAt = Self.parseDate(columnText(statement, 5)) ?? Date()

                requests.append(
                    BubblQueuedRequest(
                        id: id,
                        path: path,
                        body: body,
                        idempotencyKey: idempotencyKey,
                        attempts: attempts,
                        createdAt: createdAt
                    )
                )
            }

            return requests
        }
    }

    func replaceAll(_ requests: [BubblQueuedRequest]) throws {
        try withDatabase { database in
            try execute(database, "BEGIN IMMEDIATE TRANSACTION")

            do {
                try execute(database, "DELETE FROM ingest_queue")

                for request in requests {
                    try execute(
                        database,
                        """
                        INSERT OR REPLACE INTO ingest_queue
                        (id, path, body, idempotency_key, attempts, created_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        bindings: [
                            .text(request.id),
                            .text(request.path),
                            .blob(request.body),
                            .text(request.idempotencyKey),
                            .int(request.attempts),
                            .text(Self.formatDate(request.createdAt))
                        ]
                    )
                }

                try execute(database, "COMMIT")
            } catch {
                try? execute(database, "ROLLBACK")
                throw error
            }
        }
    }

    func count() throws -> Int {
        try withDatabase { database in
            var statement: OpaquePointer?
            let sql = "SELECT COUNT(*) FROM ingest_queue"

            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw sqliteError(database, fallback: "Failed to prepare queue count.")
            }

            defer { sqlite3_finalize(statement) }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw sqliteError(database, fallback: "Failed to count queue.")
            }

            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private func withDatabase<T>(_ work: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            defer { sqlite3_close(database) }
            throw sqliteError(database, fallback: "Failed to open SQLite queue.")
        }

        defer { sqlite3_close(database) }
        try configure(database)
        return try work(database)
    }

    private func configure(_ database: OpaquePointer) throws {
        try execute(database, "PRAGMA journal_mode=WAL")
        try execute(database, "PRAGMA synchronous=NORMAL")
        try execute(
            database,
            """
            CREATE TABLE IF NOT EXISTS ingest_queue (
                id TEXT PRIMARY KEY NOT NULL,
                path TEXT NOT NULL,
                body BLOB NOT NULL,
                idempotency_key TEXT NOT NULL,
                attempts INTEGER NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
    }

    private func execute(_ database: OpaquePointer, _ sql: String, bindings: [SQLiteBinding] = []) throws {
        if bindings.isEmpty {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw sqliteError(database, fallback: "Failed to execute SQLite statement.")
            }

            return
        }

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(database, fallback: "Failed to prepare SQLite statement.")
        }

        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            try bind(binding, to: statement, at: Int32(index + 1), database: database)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(database, fallback: "Failed to execute SQLite statement.")
        }
    }

    private func bind(_ binding: SQLiteBinding, to statement: OpaquePointer?, at index: Int32, database: OpaquePointer) throws {
        let status: Int32

        switch binding {
        case let .text(value):
            status = sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case let .int(value):
            status = sqlite3_bind_int(statement, index, Int32(value))
        case let .blob(value):
            status = value.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
            }
        }

        guard status == SQLITE_OK else {
            throw sqliteError(database, fallback: "Failed to bind SQLite value.")
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else {
            return ""
        }

        return String(cString: text)
    }

    private func columnBlob(_ statement: OpaquePointer?, _ index: Int32) -> Data {
        let bytes = sqlite3_column_blob(statement, index)
        let count = Int(sqlite3_column_bytes(statement, index))

        guard let bytes, count > 0 else {
            return Data()
        }

        return Data(bytes: bytes, count: count)
    }

    private func sqliteError(_ database: OpaquePointer?, fallback: String) -> BubblError {
        if let message = sqlite3_errmsg(database) {
            return .storage(String(cString: message))
        }

        return .storage(fallback)
    }

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private enum SQLiteBinding {
    case text(String)
    case int(Int)
    case blob(Data)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
