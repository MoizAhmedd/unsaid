import AppKit
import SwiftUI
import UnsaidCore

enum Palette {
    static let accent = Color(red: 0.23, green: 0.36, blue: 0.86)
    static let warn = Color(red: 0.91, green: 0.35, blue: 0.05)
    static let bar = Color(red: 1.0, green: 0.85, blue: 0.66)
    static let highlight = Color(red: 1.0, green: 0.95, blue: 0.75)
    static let good = Color(red: 0.18, green: 0.62, blue: 0.27)
    static let card = Color(nsColor: .controlBackgroundColor)
}

/// The dictation shown on the reveal, already loaded.
struct ExampleModel {
    let marked: Marked
    let cleaned: String
    let caption: String
    let play: () -> Void
}

/// First launch: what Wispr has been hiding, your messiest dictation, and the goal button.
struct RevealView: View {
    let reveal: Coach.Reveal
    let example: ExampleModel?
    let start: (String) -> Void
    @State private var selected: String

    init(reveal: Coach.Reveal, example: ExampleModel?, start: @escaping (String) -> Void) {
        self.reveal = reveal
        self.example = example
        self.start = start
        _selected = State(initialValue: reveal.top.first?.habit.id ?? "like")
    }

    private var chosen: Coach.HabitTotal { reveal.top.first { $0.habit.id == selected } ?? reveal.top[0] }
    private var perDay: Int { max(1, Int((Double(chosen.total) / Double(max(reveal.days, 1))).rounded())) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("You said ") + Text("\(chosen.habit.label) \(chosen.total) times").foregroundColor(Palette.warn)
             + Text(" in \(reveal.days) days."))
                .font(.system(size: 40, weight: .bold)).tracking(-1).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 10).padding(.bottom, 24)

            let most = reveal.top.map(\.total).max() ?? 1
            VStack(spacing: 6) {
                ForEach(reveal.top, id: \.habit.id) { h in
                    Button { selected = h.habit.id } label: {
                        HStack(spacing: 12) {
                            Text(h.habit.label).frame(width: 170, alignment: .leading)
                            GeometryReader { g in
                                Capsule().fill(Palette.bar).frame(width: max(8, g.size.width * CGFloat(h.total) / CGFloat(most)), height: 10)
                                    .frame(maxHeight: .infinity)
                            }.frame(height: 20)
                            Text("\(h.total)").monospacedDigit().bold().frame(width: 50, alignment: .trailing)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(h.habit.id == selected ? Color.primary.opacity(0.07) : .clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .font(.system(size: 15)).padding(.horizontal, -8).padding(.bottom, 22)

            if let example { ExampleCard(example: example).padding(.bottom, 24) }

            HStack(spacing: 12) {
                Button { start(selected) } label: {
                    Text("Halve it in 2 weeks").bold().padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.accent)).foregroundStyle(.white)
                }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
                Text("From about \(perDay) a day to \(max(1, perDay / 2)). Tracked in your menu bar.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 36)
        .frame(width: 660)
    }

    private var subtitle: String {
        switch (reveal.dictations > 0, reveal.calls > 0) {
        case (true, true): return "From \(reveal.dictations) dictations and \(reveal.calls) calls. Wispr cleans them out, so you never see them."
        case (false, true): return "From \(reveal.calls) calls in Wispr's Notetaker."
        default: return "Wispr cleaned them out, so you never saw them."
        }
    }
}

struct ExampleCard: View {
    let example: ExampleModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: example.play) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(Palette.accent))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hear your messiest one").bold()
                        Text(example.caption).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            row("YOU SAID", Text(highlighted))
            row("WISPR WROTE", Text(example.cleaned).foregroundColor(.secondary))
        }
        .font(.system(size: 14)).padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }

    private func row(_ tag: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(tag).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 80, alignment: .leading)
            text.lineSpacing(3).lineLimit(5).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var highlighted: AttributedString {
        var out = AttributedString()
        for (i, t) in example.marked.tokens.enumerated() {
            if i > 0 { out += AttributedString(" ") }
            var piece = AttributedString(t.text)
            if example.marked.habitTokens.contains(i) { piece.backgroundColor = Palette.highlight; piece.foregroundColor = .black }
            out += piece
        }
        return out
    }
}

/// Day 14: before and after, and what's next.
struct ResultsView: View {
    let habit: Habit
    let results: Coach.Results
    let next: Habit?
    let playDay1: (() -> Void)?
    let playToday: () -> Void
    let startNext: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(results.hit ? "Two weeks. Halved." : "Two weeks in.").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            (Text("\(habit.label): ") + Text("\(fmt(results.overall.before)) → \(fmt(results.overall.after))")
                .foregroundColor(results.hit ? Palette.good : Palette.warn) + Text(" a day."))
                .font(.system(size: 40, weight: .bold)).tracking(-1).padding(.top, 6)
            Text(breakdown).font(.system(size: 15)).foregroundStyle(.secondary).padding(.top, 10).padding(.bottom, 24)

            HStack(spacing: 10) {
                if let playDay1 { playButton("Day 1", playDay1) }
                playButton("Today", playToday)
            }.padding(.bottom, 26)

            HStack(spacing: 10) {
                if results.hit, let next {
                    primary("Next: \(next.label)") { startNext(next.id) }
                    secondary("Keep going") { startNext(habit.id) }
                } else {
                    primary("Two more weeks") { startNext(habit.id) }
                    if let next { secondary("Switch to \(next.label)") { startNext(next.id) } }
                }
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 36).frame(width: 660, alignment: .leading)
    }

    private var breakdown: String {
        var parts: [String] = []
        if let d = results.dictation { parts.append("Dictation \(fmt(d.before)) → \(fmt(d.after))") }
        if let c = results.calls { parts.append("Calls \(fmt(c.before)) → \(fmt(c.after))") }
        return parts.isEmpty ? "On a usual day of talking." : parts.joined(separator: " · ") + ", on a usual day."
    }

    private func fmt(_ v: Double) -> String { v >= 10 ? "\(Int(v.rounded()))" : String(format: "%.1f", v).replacingOccurrences(of: ".0", with: "") }

    private func playButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Circle().fill(Palette.accent))
                Text(title).bold()
            }.padding(.trailing, 12).padding(4).background(Capsule().fill(Palette.card))
        }.buttonStyle(.plain)
    }

    private func primary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).bold().padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.accent)).foregroundStyle(.white)
        }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
    }

    private func secondary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
        }.buttonStyle(.plain)
    }
}

/// Shown once on first launch when there isn't enough history yet, or Wispr can't be read.
struct NoticeView: View {
    let title: String
    let message: String
    let link: (String, URL)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 26, weight: .bold))
            Text(message).font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let link { Link(link.0, destination: link.1).padding(.top, 6) }
        }
        .padding(32).frame(width: 460, alignment: .leading)
    }
}

/// Shows SwiftUI views in plain titled windows, and renders them to PNG for checking without a screen.
enum Windows {
    private static var open: [String: NSWindow] = [:]

    static func show<V: View>(_ id: String, _ view: V) {
        open[id]?.close()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        open[id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close(_ id: String) { open[id]?.close(); open[id] = nil }

    static func png<V: View>(_ view: V) -> Data? {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
