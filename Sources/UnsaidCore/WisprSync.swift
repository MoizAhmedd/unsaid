import Foundation

/// Brings Unsaid's store up to date with Wispr: each dictation is compared once, each call is
/// counted as its transcript grows and finalized when Wispr marks it ended.
public final class WisprSync {
    public let wispr: Wispr
    public let store: Store
    /// Rows this recent are re-read, in case Wispr finished formatting them after we last looked.
    static let rescanWindow: TimeInterval = 15 * 60
    /// Give up on a call's audio this long after it ended (Wispr may never write or may purge it).
    static let clipDeadline: TimeInterval = 2 * 24 * 3600
    /// A clip is at most this long.
    static let maxClipMs: Double = 20_000

    public init(wispr: Wispr, store: Store) {
        self.wispr = wispr
        self.store = store
    }

    /// Returns how many dictations were new or updated.
    @discardableResult
    public func scanDictations() throws -> Int {
        let watermark: String = store.value("dictationWatermark") ?? ""
        let since = Wispr.parse(watermark).map { Self.wisprTimestamp($0.addingTimeInterval(-Self.rescanWindow)) } ?? ""
        let rows = try wispr.dictations(since: since)
        for (d, _) in rows {
            let marked = Cleanup.mark(raw: d.raw, cleaned: d.cleaned)
            try store.upsert(Sample(source: .dictation, id: d.id, date: d.date, words: marked.words, counts: marked.counts, final: true))
        }
        if let last = rows.last?.timestamp, last > watermark { try store.set("dictationWatermark", last) }
        return rows.count
    }

    /// A stretch of your speech in a call worth keeping as audio.
    public struct ClipPick: Equatable, Sendable {
        public let startMs: Double
        public let endMs: Double
        public let date: Date
        public let counts: [String: Int]
        public var total: Int { counts.values.reduce(0, +) }
    }

    /// An ended call whose clips still need cutting from `meetings/<id>/upload.ogg`.
    public struct ClipPlan: Sendable {
        public let meetingID: String
        public let audio: URL
        public let picks: [ClipPick]
    }

    /// Counts every call that isn't finished, and returns the ended calls that still need clips.
    /// Recordings with no call audio (in person) are skipped: the mic heard everyone.
    public func scanMeetings(now: Date = Date()) throws -> [ClipPlan] {
        let fm = FileManager.default
        guard let ids = try? fm.contentsOfDirectory(atPath: wispr.meetingsFolder.path) else { return [] }
        let ended = try wispr.endedMeetings()
        var plans: [ClipPlan] = []
        for id in ids {
            let folder = wispr.meetingsFolder.appendingPathComponent(id)
            let state = try store.meetingState(id)
            if state == .inPerson || state == .done { continue }
            guard let segments = try? MeetingTranscript.segments(in: folder), !segments.isEmpty else { continue }
            let isEnded = ended.contains(id)
            guard segments.contains(where: { $0.source == .system }) else {
                if isEnded { try store.setMeetingState(id, .inPerson, at: now) }
                continue
            }
            let mine = segments.filter { $0.source == .mic }
            let marks = mine.map { Speech.mark($0.text) }
            var counts: [String: Int] = [:]
            for m in marks { counts.merge(m.counts, uniquingKeysWith: +) }
            try store.upsert(Sample(source: .call, id: id, date: segments[0].start,
                                    words: marks.reduce(0) { $0 + $1.words }, counts: counts, final: isEnded))
            guard isEnded else { continue }

            if state == nil { try store.setMeetingState(id, .needsClips, at: now) }
            let audio = folder.appendingPathComponent("upload.ogg")
            let since = try store.meetingStateDate(id) ?? now
            if fm.fileExists(atPath: audio.path) {
                plans.append(ClipPlan(meetingID: id, audio: audio, picks: Self.picks(segments)))
            } else if now.timeIntervalSince(since) > Self.clipDeadline {
                try store.setMeetingState(id, .done, at: now)
            }
        }
        return plans
    }

    /// Your 3 turns with the most habits, plus your longest clean turn, each at most 20 s.
    static func picks(_ segments: [Segment]) -> [ClipPick] {
        // A turn is consecutive mic segments with no one else speaking in between.
        var turns: [[Segment]] = []
        var current: [Segment] = []
        for s in segments {
            if s.source == .mic { current.append(s) } else if !current.isEmpty { turns.append(current); current = [] }
        }
        if !current.isEmpty { turns.append(current) }

        let windows = turns.map { bestWindow($0) }
        let messy = windows.filter { $0.total > 0 }.sorted { $0.total > $1.total }.prefix(3)
        let clean = windows.filter { $0.total == 0 && $0.endMs - $0.startMs >= 6_000 }
            .max { $0.endMs - $0.startMs < $1.endMs - $1.startMs }
        return Array(messy) + (clean.map { [$0] } ?? [])
    }

    /// The stretch of a turn, at most `maxClipMs` long, with the most habits.
    static func bestWindow(_ turn: [Segment]) -> ClipPick {
        let marks = turn.map { Speech.mark($0.text).counts }
        var best = (i: 0, j: 0, total: -1)
        for i in turn.indices {
            var total = 0
            for j in i..<turn.count {
                guard turn[j].recordingEndMs - turn[i].recordingStartMs <= maxClipMs || j == i else { break }
                total += marks[j].values.reduce(0, +)
                if total > best.total || (total == best.total && j - i > best.j - best.i) { best = (i, j, total) }
            }
        }
        var counts: [String: Int] = [:]
        for k in best.i...best.j { counts.merge(marks[k], uniquingKeysWith: +) }
        let end = min(turn[best.j].recordingEndMs, turn[best.i].recordingStartMs + maxClipMs)
        return ClipPick(startMs: turn[best.i].recordingStartMs, endMs: end, date: turn[best.i].start, counts: counts)
    }

    /// Starts a two-week goal and keeps today's "before" recording: your latest dictation with the
    /// habit, or else your latest call clip with it.
    @discardableResult
    public func startGoal(_ habit: String, now: Date) throws -> Goal {
        var goal = Coach.startGoal(habit: habit, samples: try store.samples(), now: now)
        for s in try store.samples().reversed() where s.source == .dictation && (s.counts[habit] ?? 0) > 0 {
            guard let audio = try wispr.audio(id: s.id), !audio.isEmpty else { continue }
            let file = "day1-\(Int(now.timeIntervalSince1970)).wav"
            try audio.write(to: store.clipsFolder.appendingPathComponent(file))
            try store.add(Clip(file: file, source: .dictation, date: s.date, counts: s.counts))
            goal.day1Clip = file
            break
        }
        if goal.day1Clip == nil { goal.day1Clip = try store.clips().last { ($0.counts[habit] ?? 0) > 0 }?.file }
        try store.set("goal", goal)
        try store.set("resultsShownFor", nil as Date?)
        return goal
    }

    static func wisprTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS xxx"
        return f.string(from: date)
    }
}
