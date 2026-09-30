import Foundation
import SQLite3
import XCTest
@testable import UnsaidCore

final class CleanupTests: XCTestCase {
    func testCountsOnlyHabitsWisprRemoved() {
        let m = Cleanup.mark(raw: "So like I like it, kind of a lot, so yeah.", cleaned: "I like it a lot.")
        XCTAssertEqual(m.counts, ["like": 1, "kind of": 1, "yeah": 1])
        // The kept "like" isn't highlighted; the removed one is.
        XCTAssertEqual(m.habitTokens.map { m.tokens[$0].norm }.sorted(), ["kind", "like", "of", "so", "yeah"])
    }

    func testLongRewritesDontCount() {
        let m = Cleanup.mark(raw: "we should like maybe kind of think about it like later on tonight ok",
                             cleaned: "Let's revisit this.")
        XCTAssertEqual(m.counts, [:])
    }

    func testNothingRemoved() {
        XCTAssertEqual(Cleanup.mark(raw: "I think it works", cleaned: "I think it works.").counts, [:])
    }
}

final class SpeechTests: XCTestCase {
    func testContextRules() {
        let m = Speech.mark("Um, it's kind of going, like, fine. What kind of test? I like it. It looks like, rain. You know, sure. I mean, it works. You know what I mean.")
        XCTAssertEqual(m.counts, ["um": 1, "kind of": 1, "like": 1, "you know": 1, "i mean": 1])
    }
}

final class CoachTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int, hour: Int = 12) -> Date { Date(timeIntervalSince1970: Double(n) * 86400 + Double(hour) * 3600) }
    func sample(_ n: Int, _ source: Source = .dictation, words: Int, like: Int) -> Sample {
        Sample(source: source, id: UUID().uuidString, date: day(n), words: words, counts: like > 0 ? ["like": like] : [:], final: true)
    }

    func testRevealNeedsEnoughWords() {
        XCTAssertNil(Coach.reveal([sample(0, words: 500, like: 9)], now: day(0), calendar: cal))
        let r = Coach.reveal([sample(0, words: 800, like: 9), sample(3, .call, words: 400, like: 3)], now: day(3), calendar: cal)
        XCTAssertEqual(r?.days, 4)
        XCTAssertEqual(r?.top.first, Coach.HabitTotal(habit: Habits.named("like")!, dictation: 9, calls: 3))
    }

    func testGoalAllowanceScalesWithWords() {
        // 12 per 1,000 words before; target 6 per 1,000.
        let history = [sample(0, words: 1000, like: 12), sample(1, words: 1000, like: 12)]
        let goal = Coach.startGoal(habit: "like", samples: history, now: day(1, hour: 20), calendar: cal)
        XCTAssertEqual(goal.baselinePer1k, 12, accuracy: 0.001)
        XCTAssertEqual(goal.wordsPerDay, 1000, accuracy: 0.001)
        let t = Coach.today(goal, history + [sample(2, words: 500, like: 4)], now: day(2), calendar: cal)
        XCTAssertEqual(t, Coach.Today(count: 4, allowance: 3, day: 2, dictation: 4, calls: 0))
        XCTAssertTrue(t.over)
        XCTAssertNil(Coach.today(goal, history, now: day(3), calendar: cal).allowance)
    }

    func testResultsUseSecondWeek() {
        let history = [sample(0, words: 1000, like: 12)]
        let goal = Coach.startGoal(habit: "like", samples: history, now: day(0, hour: 20), calendar: cal)
        let during = history + [sample(3, words: 1000, like: 10), sample(9, words: 1000, like: 5), sample(10, .call, words: 500, like: 3)]
        XCTAssertFalse(Coach.isFinished(goal, now: day(13), calendar: cal))
        XCTAssertTrue(Coach.isFinished(goal, now: day(14), calendar: cal))
        let r = Coach.results(goal, during, calendar: cal)
        XCTAssertEqual(r.overall.before, 12, accuracy: 0.01)
        XCTAssertEqual(r.overall.after, 8 * 1000 / 1500, accuracy: 0.01)
        XCTAssertTrue(r.hit)
        XCTAssertNil(r.calls) // no calls before the goal to compare with
    }
}

final class WisprSyncTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("wispr/meetings"), withIntermediateDirectories: true)
        let db = try SQLite(path: dir.appendingPathComponent("wispr/flow.sqlite").path, readOnly: false)
        try db.execute("""
            CREATE TABLE History (transcriptEntityId TEXT, timestamp DATETIME, asrText TEXT, formattedText TEXT, status TEXT,
                speechDuration FLOAT, app TEXT, audio BLOB, screenshot BLOB);
            CREATE TABLE Meetings (id TEXT, endedAt INTEGER, isDeleted INTEGER);
            INSERT INTO History VALUES ('d1', '2026-09-20 10:00:00.000 +00:00', 'so like we ship it', 'We ship it.', 'formatted', 3, 'Slack', x'00', x'FF');
            INSERT INTO History VALUES ('d2', '2026-09-20 11:00:00.000 +00:00', '', '', 'raw_transcript', 0, NULL, NULL, NULL);
            INSERT INTO Meetings VALUES ('call', 1790000000000, 0);
            INSERT INTO Meetings VALUES ('room', 1790000000000, 0);
            """)
        func meeting(_ id: String, _ lines: [(String, String)]) throws {
            let folder = dir.appendingPathComponent("wispr/meetings/\(id)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var out = #"{"meta":{"v":3}}"# + "\n"
            for (i, (source, text)) in lines.enumerated() {
                out += #"{"text":"\#(text)","speaker":{"source":"\#(source)"},"startEpochMs":\#(1790000000000 + i * 1000),"startRecordingMs":\#(i * 1000),"endRecordingMs":\#(i * 1000 + 900)}"# + "\n"
            }
            try out.write(to: folder.appendingPathComponent("live.ndjson"), atomically: true, encoding: .utf8)
        }
        try meeting("call", [("system", "How's it going?"), ("mic", "Um, it's kind of going, like, fine."), ("system", "Nice.")])
        try meeting("room", [("mic", "Um, so, um, welcome everyone.")])
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testScansDictationsAndCallsButNotInPerson() throws {
        let store = try Store(folder: dir.appendingPathComponent("store"))
        let sync = WisprSync(wispr: try Wispr(folder: dir.appendingPathComponent("wispr")), store: store)
        XCTAssertEqual(try sync.scanDictations(), 1)
        XCTAssertEqual(store.value("dictationWatermark", as: String.self), "2026-09-20 10:00:00.000 +00:00")
        let plans = try sync.scanMeetings()
        XCTAssertTrue(plans.isEmpty) // no upload.ogg in the fixture yet

        let samples = try store.samples()
        XCTAssertEqual(samples.map(\.id).sorted(), ["call", "d1"])
        XCTAssertEqual(samples.first { $0.id == "call" }?.counts, ["um": 1, "kind of": 1, "like": 1])
        XCTAssertEqual(samples.first { $0.id == "call" }?.words, 7)
        XCTAssertEqual(try store.meetingState("room"), .inPerson)
        XCTAssertEqual(try store.meetingState("call"), .needsClips)

        let goal = try sync.startGoal("like", now: Date())
        XCTAssertEqual(goal.baselinePer1k, 2 * 1000.0 / 12, accuracy: 0.01) // 1 + 1 "like" in 5 + 7 words
        let clip = try XCTUnwrap(goal.day1Clip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.clipsFolder.appendingPathComponent(clip).path))
        XCTAssertEqual(store.value("goal", as: Goal.self)?.day1Clip, clip)
    }

    func testReportsAChangedDatabase() throws {
        let db = try SQLite(path: dir.appendingPathComponent("wispr/flow.sqlite").path, readOnly: false)
        try db.execute("ALTER TABLE History RENAME COLUMN asrText TO rawText")
        XCTAssertThrowsError(try Wispr(folder: dir.appendingPathComponent("wispr"))) {
            XCTAssertEqual($0 as? Wispr.Problem, .changed(missing: ["History.asrText"]))
        }
    }

    func testPicksTheMessiestWindow() {
        let seg = { (s: Segment.Source, t: String, ms: Double) in
            Segment(source: s, text: t, start: Date(), recordingStartMs: ms, recordingEndMs: ms + 2000)
        }
        let picks = WisprSync.picks([
            seg(.mic, "Um, like, yeah.", 0), seg(.mic, "It's kind of, um, done.", 2000),
            seg(.system, "OK.", 5000),
            seg(.mic, "We ship the tenant model today and the docs follow tomorrow morning.", 8000),
            seg(.mic, "Then we review it together.", 10000),
            seg(.mic, "After that it goes to staging.", 12000),
        ])
        XCTAssertEqual(picks.count, 2)
        XCTAssertEqual(picks[0].startMs, 0)
        XCTAssertEqual(picks[0].total, 4) // um, like, kind of, um
        XCTAssertEqual(picks[1].total, 0) // the clean turn
        XCTAssertEqual(picks[1].endMs - picks[1].startMs, 6000)
    }
}
