import CSQLite
import Foundation

public struct StoredEvent: Codable, Identifiable, Sendable {
  public var id: UUID
  public var taskID: UUID?
  public var kind: String
  public var payload: JSONValue
  public var createdAt: Date
  public init(
    id: UUID = UUID(), taskID: UUID? = nil, kind: String, payload: JSONValue,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.taskID = taskID
    self.kind = kind
    self.payload = payload
    self.createdAt = createdAt
  }
}

public enum SQLiteStoreError: Error, LocalizedError {
  case open(String)
  case execute(String)
  case prepare(String)
  case bind(String)
  public var errorDescription: String? {
    switch self {
    case .open(let message): "Could not open evidence database: \(message)"
    case .execute(let message): "Database operation failed: \(message)"
    case .prepare(let message): "Could not prepare database statement: \(message)"
    case .bind(let message): "Could not bind database value: \(message)"
    }
  }
}

public actor SQLiteStore {
  // Access is serialized by the actor; `unsafe` is required only so deinit can close the C handle.
  nonisolated(unsafe) private var database: OpaquePointer?
  private let encoder = JSONEncoder(), decoder = JSONDecoder()

  public init(url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var connection: OpaquePointer?
    guard
      sqlite3_open_v2(
        url.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
        nil) == SQLITE_OK
    else {
      let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
      sqlite3_close(connection)
      throw SQLiteStoreError.open(message)
    }
    database = connection
    try Self.execute(
      on: connection,
      sql: "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;")
    try Self.execute(on: connection, sql: Self.schema)
  }

  deinit { sqlite3_close(database) }

  public func saveRepository(_ repository: Repository) throws {
    try write(
      table: "repositories", id: repository.id.uuidString, taskID: nil, kind: nil, date: Date(),
      payload: repository)
  }

  public func saveTask(_ task: DevelopmentTask) throws {
    try write(
      table: "tasks", id: task.id.uuidString, taskID: nil, kind: task.state.rawValue,
      date: task.updatedAt, payload: task)
  }

  public func append(_ event: StoredEvent) throws {
    try write(
      table: "events", id: event.id.uuidString, taskID: event.taskID?.uuidString, kind: event.kind,
      date: event.createdAt, payload: event)
  }

  public func saveEvidence(_ evidence: Evidence, taskID: UUID) throws {
    try write(
      table: "evidence", id: evidence.id.uuidString, taskID: taskID.uuidString,
      kind: evidence.kind.rawValue, date: evidence.createdAt, payload: evidence)
  }

  public func saveAppGraph(_ snapshot: AppGraphSnapshot, key: String, taskID: UUID? = nil) throws {
    try write(
      table: "app_graph", id: key, taskID: taskID?.uuidString, kind: "snapshot", date: Date(),
      payload: snapshot)
  }

  public func saveAppStoreConnection(_ connection: AppStoreConnection) throws {
    try write(
      table: "app_store_connections", id: connection.id.uuidString, taskID: nil,
      kind: connection.keyKind.rawValue, date: connection.validatedAt, payload: connection)
  }

  public func appStoreConnections() throws -> [AppStoreConnection] {
    let statement = try prepare(
      "SELECT payload FROM app_store_connections ORDER BY created_at DESC, id")
    defer { sqlite3_finalize(statement) }
    var values: [AppStoreConnection] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let text = sqlite3_column_text(statement, 0) {
        values.append(
          try decoder.decode(AppStoreConnection.self, from: Data(String(cString: text).utf8)))
      }
    }
    return values
  }

  public func deleteAppStoreConnection(id: UUID) throws {
    let statement = try prepare("DELETE FROM app_store_connections WHERE id = ?")
    defer { sqlite3_finalize(statement) }
    try bind(id.uuidString, at: 1, statement: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw SQLiteStoreError.execute(errorMessage)
    }
  }

  public func appGraph(key: String) throws -> AppGraphSnapshot? {
    let statement = try prepare("SELECT payload FROM app_graph WHERE id = ? LIMIT 1")
    defer { sqlite3_finalize(statement) }
    try bind(key, at: 1, statement: statement)
    guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
      return nil
    }
    return try decoder.decode(AppGraphSnapshot.self, from: Data(String(cString: text).utf8))
  }

  public func events(taskID: UUID) throws -> [StoredEvent] {
    let sql = "SELECT payload FROM events WHERE task_id = ? ORDER BY created_at, id"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(taskID.uuidString, at: 1, statement: statement)
    var values: [StoredEvent] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let text = sqlite3_column_text(statement, 0) {
        values.append(try decoder.decode(StoredEvent.self, from: Data(String(cString: text).utf8)))
      }
    }
    return values
  }

  public func evidence(taskID: UUID) throws -> [Evidence] {
    let sql = "SELECT payload FROM evidence WHERE task_id = ? ORDER BY created_at, id"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(taskID.uuidString, at: 1, statement: statement)
    var values: [Evidence] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let text = sqlite3_column_text(statement, 0) {
        values.append(try decoder.decode(Evidence.self, from: Data(String(cString: text).utf8)))
      }
    }
    return values
  }

  private nonisolated static let schema = """
    CREATE TABLE IF NOT EXISTS repositories (id TEXT PRIMARY KEY, created_at REAL NOT NULL, payload TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, task_id TEXT, kind TEXT, created_at REAL NOT NULL, payload TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, task_id TEXT, kind TEXT NOT NULL, created_at REAL NOT NULL, payload TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS events_task_time ON events(task_id, created_at);
    CREATE TABLE IF NOT EXISTS evidence (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, kind TEXT NOT NULL, created_at REAL NOT NULL, payload TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS evidence_task_time ON evidence(task_id, created_at);
    CREATE TABLE IF NOT EXISTS app_graph (id TEXT PRIMARY KEY, task_id TEXT, kind TEXT NOT NULL, created_at REAL NOT NULL, payload TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS app_store_connections (id TEXT PRIMARY KEY, task_id TEXT, kind TEXT NOT NULL, created_at REAL NOT NULL, payload TEXT NOT NULL);
    PRAGMA user_version=2;
    """

  private func write<T: Encodable>(
    table: String, id: String, taskID: String?, kind: String?, date: Date, payload: T
  ) throws {
    let data = try encoder.encode(payload)
    let json = String(decoding: data, as: UTF8.self)
    let columns: String
    let placeholders: String
    if table == "repositories" {
      columns = "id, created_at, payload"
      placeholders = "?, ?, ?"
    } else {
      columns = "id, task_id, kind, created_at, payload"
      placeholders = "?, ?, ?, ?, ?"
    }
    let statement = try prepare(
      "INSERT OR REPLACE INTO \(table) (\(columns)) VALUES (\(placeholders))")
    defer { sqlite3_finalize(statement) }
    try bind(id, at: 1, statement: statement)
    if table == "repositories" {
      sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
      try bind(json, at: 3, statement: statement)
    } else {
      try bindOptional(taskID, at: 2, statement: statement)
      try bindOptional(kind, at: 3, statement: statement)
      sqlite3_bind_double(statement, 4, date.timeIntervalSince1970)
      try bind(json, at: 5, statement: statement)
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw SQLiteStoreError.execute(errorMessage)
    }
  }

  private func execute(_ sql: String) throws {
    try Self.execute(on: database, sql: sql)
  }
  private nonisolated static func execute(on database: OpaquePointer?, sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
      let message =
        error.map { String(cString: $0) } ?? database.map { String(cString: sqlite3_errmsg($0)) }
        ?? "database unavailable"
      sqlite3_free(error)
      throw SQLiteStoreError.execute(message)
    }
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw SQLiteStoreError.prepare(errorMessage)
    }
    return statement
  }
  private func bind(_ value: String, at index: Int32, statement: OpaquePointer) throws {
    guard
      sqlite3_bind_text(
        statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        == SQLITE_OK
    else { throw SQLiteStoreError.bind(errorMessage) }
  }
  private func bindOptional(_ value: String?, at index: Int32, statement: OpaquePointer) throws {
    if let value {
      try bind(value, at: index, statement: statement)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }
  private var errorMessage: String {
    database.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable"
  }
}
