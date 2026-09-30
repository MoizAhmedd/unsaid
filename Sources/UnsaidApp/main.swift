import AppKit
import os
import SwiftUI
import ServiceManagement
import UnsaidCore

private let log = Logger(subsystem: "dev.unsaid", category: "app")

// Build-time and checking helpers, run without starting the app:
//   Unsaid --write-iconset DIR           the app icon, for scripts/make-app.sh
//   Unsaid --scan                        scan Wispr into the store and print counts (no transcript text);
//                                        set UNSAID_DATA_DIR to keep it away from the real store
//   Unsaid --start-goal HABIT            start a goal in the store, as the reveal's button does
//   Unsaid --render-reveal OUT.png       the first-launch window with sample data
//   Unsaid --render-results OUT.png      the day-14 window with sample data
let args = CommandLine.arguments
if args.count >= 3, args[1] == "--write-iconset" {
    try Art.writeIconset(to: URL(fileURLWithPath: args[2]))
    exit(0)
}
if args.count >= 3, args[1] == "--start-goal" {
    try Checks.startGoal(args[2])
    exit(0)
}
if args.count >= 2, args[1] == "--scan" {
    try Checks.scan()
    exit(0)
}
if args.count >= 3, args[1].hasPrefix("--render-") {
    _ = NSApplication.shared
    let view = args[1] == "--render-results" ? AnyView(Samples.results) : AnyView(Samples.reveal)
    guard let png = Windows.png(view) else { exit(1) }
    try png.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = Controller()
    private var menu: StatusMenu?
    private var noticeShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenu(controller: controller)
        menu?.showReveal = { [weak self] in self?.presentReveal() }
        menu?.showResults = { [weak self] in self?.presentResults() }
        controller.onChange = { [weak self] in self?.update() }
        controller.start()

        if !UserDefaults.standard.bool(forKey: "didFirstRun") {
            UserDefaults.standard.set(true, forKey: "didFirstRun")
            try? SMAppService.mainApp.register()
        }
    }

    /// Opens a window only at the moments in the product flow: the reveal once, day-14 results once.
    private func update() {
        menu?.refresh()
        switch controller.snapshot.status {
        case .problem(let problem) where !noticeShown:
            noticeShown = true
            if problem == .notInstalled {
                Windows.show("notice", NoticeView(title: "Unsaid coaches you through Wispr Flow",
                    message: "Unsaid learns how you speak from what you say to Wispr Flow and the calls it records. Install Wispr Flow, talk to it for a few days, then open Unsaid again.",
                    link: ("Get Wispr Flow", URL(string: "https://wisprflow.ai")!)))
            } else {
                Windows.show("notice", NoticeView(title: "Wispr Flow changed",
                    message: "Wispr Flow updated how it stores history, so this version of Unsaid stopped reading it rather than show wrong numbers.",
                    link: ("Get the latest Unsaid", URL(string: "https://github.com/MoizAhmedd/unsaid/releases")!)))
            }
        case .collecting(let words) where !controller.flag("revealShown") && !controller.flag("collectingShown"):
            controller.setFlag("collectingShown")
            Windows.show("notice", NoticeView(title: "Still listening",
                message: "Unsaid has heard \(words.formatted()) of the \(Coach.minimumWords.formatted()) words it needs to learn how you speak. Keep using Wispr Flow; your check-up opens when it's ready.",
                link: nil))
        case .ready where !controller.flag("revealShown"):
            controller.setFlag("revealShown")
            Windows.close("notice")
            presentReveal()
        case .finished(let goal, _) where !controller.resultsShown(goal):
            presentResults()
        default:
            break
        }
    }

    private func presentReveal() {
        guard case .ready(let reveal) = controller.snapshot.status else { return }
        controller.messiestExample { [controller] example in
            let model = example.map { e in
                ExampleModel(marked: e.marked, cleaned: e.dictation.cleaned, caption: Self.caption(e.dictation),
                             play: { controller.play([.data(e.audio)]) })
            }
            Windows.show("reveal", RevealView(reveal: reveal, example: model) { habit in
                controller.startGoal(habit)
                Windows.close("reveal")
            })
            log.info("reveal shown: top \(reveal.top.first?.habit.id ?? "-", privacy: .public) \(reveal.top.first?.total ?? 0)")
        }
    }

    private func presentResults() {
        guard case .finished(let goal, let results) = controller.snapshot.status, let habit = Habits.named(goal.habit) else { return }
        let during = controller.snapshot.samples.filter { $0.date >= goal.start }
        let next = Habits.all.filter { $0.id != goal.habit }.max { Coach.count($0.id, during) < Coach.count($1.id, during) }
        let secondWeek = Calendar.current.date(byAdding: .day, value: 7, to: goal.start)!
        let day1 = controller.day1(goal)
        Windows.show("results", ResultsView(
            habit: habit, results: results, next: next.flatMap { Coach.count($0.id, during) > 0 ? $0 : nil },
            playDay1: day1.map { d in { [controller] in controller.play([d]) } },
            playToday: { [controller] in controller.worst(goal.habit, since: secondWeek) { $0.map { controller.play([$0]) } } },
            startNext: { [controller] id in controller.startGoal(id); Windows.close("results") }))
    }

    static func caption(_ d: Dictation) -> String {
        let date = d.date.formatted(.dateTime.month(.abbreviated).day())
        var parts = [date, "\(Int(d.speechSeconds.rounded())) s"]
        if let bundle = d.app, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            parts.append(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
        return parts.joined(separator: " · ")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
