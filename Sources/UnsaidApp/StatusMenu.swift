import AppKit
import ServiceManagement
import UnsaidCore

/// The menu bar: your goal habit's count for today against today's goal, and its menu.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: Controller
    private let menu = NSMenu()
    var showReveal: () -> Void = {}
    var showResults: () -> Void = {}

    init(controller: Controller) {
        self.controller = controller
        super.init()
        item.button?.image = Art.menuBarIcon
        item.button?.imagePosition = .imageLeading
        menu.delegate = self
        item.menu = menu
        refresh()
    }

    func refresh() {
        guard let button = item.button else { return }
        switch controller.snapshot.status {
        case .goal(let goal, let today):
            let text = " \(goal.habit) \(today.count)" + (today.allowance.map { "/\($0)" } ?? "")
            let color: NSColor = today.over ? .systemOrange : .labelColor
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .foregroundColor: color, .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)])
        case .problem:
            button.title = " !"
        default:
            button.title = ""
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let snap = controller.snapshot
        switch snap.status {
        case .starting:
            menu.addItem(disabled("Reading Wispr Flow…"))
        case .problem(.notInstalled):
            menu.addItem(disabled("Wispr Flow isn't on this Mac"))
            menu.addItem(action("Get Wispr Flow", #selector(openWispr)))
        case .problem(.changed):
            menu.addItem(disabled("Wispr Flow changed. Unsaid needs an update."))
            menu.addItem(action("Get the latest Unsaid", #selector(openGitHub)))
        case .collecting(let words):
            menu.addItem(disabled("Listening: \(words.formatted()) of \(Coach.minimumWords.formatted()) words"))
            menu.addItem(disabled("Keep using Wispr. Unsaid needs a little history."))
        case .ready:
            menu.addItem(action("Pick a habit to halve…", #selector(reveal)))
        case .goal(let goal, let today):
            let label = Habits.named(goal.habit)?.label ?? goal.habit
            menu.addItem(disabled("\(label) today: \(today.count)" + (today.allowance.map { " / goal \($0)" } ?? "")))
            menu.addItem(disabled("Messages \(today.dictation) · Calls \(today.calls) · Day \(today.day) of \(Goal.days)"))
            menu.addItem(.separator())
            if today.day >= 7 { menu.addItem(bold(action("Halfway: hear the difference", #selector(playDay1VsToday)))) }
            else { menu.addItem(action("▶ Hear day 1 vs today", #selector(playDay1VsToday))) }
            menu.addItem(action("▶ Hear today's worst", #selector(playTodaysWorst)))
            menu.addItem(switchMenu(current: goal.habit, snap))
        case .finished:
            menu.addItem(action("Your two weeks are up: see results", #selector(results)))
        }
        menu.addItem(.separator())
        let login = action("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(action("Unsaid on GitHub", #selector(openGitHub)))
        menu.addItem(NSMenuItem(title: "Quit Unsaid", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func switchMenu(current: String, _ snap: Snapshot) -> NSMenuItem {
        let item = NSMenuItem(title: "Switch habit (restarts the 2 weeks)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let totals = Habits.all.map { ($0, Coach.count($0.id, snap.samples)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        for (habit, n) in totals.prefix(6) {
            let m = action("\(habit.label)  (\(n))", #selector(switchHabit(_:)))
            m.representedObject = habit.id
            m.state = habit.id == current ? .on : .off
            sub.addItem(m)
        }
        item.submenu = sub
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        m.isEnabled = false
        return m
    }

    private func bold(_ m: NSMenuItem) -> NSMenuItem {
        m.attributedTitle = NSAttributedString(string: m.title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        return m
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        m.target = self
        return m
    }

    private var goal: Goal? {
        if case .goal(let g, _) = controller.snapshot.status { return g }
        return nil
    }

    @objc private func reveal() { showReveal() }
    @objc private func results() { showResults() }

    @objc private func playTodaysWorst() {
        guard let goal else { return }
        controller.worst(goal.habit) { [controller] worst in
            if let worst { controller.play([worst]) } else { NSSound.beep() }
        }
    }

    @objc private func playDay1VsToday() {
        guard let goal else { return }
        let day1 = controller.day1(goal)
        controller.worst(goal.habit) { [controller] worst in
            let items = [day1, worst].compactMap { $0 }
            if items.isEmpty { NSSound.beep() } else { controller.play(items) }
        }
    }

    @objc private func switchHabit(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        controller.startGoal(id)
    }

    @objc private func openWispr() { NSWorkspace.shared.open(URL(string: "https://wisprflow.ai")!) }
    @objc private func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/MoizAhmedd/unsaid")!) }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
    }
}
