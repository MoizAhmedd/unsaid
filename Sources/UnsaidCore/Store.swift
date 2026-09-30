import Foundation

public enum Source: String, Codable, Sendable { case dictation, call }

/// Habit counts for one dictation or one call. No transcript text is ever stored.
public struct Sample: Codable, Equatable, Sendable {
    public let source: Source
    public let id: String
    public let date: Date
    /// Your words (for a call, only what your mic heard).
    public let words: Int
    public let counts: [String: Int]
    public let final: Bool

    public init(source: Source, id: String, date: Date, words: Int, counts: [String: Int], final: Bool) {
        self.source = source; self.id = id; self.date = date; self.words = words; self.counts = counts; self.final = final
    }
}

/// A short recording of you, kept because Wispr may delete the original.
public struct Clip: Codable, Equatable, Sendable {
    public let file: String
    public let source: Source
    public let date: Date
    public let counts: [String: Int]

    public init(file: String, source: Source, date: Date, counts: [String: Int]) {
        self.file = file; self.source = source; self.date = date; self.counts = counts
    }
}

/// Unsaid's own data: `coach.sqlite` plus a `clips` folder, a few hundred KB in total.
public final class Store {
    public static var defaultFolder: URL {
        if let dir = ProcessInfo.processInfo.environment["UNSAID_DATA_DIR"] { return URL(fileURLWithPath: dir) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Unsaid")
    }

    public let folder: URL
    public var clipsFolder: URL { folder.appendingPathComponent("clips") }
    private let db: SQLite

    public init(folder: URL = Store.defaultFolder) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("clips"), withIntermediateDirectories: true)
        db = try SQLite(path: folder.appendingPathComponent("coach.sqlite").path, readOnly: false)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS samples (source TEXT, id TEXT, ts REAL, words INTEGER, counts TEXT, final INTEGER,
                PRIMARY KEY (source, id));
            CREATE TABLE IF NOT EXISTS meetings (id TEXT PRIMARY KEY, state TEXT, ts REAL);
            CREATE TABLE IF NOT EXISTS clips (file TEXT PRIMARY KEY, source TEXT, ts REAL, counts TEXT);
            CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT);
            """)
    }

    // MARK: Samples

    public func upsert(_ s: Sample) throws {
        try db.query("INSERT OR REPLACE INTO samples VALUES (?, ?, ?, ?, ?, ?)",
                     [s.source.rawValue, s.id, s.date.timeIntervalSince1970, s.words, Self.json(s.counts), s.final ? 1 : 0])
    }

    public func samples() throws -> [Sample] {
        try db.query("SELECT * FROM samples ORDER BY ts").compactMap { r in
            guard let source = r.string("source").flatMap(Source.init), let id = r.string("id"), let ts = r.double("ts") else { return nil }
            return Sample(source: source, id: id, date: Date(timeIntervalSince1970: ts), words: r.int("words") ?? 0,
                          counts: Self.counts(r.string("counts")), final: r.int("final") == 1)
        }
    }

    // MARK: Meetings

    public enum MeetingState: String { case inPerson, needsClips, done }

    public func meetingState(_ id: String) throws -> MeetingState? {
        try db.query("SELECT state FROM meetings WHERE id = ?", [id]).first?.string("state").flatMap(MeetingState.init)
    }

    public func setMeetingState(_ id: String, _ state: MeetingState, at date: Date = Date()) throws {
        try db.query("INSERT OR REPLACE INTO meetings VALUES (?, ?, ?)", [id, state.rawValue, date.timeIntervalSince1970])
    }

    /// When a meeting first needed clips, to give up on its audio eventually.
    public func meetingStateDate(_ id: String) throws -> Date? {
        try db.query("SELECT ts FROM meetings WHERE id = ?", [id]).first?.double("ts").map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: Clips

    public func add(_ c: Clip) throws {
        try db.query("INSERT OR REPLACE INTO clips VALUES (?, ?, ?, ?)",
                     [c.file, c.source.rawValue, c.date.timeIntervalSince1970, Self.json(c.counts)])
    }

    public func clips() throws -> [Clip] {
        try db.query("SELECT * FROM clips ORDER BY ts").compactMap { r in
            guard let file = r.string("file"), let source = r.string("source").flatMap(Source.init),
                  let ts = r.double("ts") else { return nil }
            return Clip(file: file, source: source, date: Date(timeIntervalSince1970: ts), counts: Self.counts(r.string("counts")))
        }
    }

    public func url(of clip: Clip) -> URL { clipsFolder.appendingPathComponent(clip.file) }

    // MARK: Settings

    public func value<T: Decodable>(_ key: String, as: T.Type = T.self) -> T? {
        guard let s = try? db.query("SELECT value FROM kv WHERE key = ?", [key]).first?.string("value") else { return nil }
        return try? Self.decoder.decode(T.self, from: Data(s.utf8))
    }

    public func set<T: Encodable>(_ key: String, _ value: T?) throws {
        guard let value else { try db.query("DELETE FROM kv WHERE key = ?", [key]); return }
        let s = String(decoding: try Self.encoder.encode(value), as: UTF8.self)
        try db.query("INSERT OR REPLACE INTO kv VALUES (?, ?)", [key, s])
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }()
    private static func json(_ counts: [String: Int]) -> String { String(decoding: (try? encoder.encode(counts)) ?? Data("{}".utf8), as: UTF8.self) }
    private static func counts(_ s: String?) -> [String: Int] { s.flatMap { try? decoder.decode([String: Int].self, from: Data($0.utf8)) } ?? [:] }
}
