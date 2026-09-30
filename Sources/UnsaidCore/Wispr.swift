import Foundation

/// A finished Wispr Flow dictation.
public struct Dictation: Sendable {
    public let id: String
    public let date: Date
    /// Speech-to-text before Wispr's cleanup.
    public let raw: String
    /// What Wispr pasted.
    public let cleaned: String
    public let speechSeconds: Double
    public let app: String?
}

/// Reads Wispr Flow's local files. Never writes: the database is opened read-only in place (in WAL
/// mode a reader doesn't block Wispr's writes), and only the columns below are ever selected.
public final class Wispr {
    public static var defaultFolder: URL {
        if let dir = ProcessInfo.processInfo.environment["UNSAID_WISPR_DIR"] { return URL(fileURLWithPath: dir) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wispr Flow")
    }

    public enum Problem: Error, Equatable {
        /// No Wispr Flow data on this Mac.
        case notInstalled
        /// Wispr changed its database; this version of Unsaid can't read it safely.
        case changed(missing: [String])
    }

    static let historyColumns = ["transcriptEntityId", "timestamp", "asrText", "formattedText", "status",
                                 "speechDuration", "app", "audio"]
    static let meetingColumns = ["id", "endedAt", "isDeleted"]

    public let folder: URL
    private let db: SQLite

    public init(folder: URL = Wispr.defaultFolder) throws {
        self.folder = folder
        let path = folder.appendingPathComponent("flow.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else { throw Problem.notInstalled }
        db = try SQLite(path: path, readOnly: true)
        var missing: [String] = []
        for (table, needed) in [("History", Self.historyColumns), ("Meetings", Self.meetingColumns)] {
            let have = Set(try db.query("PRAGMA table_info(\(table))").compactMap { $0.string("name") })
            missing += needed.filter { !have.contains($0) }.map { "\(table).\($0)" }
        }
        if !missing.isEmpty { throw Problem.changed(missing: missing) }
    }

    /// Finished dictations at or after `since` (Wispr's timestamps sort as text), oldest first.
    public func dictations(since: String = "") throws -> [(dictation: Dictation, timestamp: String)] {
        try db.query("""
            SELECT transcriptEntityId, timestamp, asrText, formattedText, speechDuration, app FROM History
            WHERE status = 'formatted' AND asrText != '' AND timestamp >= ? ORDER BY timestamp
            """, [since]).compactMap { row in
            guard let id = row.string("transcriptEntityId"), let ts = row.string("timestamp"),
                  let date = Self.parse(ts), let raw = row.string("asrText") else { return nil }
            let d = Dictation(id: id, date: date, raw: raw, cleaned: row.string("formattedText") ?? "",
                              speechSeconds: row.double("speechDuration") ?? 0, app: row.string("app"))
            return (d, ts)
        }
    }

    public func dictation(id: String) throws -> Dictation? {
        try db.query("""
            SELECT transcriptEntityId, timestamp, asrText, formattedText, speechDuration, app FROM History
            WHERE transcriptEntityId = ?
            """, [id]).first.flatMap { row in
            guard let ts = row.string("timestamp"), let date = Self.parse(ts) else { return nil }
            return Dictation(id: id, date: date, raw: row.string("asrText") ?? "", cleaned: row.string("formattedText") ?? "",
                             speechSeconds: row.double("speechDuration") ?? 0, app: row.string("app"))
        }
    }

    /// The dictation's recording (a 16 kHz WAV), read only when it's played.
    public func audio(id: String) throws -> Data? {
        try db.query("SELECT audio FROM History WHERE transcriptEntityId = ?", [id]).first?.data("audio")
    }

    /// Which meetings have ended, by id. A meeting missing here, or with no end, is still going.
    public func endedMeetings() throws -> Set<String> {
        Set(try db.query("SELECT id FROM Meetings WHERE endedAt IS NOT NULL OR isDeleted = 1").compactMap { $0.string("id") })
    }

    public var meetingsFolder: URL { folder.appendingPathComponent("meetings") }

    static func parse(_ ts: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss.SSS xxx", "yyyy-MM-dd HH:mm:ss xxx"] {
            f.dateFormat = format
            if let d = f.date(from: ts) { return d }
        }
        return nil
    }
}

/// One line of a Notetaker transcript.
public struct Segment: Sendable {
    public enum Source: String, Sendable { case mic, system }
    public let source: Source
    public let text: String
    public let start: Date
    /// Position in the meeting's recording, for cutting clips.
    public let recordingStartMs: Double
    public let recordingEndMs: Double
}

/// A Notetaker meeting's live transcript (`meetings/<id>/live.ndjson`), written during the call.
public enum MeetingTranscript {
    public static func segments(in folder: URL) throws -> [Segment] {
        let text = try String(contentsOf: folder.appendingPathComponent("live.ndjson"), encoding: .utf8)
        return text.split(separator: "\n").compactMap { line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let speaker = o["speaker"] as? [String: Any],
                  let source = (speaker["source"] as? String).flatMap(Segment.Source.init),
                  let body = o["text"] as? String,
                  let startEpoch = o["startEpochMs"] as? Double,
                  let s = o["startRecordingMs"] as? Double, let e = o["endRecordingMs"] as? Double else { return nil }
            // Only your own words are kept; the other side's text is dropped here.
            return Segment(source: source, text: source == .mic ? body : "",
                           start: Date(timeIntervalSince1970: startEpoch / 1000), recordingStartMs: s, recordingEndMs: e)
        }
    }
}
