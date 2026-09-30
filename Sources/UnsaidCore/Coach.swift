import Foundation

/// A two-week goal to halve one habit, measured per 1,000 of your words so busy days aren't failures.
public struct Goal: Codable, Equatable, Sendable {
    public static let days = 14

    public let habit: String
    public let start: Date
    /// Habit rate before the goal, per 1,000 words, across dictation and calls.
    public let baselinePer1k: Double
    /// Your usual words a day, to show rates as "a day".
    public let wordsPerDay: Double
    /// The clip played as "day 1".
    public var day1Clip: String?
    public var targetPer1k: Double { baselinePer1k / 2 }

    public init(habit: String, start: Date, baselinePer1k: Double, wordsPerDay: Double, day1Clip: String? = nil) {
        self.habit = habit; self.start = start; self.baselinePer1k = baselinePer1k; self.wordsPerDay = wordsPerDay; self.day1Clip = day1Clip
    }

    /// A rate per 1,000 words as a count on a usual day.
    public func perDay(_ per1k: Double) -> Double { per1k * wordsPerDay / 1000 }
}

public enum Coach {
    /// Below this many words there isn't enough history to find habits.
    public static let minimumWords = 1000

    public struct HabitTotal: Equatable, Sendable {
        public let habit: Habit
        public let dictation: Int
        public let calls: Int
        public var total: Int { dictation + calls }

        public init(habit: Habit, dictation: Int, calls: Int) { self.habit = habit; self.dictation = dictation; self.calls = calls }
    }

    /// The first-launch numbers.
    public struct Reveal: Equatable, Sendable {
        public let days: Int
        public let dictations: Int
        public let calls: Int
        /// Up to 3 habits, most frequent first.
        public let top: [HabitTotal]

        public init(days: Int, dictations: Int, calls: Int, top: [HabitTotal]) {
            self.days = days; self.dictations = dictations; self.calls = calls; self.top = top
        }
    }

    public static func words(_ samples: [Sample]) -> Int { samples.reduce(0) { $0 + $1.words } }

    public static func count(_ habit: String, _ samples: [Sample]) -> Int {
        samples.reduce(0) { $0 + ($1.counts[habit] ?? 0) }
    }

    /// Nil until there are `minimumWords` words and at least one habit.
    public static func reveal(_ samples: [Sample], now: Date, calendar: Calendar = .current) -> Reveal? {
        guard words(samples) >= minimumWords, let first = samples.map(\.date).min() else { return nil }
        let dictation = samples.filter { $0.source == .dictation }, calls = samples.filter { $0.source == .call }
        let top = Habits.all.map { HabitTotal(habit: $0, dictation: count($0.id, dictation), calls: count($0.id, calls)) }
            .filter { $0.total > 0 }.sorted { $0.total > $1.total }.prefix(3)
        guard !top.isEmpty else { return nil }
        return Reveal(days: dayNumber(of: now, since: first, calendar: calendar),
                      dictations: dictation.count, calls: calls.count, top: Array(top))
    }

    /// Dictations, most habits first, as candidates for "hear your messiest one".
    public static func messiest(_ samples: [Sample]) -> [Sample] {
        func score(_ s: Sample) -> Int { s.counts.values.reduce(0, +) }
        return samples.filter { $0.source == .dictation && score($0) > 0 }
            .sorted { score($0) != score($1) ? score($0) > score($1) : $0.date > $1.date }
    }

    public static func startGoal(habit: String, samples: [Sample], now: Date, calendar: Calendar = .current) -> Goal {
        let before = samples.filter { $0.date <= now }
        let days = before.map(\.date).min().map { dayNumber(of: now, since: $0, calendar: calendar) } ?? 1
        return Goal(habit: habit, start: now, baselinePer1k: rate(habit, before) ?? 0,
                    wordsPerDay: Double(words(before)) / Double(max(days, 1)))
    }

    public static func rate(_ habit: String, _ samples: [Sample]) -> Double? {
        let w = words(samples)
        return w > 0 ? Double(count(habit, samples)) * 1000 / Double(w) : nil
    }

    public struct Today: Equatable, Sendable {
        public let count: Int
        /// Today's goal, which grows with the words you've spoken today. Nil before you've said anything.
        public let allowance: Int?
        /// 1 to 14.
        public let day: Int
        public let dictation: Int
        public let calls: Int
        public var over: Bool { allowance.map { count > $0 } ?? false }
    }

    public static func today(_ goal: Goal, _ samples: [Sample], now: Date, calendar: Calendar = .current) -> Today {
        let todays = samples.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let w = words(todays)
        return Today(count: count(goal.habit, todays),
                     allowance: w > 0 ? max(1, Int((goal.targetPer1k * Double(w) / 1000).rounded())) : nil,
                     day: min(dayNumber(of: now, since: goal.start, calendar: calendar), Goal.days),
                     dictation: count(goal.habit, todays.filter { $0.source == .dictation }),
                     calls: count(goal.habit, todays.filter { $0.source == .call }))
    }

    public static func isFinished(_ goal: Goal, now: Date, calendar: Calendar = .current) -> Bool {
        dayNumber(of: now, since: goal.start, calendar: calendar) > Goal.days
    }

    public struct Change: Equatable, Sendable {
        /// Counts on a usual day.
        public let before: Double
        public let after: Double

        public init(before: Double, after: Double) { self.before = before; self.after = after }
    }

    public struct Results: Equatable, Sendable {
        public let overall: Change
        public let dictation: Change?
        public let calls: Change?
        public let hit: Bool

        public init(overall: Change, dictation: Change?, calls: Change?, hit: Bool) {
            self.overall = overall; self.dictation = dictation; self.calls = calls; self.hit = hit
        }
    }

    /// Before = everything until the goal started. After = its second week, or the whole goal
    /// if the second week was too quiet to judge.
    public static func results(_ goal: Goal, _ samples: [Sample], calendar: Calendar = .current) -> Results {
        let startDay = calendar.startOfDay(for: goal.start)
        let day = { (n: Int) in calendar.date(byAdding: .day, value: n, to: startDay)! }
        let before = samples.filter { $0.date < goal.start }
        var after = samples.filter { $0.date >= day(7) && $0.date < day(Goal.days) }
        if words(after) < 300 { after = samples.filter { $0.date >= goal.start && $0.date < day(Goal.days) } }

        func change(_ source: Source?) -> Change? {
            let b = source.map { s in before.filter { $0.source == s } } ?? before
            let a = source.map { s in after.filter { $0.source == s } } ?? after
            guard let rb = rate(goal.habit, b), let ra = rate(goal.habit, a) else { return nil }
            return Change(before: goal.perDay(rb), after: goal.perDay(ra))
        }
        let afterRate = rate(goal.habit, after) ?? goal.baselinePer1k
        return Results(overall: Change(before: goal.perDay(goal.baselinePer1k), after: goal.perDay(afterRate)),
                       dictation: change(.dictation), calls: change(.call),
                       hit: afterRate <= goal.targetPer1k * 1.05)
    }

    /// 1 on the day of `since`, 2 the next calendar day, and so on.
    public static func dayNumber(of date: Date, since: Date, calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: since), to: calendar.startOfDay(for: date)).day ?? 0) + 1
    }
}
