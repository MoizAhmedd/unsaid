import Foundation
import SwiftUI
import UnsaidCore

/// `--scan`: runs a real scan and prints only numbers, to check Unsaid against a real Wispr install.
enum Checks {
    /// `--start-goal HABIT`: starts a goal in the store, as the reveal's button does.
    static func startGoal(_ habit: String) throws {
        let sync = WisprSync(wispr: try Wispr(), store: try Store())
        try sync.scanDictations()
        let goal = try sync.startGoal(habit, now: Date())
        print("goal: \(habit) from \(String(format: "%.1f", goal.baselinePer1k)) to \(String(format: "%.1f", goal.targetPer1k)) per 1,000 words, about \(Int(goal.perDay(goal.baselinePer1k).rounded())) a day; day-1 clip: \(goal.day1Clip ?? "none")")
    }

    static func scan() throws {
        let store = try Store()
        let sync = WisprSync(wispr: try Wispr(), store: store)
        let started = Date()
        let n = try sync.scanDictations()
        let plans = try sync.scanMeetings()
        for plan in plans {
            for (i, pick) in plan.picks.enumerated() {
                let file = "call-\(plan.meetingID.prefix(8))-\(i).m4a"
                try ClipCutter.cut(plan.audio, fromMs: pick.startMs, toMs: pick.endMs, into: store.clipsFolder.appendingPathComponent(file))
                try store.add(Clip(file: file, source: .call, date: pick.date, counts: pick.counts))
            }
            try store.setMeetingState(plan.meetingID, .done)
        }
        let samples = try store.samples()
        let dictations = samples.filter { $0.source == .dictation }, calls = samples.filter { $0.source == .call }
        print("store: \(store.folder.path)")
        print("scan: \(n) dictations read, \(plans.count) calls clipped, \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        print("dictations: \(dictations.count), \(Coach.words(dictations)) words")
        print("calls: \(calls.count), \(Coach.words(calls)) of your words, \(calls.filter { !$0.final }.count) in progress")
        print("clips: \(try store.clips().count)")
        for h in Habits.all {
            let d = Coach.count(h.id, dictations), c = Coach.count(h.id, calls)
            if d + c > 0 { print("  \(h.label): \(d + c)  (dictation \(d), calls \(c))") }
        }
        if let r = Coach.reveal(samples, now: Date()) {
            print("reveal: \(r.top[0].habit.label) \(r.top[0].total) times in \(r.days) days")
        } else {
            print("reveal: not enough history")
        }
    }
}

/// Sample data for the rendered windows (landing page, demo, checking layout).
enum Samples {
    static let reveal = RevealView(
        reveal: Coach.Reveal(days: 12, dictations: 287, calls: 9, top: [
            Coach.HabitTotal(habit: Habits.named("like")!, dictation: 146, calls: 61),
            Coach.HabitTotal(habit: Habits.named("kind of")!, dictation: 50, calls: 97),
            Coach.HabitTotal(habit: Habits.named("yeah")!, dictation: 35, calls: 12),
        ]),
        example: ExampleModel(
            marked: Cleanup.mark(raw: "So like the thing is we kind of need the org row first, and then like the client, so yeah.",
                                 cleaned: "The thing is we need the org row first, then the client."),
            cleaned: "The thing is we need the org row first, then the client.",
            caption: "Sep 24 · 41 s · Slack", play: {}),
        start: { _ in })

    static let results = ResultsView(
        habit: Habits.named("like")!,
        results: Coach.Results(overall: .init(before: 17, after: 7), dictation: .init(before: 12, after: 5),
                               calls: .init(before: 5, after: 2), hit: true),
        next: Habits.named("kind of"), playDay1: {}, playToday: {}, startNext: { _ in })
}
