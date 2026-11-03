import Foundation
import SQLite3

public struct DictionaryEntry: Sendable, Equatable {
    public let term: String
    public let phonetic: String
    public let translation: String
}
public struct DictionaryResult: Sendable {
    public enum Kind: String, Sendable { case exact, inflected, phrase, components, suggestion, missing }
    public let entries: [DictionaryEntry]
    public let kind: Kind
    public var note: String {
        switch kind {
        case .exact: return "离线词典 · 常规释义，未结合上下文消歧"
        case .inflected: return "离线词典 · 已还原词形，释义对应下方词条"
        case .phrase: return "离线词典 · 匹配到短语，可能只覆盖部分选文"
        case .components: return "离线词典 · 以下是词组与单词释义，不是整句翻译"
        case .suggestion: return "离线词典 · 可能存在拼写错误，请核对建议词条"
        case .missing: return "离线词典未收录这段文字，可尝试缩短选区。"
        }
    }
    public var text: String {
        guard let first = entries.first else { return "" }
        if entries.count == 1 {
            let lines = first.translation.components(separatedBy: "\n").filter { !$0.isEmpty }
            return (lines.first ?? first.translation) + "\n\n" + first.term + (first.phonetic.isEmpty ? "" : " /\(first.phonetic)/") + (lines.count > 1 ? "\n" + lines.dropFirst().joined(separator: "\n") : "")
        }
        return entries.map { "\($0.term)\n\($0.translation)" }.joined(separator: "\n\n")
    }
}

/// Read-only connection confined to an actor, with a 2 MB page cache and no full-table preload.
public actor OfflineDictionary {
    private var db: OpaquePointer?
    public init(path: String) throws {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw CocoaError(.fileReadCorruptFile)
        }
        db = connection
        sqlite3_exec(connection, "PRAGMA query_only=ON; PRAGMA cache_size=-2048; PRAGMA mmap_size=0;", nil, nil, nil)
    }
    deinit { sqlite3_close(db) }
    public static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?:;\"()[]{}"))
    }
    private func rows(_ sql: String, _ args: [String], limit: Int = 5) -> [DictionaryEntry] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in args.enumerated() { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
        var result: [DictionaryEntry] = []
        while result.count < limit && sqlite3_step(statement) == SQLITE_ROW {
            func string(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
            result.append(DictionaryEntry(term: string(0), phonetic: string(1), translation: String(string(2).prefix(1800))))
        }
        return result
    }
    private func exact(_ text: String) -> [DictionaryEntry] {
        rows("SELECT term,phonetic,translation FROM entries WHERE normalized=? ORDER BY rank LIMIT 3", [text], limit: 3)
    }
    private func forms(_ text: String) -> [DictionaryEntry] {
        rows("SELECT e.term,e.phonetic,e.translation FROM forms f JOIN entries e ON e.id=f.entry_id WHERE f.form=? ORDER BY e.rank LIMIT 3", [text], limit: 3)
    }
    private func variants(_ word: String) -> [String] {
        var result = [word]
        func add(_ value: String) { if !value.isEmpty && !result.contains(value) { result.append(value) } }
        for entry in forms(word) { add(Self.normalize(entry.term)) }
        if word.hasSuffix("'s") { add(String(word.dropLast(2))) }
        if word.hasSuffix("s'") { add(String(word.dropLast())) }
        // Rules are only accepted if the resulting headword exists; suggestions are labelled.
        var guesses: [String] = []
        if word.count > 4 && word.hasSuffix("ies") { guesses.append(String(word.dropLast(3)) + "y") }
        if word.count > 4 && word.hasSuffix("ing") {
            let stem = String(word.dropLast(3)); guesses += [stem, stem + "e"]
            if stem.count > 2 && stem.last == stem.dropLast().last { guesses.append(String(stem.dropLast())) }
        }
        if word.count > 3 && word.hasSuffix("ed") { guesses += [String(word.dropLast(2)), String(word.dropLast())] }
        if word.count > 3 && word.hasSuffix("es") { guesses.append(String(word.dropLast(2))) }
        if word.count > 2 && word.hasSuffix("s") { guesses.append(String(word.dropLast())) }
        for guess in guesses where !exact(guess).isEmpty { add(guess) }
        return Array(result.prefix(5))
    }
    private func matchPhrase(_ words: [String]) -> (DictionaryEntry, Bool)? {
        let original = words.joined(separator: " ")
        if let entry = exact(original).first { return (entry, false) }
        var candidates = [""]
        for word in words {
            candidates = Array(candidates.flatMap { prefix in variants(word).map { prefix.isEmpty ? $0 : prefix + " " + $0 } }.prefix(96))
        }
        for candidate in candidates where candidate != original {
            if let entry = exact(candidate).first { return (entry, true) }
        }
        return nil
    }
    public func lookup(_ input: String) -> DictionaryResult {
        let text = Self.normalize(String(input.prefix(1000)))
        guard !Task.isCancelled, !text.isEmpty else { return DictionaryResult(entries: [], kind: .missing) }
        let direct = exact(text)
        if !direct.isEmpty { return DictionaryResult(entries: direct, kind: .exact) }
        let inflected = forms(text)
        if !inflected.isEmpty { return DictionaryResult(entries: Array(inflected.prefix(2)), kind: .inflected) }
        let words = Array(text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "-" }).map(String.init).prefix(24))
        guard !words.isEmpty else { return DictionaryResult(entries: [], kind: .missing) }
        if words.count <= 6, let (entry, changed) = matchPhrase(words) {
            return DictionaryResult(entries: [entry], kind: changed ? .inflected : .exact)
        }
        // Separable phrasal verbs: "turned it down" → "turn down". Never discard arbitrary words.
        if words.count == 3, ["it", "them", "me", "him", "her", "us", "you"].contains(words[1]),
           let (entry, _) = matchPhrase([words[0], words[2]]) {
            return DictionaryResult(entries: [entry], kind: .phrase)
        }
        var entries: [DictionaryEntry] = [], index = 0
        let stop: Set<String> = ["a", "an", "the", "i", "you", "he", "she", "it", "we", "they", "is", "are", "was", "were", "be", "to", "of", "and", "in", "on", "this", "that", "for"]
        var phrase = false
        while index < words.count && entries.count < 5 && !Task.isCancelled {
            var matched = false
            let maximum = min(6, words.count - index)
            if maximum >= 2 {
                for length in stride(from: maximum, through: 2, by: -1) {
                    if let (entry, _) = matchPhrase(Array(words[index..<(index + length)])) {
                        if !entries.contains(entry) { entries.append(entry) }
                        index += length; matched = true; phrase = true; break
                    }
                }
            }
            if matched { continue }
            let word = words[index]
            if words.count == 1 || !stop.contains(word) {
                if let entry = variants(word).lazy.compactMap({ self.exact($0).first }).first, !entries.contains(entry) { entries.append(entry) }
            }
            index += 1
        }
        if !entries.isEmpty {
            return DictionaryResult(entries: entries, kind: words.count == 1 ? .inflected : (phrase && entries.count == 1 ? .phrase : .components))
        }
        // Bounded spelling candidates, indexed prefix range, never silently treated as an exact answer.
        if words.count == 1, (4...24).contains(text.count) {
            var candidates: [DictionaryEntry] = []
            var letters = Array(text)
            for i in 0..<(letters.count - 1) {
                letters.swapAt(i, i + 1); candidates += exact(String(letters)); letters.swapAt(i, i + 1)
            }
            let prefix = String(text.prefix(2))
            candidates += rows("SELECT term,phonetic,translation FROM entries WHERE normalized>=? AND normalized<? AND length(normalized) BETWEEN ? AND ? ORDER BY rank LIMIT 160", [prefix, prefix + "{", String(text.count - 1), String(text.count + 1)], limit: 160)
            var suggestions: [DictionaryEntry] = []
            for entry in candidates where Self.oneEdit(text, Self.normalize(entry.term)) && !suggestions.contains(entry) { suggestions.append(entry); if suggestions.count == 3 { break } }
            if !suggestions.isEmpty { return DictionaryResult(entries: suggestions, kind: .suggestion) }
        }
        return DictionaryResult(entries: [], kind: .missing)
    }
    private static func oneEdit(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 1 else { return false }
        if a.count == b.count {
            let different = a.indices.filter { a[$0] != b[$0] }
            if different.count <= 1 { return true }
            return different.count == 2 && different[1] == different[0] + 1 && a[different[0]] == b[different[1]] && a[different[1]] == b[different[0]]
        }
        let short = a.count < b.count ? a : b, long = a.count < b.count ? b : a
        var i = 0, j = 0
        while i < short.count && j < long.count { if short[i] == long[j] { i += 1 }; j += 1; if j - i > 1 { return false } }
        return true
    }
}
