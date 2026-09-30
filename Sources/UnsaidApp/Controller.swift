import AppKit
import CoreServices
import os
import UnsaidCore

private let log = Logger(subsystem: "dev.unsaid", category: "coach")

/// What the menu bar and windows show, computed off the main thread after each scan.
struct Snapshot {
    enum Status {
        case starting
        case problem(Wispr.Problem)
        /// Not enough history yet.
        case collecting(words: Int)
        /// Enough history, no goal chosen yet.
        case ready(Coach.Reveal)
        case goal(Goal, Coach.Today)
        case finished(Goal, Coach.Results)
    }
    var status: Status = .starting
    var samples: [Sample] = []
}

extension Snapshot.Status {
    /// For the log: numbers only.
    var summary: String {
        switch self {
        case .starting: return "starting"
        case .problem(let p): return "problem \(p)"
        case .collecting(let words): return "collecting \(words) words"
        case .ready(let r): return "ready: \(r.top.map { "\($0.habit.id) \($0.total)" }.joined(separator: ", ")) in \(r.days) days"
        case .goal(let g, let t): return "goal \(g.habit) \(t.count)/\(t.allowance.map(String.init) ?? "-") day \(t.day)"
        case .finished(let g, let r): return "finished \(g.habit) \(r.overall.before) -> \(r.overall.after) hit \(r.hit)"
        }
    }
}

/// Keeps Unsaid's store in step with Wispr and decides what to show. All Wispr and store access
/// happens on `queue`; the UI reads `snapshot` on the main thread.
final class Controller {
    private let queue = DispatchQueue(label: "dev.unsaid.scan")
    private var wispr: Wispr?
    private var store: Store?
    private var sync: WisprSync?
    private var stream: FSEventStreamRef?
    private var pending = false
    let player = Player()

    private(set) var snapshot = Snapshot()
    var onChange: (() -> Void)?

    func start() {
        queue.async { [self] in
            do {
                let wispr = try Wispr()
                let store = try Store()
                self.wispr = wispr; self.store = store
                self.sync = WisprSync(wispr: wispr, store: store)
                DispatchQueue.main.async { self.watch(wispr.folder) }
            } catch let problem as Wispr.Problem {
                log.error("wispr: \(String(describing: problem))")
                publish(Snapshot(status: .problem(problem)))
                return
            } catch {
                log.error("start failed: \(error.localizedDescription)")
                publish(Snapshot(status: .problem(.notInstalled)))
                return
            }
            refresh()
        }
        // Day changes (a new day's count, day 14) happen without any file changing.
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.scheduleRefresh() }
    }

    /// Wakes on Wispr's database (a new dictation) and meeting files (a call in progress).
    private func watch(_ folder: URL) {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var ctx = FSEventStreamContext(version: 0, info: context, retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            let me = Unmanaged<Controller>.fromOpaque(info!).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as! [String]
            if list.prefix(count).contains(where: { $0.contains("flow.sqlite") || $0.hasSuffix("live.ndjson") || $0.hasSuffix("upload.ogg") }) {
                me.scheduleRefresh()
            }
        }
        stream = FSEventStreamCreate(nil, callback, &ctx, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     2.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { log.error("can't watch \(folder.path)"); return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        log.info("watching \(folder.path)")
    }

    func scheduleRefresh() {
        queue.async { [self] in
            guard !pending else { return }
            pending = true
            queue.asyncAfter(deadline: .now() + 1) { self.pending = false; self.refresh() }
        }
    }

    /// Scans Wispr, cuts any new call clips, and publishes a new snapshot. Runs on `queue`.
    private func refresh() {
        guard let sync, let store else { return }
        do {
            let n = try sync.scanDictations()
            let plans = try sync.scanMeetings()
            if n > 0 || !plans.isEmpty { log.info("scanned \(n) dictations, \(plans.count) calls to clip") }
            publish(try compute(store))
            // Clips come after the counts are shown: decoding a call's audio can take seconds.
            for plan in plans { cutClips(plan, store) }
        } catch let problem as Wispr.Problem {
            publish(Snapshot(status: .problem(problem)))
        } catch {
            log.error("refresh failed: \(error.localizedDescription)")
        }
    }

    private func cutClips(_ plan: WisprSync.ClipPlan, _ store: Store) {
        for (i, pick) in plan.picks.enumerated() {
            let file = "call-\(plan.meetingID.prefix(8))-\(i).m4a"
            do {
                try ClipCutter.cut(plan.audio, fromMs: pick.startMs, toMs: pick.endMs, into: store.clipsFolder.appendingPathComponent(file))
                try store.add(Clip(file: file, source: .call, date: pick.date, counts: pick.counts))
            } catch {
                log.error("clip \(file) failed: \(error.localizedDescription)")
            }
        }
        try? store.setMeetingState(plan.meetingID, .done)
        log.info("clipped call \(plan.meetingID, privacy: .public): \(plan.picks.count) clips")
    }

    private func compute(_ store: Store, now: Date = Date()) throws -> Snapshot {
        let samples = try store.samples()
        var snap = Snapshot(samples: samples)
        if let goal: Goal = store.value("goal") {
            snap.status = Coach.isFinished(goal, now: now)
                ? .finished(goal, Coach.results(goal, samples))
                : .goal(goal, Coach.today(goal, samples, now: now))
        } else if let reveal = Coach.reveal(samples, now: now) {
            snap.status = .ready(reveal)
        } else {
            snap.status = .collecting(words: Coach.words(samples))
        }
        return snap
    }

    private func publish(_ snap: Snapshot) {
        log.info("status: \(snap.status.summary, privacy: .public)")
        DispatchQueue.main.async { self.snapshot = snap; self.onChange?() }
    }

    // MARK: Actions (called from the UI; the work runs on `queue`)

    /// The dictation to show on the reveal: raw text marked, cleaned text, and its audio.
    struct Example {
        let dictation: Dictation
        let marked: Marked
        let audio: Data
    }

    func messiestExample(completion: @escaping (Example?) -> Void) {
        let samples = snapshot.samples
        queue.async { [self] in
            var found: Example?
            for s in Coach.messiest(samples).prefix(20) {
                guard let d = try? wispr?.dictation(id: s.id), let audio = try? wispr?.audio(id: s.id), !audio.isEmpty else { continue }
                found = Example(dictation: d, marked: Cleanup.mark(raw: d.raw, cleaned: d.cleaned), audio: audio)
                break
            }
            DispatchQueue.main.async { completion(found) }
        }
    }

    func startGoal(_ habit: String) {
        queue.async { [self] in
            guard let store else { return }
            do {
                let goal = try sync?.startGoal(habit, now: Date())
                log.info("goal: halve \(habit, privacy: .public) from \(goal?.baselinePer1k ?? 0, format: .fixed(precision: 1))/1k words, day-1 clip \(goal?.day1Clip != nil)")
                publish(try compute(store))
            } catch {
                log.error("start goal failed: \(error.localizedDescription)")
            }
        }
    }

    func play(_ items: [Playable]) { player.play(items) }

    /// The recording with the most of the habit since `since` (default: today), from a dictation
    /// or a call clip.
    func worst(_ habit: String, since: Date = Calendar.current.startOfDay(for: Date()), completion: @escaping (Playable?) -> Void) {
        let samples = snapshot.samples
        queue.async { [self] in
            let dictation = samples.filter { $0.source == .dictation && $0.date >= since }
                .max { ($0.counts[habit] ?? 0) < ($1.counts[habit] ?? 0) }
            let clip = (try? store?.clips())??.filter { $0.source == .call && $0.date >= since }
                .max { ($0.counts[habit] ?? 0) < ($1.counts[habit] ?? 0) }
            let d = dictation?.counts[habit] ?? 0, c = clip?.counts[habit] ?? 0
            var result: Playable?
            if let clip, let store, c > d, c > 0 {
                result = .file(store.url(of: clip))
            } else if let dictation, d > 0, let audio = try? wispr?.audio(id: dictation.id), !audio.isEmpty {
                result = .data(audio)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func day1(_ goal: Goal) -> Playable? {
        guard let file = goal.day1Clip, let store else { return nil }
        return .file(store.clipsFolder.appendingPathComponent(file))
    }

    /// Marks the day-14 results as seen, so the window opens once.
    func resultsShown(_ goal: Goal) -> Bool {
        queue.sync {
            let shown: Date? = store?.value("resultsShownFor")
            if shown == goal.start { return true }
            try? store?.set("resultsShownFor", goal.start)
            return false
        }
    }

    func flag(_ key: String) -> Bool { queue.sync { store?.value(key, as: Bool.self) ?? false } }
    func setFlag(_ key: String) { queue.async { try? self.store?.set(key, true) } }
}
