import Foundation

/// What Wispr removed from a dictation: the raw speech-to-text compared with the cleaned text.
/// Only habit phrases Wispr deleted outright count. That separates filler "like" from "I like it"
/// (kept) and from "things like" rewritten as "such as" (replaced, not deleted).
public enum Cleanup {
    /// A deleted stretch longer than this is a rewrite, not filler, and doesn't count.
    static let maxRemovedRun = 8
    /// Above this many cells the word diff is skipped (a very long dictation; rare).
    static let maxCells = 6_000_000

    public static func mark(raw: String, cleaned: String) -> Marked {
        let tokens = Tokenizer.tokens(raw)
        let idx = tokens.indices.filter { !tokens[$0].norm.isEmpty }
        let a = idx.map { tokens[$0].norm }
        let b = Tokenizer.tokens(cleaned).map(\.norm).filter { !$0.isEmpty }
        guard !a.isEmpty, a.count * max(b.count, 1) <= maxCells else {
            return Marked(tokens: tokens, habitTokens: [], counts: [:])
        }
        let eligible = deletedMask(a, b)

        var counts: [String: Int] = [:]
        var marked = Set<Int>()
        var i = 0
        while i < a.count {
            var matched = 0
            for (habit, phrase) in Habits.phrases where Speech.matches(a, at: i, phrase)
                && (i..<(i + phrase.count)).allSatisfy({ eligible[$0] }) {
                counts[habit.id, default: 0] += 1
                for k in i..<(i + phrase.count) { marked.insert(idx[k]) }
                matched = phrase.count
                break
            }
            i += max(matched, 1)
        }
        return Marked(tokens: tokens, habitTokens: marked, counts: counts)
    }

    /// For each word of `a`, whether Wispr deleted it: missing from the longest common subsequence
    /// with `b`, with nothing written in its place, in a stretch no longer than `maxRemovedRun`.
    static func deletedMask(_ a: [String], _ b: [String]) -> [Bool] {
        let n = a.count, m = b.count
        // lcs[i * w + j] = LCS length of a[i...] and b[j...].
        let w = m + 1
        var lcs = [Int32](repeating: 0, count: (n + 1) * w)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i * w + j] = a[i] == b[j] ? lcs[(i + 1) * w + j + 1] + 1
                    : max(lcs[(i + 1) * w + j], lcs[i * w + j + 1])
            }
        }
        // Words of `a` kept in `b`, as (i, j) pairs, bracketed by virtual anchors at both ends.
        var kept: [(Int, Int)] = [(-1, -1)]
        var i = 0, j = 0
        while i < n, j < m {
            if a[i] == b[j] { kept.append((i, j)); i += 1; j += 1 }
            else if lcs[(i + 1) * w + j] >= lcs[i * w + j + 1] { i += 1 }
            else { j += 1 }
        }
        kept.append((n, m))
        var deleted = Array(repeating: false, count: n)
        for (x, y) in zip(kept, kept.dropFirst()) {
            let gapA = x.0 + 1..<y.0, gapB = y.1 - x.1 - 1
            if gapB == 0, !gapA.isEmpty, gapA.count <= maxRemovedRun { for k in gapA { deleted[k] = true } }
        }
        return deleted
    }
}
