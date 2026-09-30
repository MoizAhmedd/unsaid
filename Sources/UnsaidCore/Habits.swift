import Foundation

/// A speaking habit Unsaid can track, such as "like" or "kind of".
public struct Habit: Hashable, Sendable, Identifiable {
    /// Stable key stored in counts and goals.
    public let id: String
    /// How the UI names it.
    public let label: String
    /// Normalized word sequences that count as this habit.
    public let phrases: [[String]]
}

public enum Habits {
    public static let all: [Habit] = [
        Habit(id: "like", label: "\"like\"", phrases: [["like"]]),
        Habit(id: "kind of", label: "\"kind of\"", phrases: [["kind", "of"], ["kinda"]]),
        Habit(id: "sort of", label: "\"sort of\"", phrases: [["sort", "of"], ["sorta"]]),
        Habit(id: "um", label: "um / uh", phrases: [["um"], ["umm"], ["uh"], ["uhh"], ["uhm"], ["erm"]]),
        Habit(id: "yeah", label: "\"so yeah\" endings", phrases: [["so", "yeah"], ["but", "yeah"], ["and", "yeah"]]),
        Habit(id: "you know", label: "\"you know\"", phrases: [["you", "know"]]),
        Habit(id: "i mean", label: "\"I mean\"", phrases: [["i", "mean"]]),
        Habit(id: "i think", label: "\"I think\"", phrases: [["i", "think"]]),
        Habit(id: "i guess", label: "\"I guess\"", phrases: [["i", "guess"]]),
        Habit(id: "basically", label: "\"basically\"", phrases: [["basically"]]),
        Habit(id: "actually", label: "\"actually\"", phrases: [["actually"]]),
        Habit(id: "literally", label: "\"literally\"", phrases: [["literally"]]),
    ]

    public static func named(_ id: String) -> Habit? { all.first { $0.id == id } }

    /// Every (habit, phrase) pair, longest phrase first, so "kind of" wins over a one-word match.
    static let phrases: [(habit: Habit, phrase: [String])] =
        all.flatMap { h in h.phrases.map { (h, $0) } }.sorted { $0.phrase.count > $1.phrase.count }
}

/// One word of a transcript: `text` as written (for display), `norm` for matching.
public struct Token: Equatable, Sendable {
    public let text: String
    public let norm: String
}

public enum Tokenizer {
    /// Splits on whitespace and on em/en dashes (kept on the left word, so "the— the" is two words).
    public static func tokens(_ s: String) -> [Token] {
        var out: [Token] = []
        for chunk in s.split(whereSeparator: \.isWhitespace) {
            var piece = ""
            for ch in chunk {
                piece.append(ch)
                if ch == "—" || ch == "–" { out.append(token(piece)); piece = "" }
            }
            if !piece.isEmpty { out.append(token(piece)) }
        }
        return out
    }

    static func token(_ text: String) -> Token {
        let norm = text.lowercased().replacingOccurrences(of: "’", with: "'")
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "'" }
        return Token(text: text, norm: String(String.UnicodeScalarView(norm)))
    }
}

/// A transcript with the positions of habit words marked, for counting and for highlighting.
public struct Marked: Sendable {
    public let tokens: [Token]
    /// Indices into `tokens` that belong to a counted habit phrase.
    public let habitTokens: Set<Int>
    public let counts: [String: Int]

    public var words: Int { tokens.filter { !$0.norm.isEmpty }.count }
}

public enum Speech {
    /// Habits in your own spoken words (a meeting transcript, where nothing was cleaned up), with
    /// context rules so "I like it" or "what kind of test" don't count.
    public static func mark(_ text: String) -> Marked {
        let tokens = Tokenizer.tokens(text)
        let idx = tokens.indices.filter { !tokens[$0].norm.isEmpty }
        let norms = idx.map { tokens[$0].norm }
        var counts: [String: Int] = [:]
        var marked = Set<Int>()
        var i = 0
        while i < norms.count {
            var matched = 0
            for (habit, phrase) in Habits.phrases where matches(norms, at: i, phrase) {
                let prev = i > 0 ? norms[i - 1] : ""
                let next = i + phrase.count < norms.count ? norms[i + phrase.count] : ""
                guard isHabit(habit.id, first: tokens[idx[i]], prev: prev, next: next) else { continue }
                counts[habit.id, default: 0] += 1
                for k in i..<(i + phrase.count) { marked.insert(idx[k]) }
                matched = phrase.count
                break
            }
            i += max(matched, 1)
        }
        return Marked(tokens: tokens, habitTokens: marked, counts: counts)
    }

    static func matches(_ norms: [String], at i: Int, _ phrase: [String]) -> Bool {
        guard i + phrase.count <= norms.count else { return false }
        return zip(norms[i...], phrase).allSatisfy { $0 == $1 }
    }

    private static let likeVerbs: Set<String> = ["feel", "feels", "felt", "look", "looks", "looked", "looking", "seem",
        "seems", "seemed", "sound", "sounds", "sounded", "something", "things", "stuff", "would", "i'd", "you'd",
        "we'd", "they'd", "don't", "didn't", "really", "i", "you", "we", "they"]
    private static let kindOfNouns: Set<String> = ["what", "this", "that", "the", "a", "any", "some", "same", "which",
        "every", "one", "another", "these", "those", "different", "only", "first", "whatever", "that's", "what's",
        "all", "no", "each", "right", "new", "other"]
    private static let youKnowObjects: Set<String> = ["what", "how", "that", "if", "why", "where", "when", "who",
        "whether", "the", "a", "it", "him", "her", "them", "about", "this", "me", "us", "my", "your"]

    /// Context rules for spoken text. A filler "like" is set off by a comma ("going, like, coinciding").
    static func isHabit(_ id: String, first: Token, prev: String, next: String) -> Bool {
        switch id {
        case "like": return first.text.hasSuffix(",") && !likeVerbs.contains(prev)
        case "kind of", "sort of": return !kindOfNouns.contains(prev)
        case "you know": return !youKnowObjects.contains(next)
        case "i mean": return prev != "what"
        default: return true
        }
    }
}
