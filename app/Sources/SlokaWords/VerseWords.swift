import Foundation

/// One row of a verse's vocabulary: a deck word card, or a gloss that has no card.
struct VerseWord: Identifiable, Hashable {
    let id: String
    /// Deck word id when this row can be studied as a word card.
    let cardID: String?
    let te: String
    let deva: String
    let iast: String
    let teMeaning: String
    let en: [String]
}

/// Matches a verse's word-by-word gloss to word cards, in chanting order.
enum VerseWords {
    private static let particles: Set<String> = ["ca", "eva", "api", "hi", "tu", "vā"]

    static func entries(for verse: Verse, words: [Word], labelShared: Bool) -> [VerseWord] {
        let useCards = !verse.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !labelShared
        let cards = useCards
            ? words.filter { word in
                word.refs.contains { $0.src == verse.src && $0.group == verse.group && $0.label == verse.label }
            }
            : []
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<String>()
        var entries: [VerseWord] = []
        var glossIndex = 0

        func addCard(_ word: Word, gloss: String? = nil) {
            guard used.insert(word.id).inserted else { return }
            entries.append(VerseWord(
                id: word.id, cardID: word.id, te: word.te, deva: word.deva, iast: word.iast,
                teMeaning: word.teMeaning, en: gloss.map { [$0] } ?? word.en))
        }

        for (head, meaning) in glossHeads(verse.words) {
            let hits = match(head: head, byID: byID)
            if hits.isEmpty {
                entries.append(VerseWord(
                    id: "gloss-\(glossIndex)-\(head)", cardID: nil, te: "", deva: "", iast: head,
                    teMeaning: "", en: [meaning]))
                glossIndex += 1
            } else if hits.count == 1 {
                addCard(hits[0], gloss: meaning)
            } else {
                hits.forEach { addCard($0) }
            }
        }
        cards.forEach { addCard($0) }
        return entries
    }

    static func cardIDs(for verse: Verse, words: [Word], labelShared: Bool) -> [String] {
        var seen = Set<String>()
        return entries(for: verse, words: words, labelShared: labelShared).compactMap { entry in
            guard let id = entry.cardID, seen.insert(id).inserted else { return nil }
            return id
        }
    }

    private static func match(head: String, byID: [String: Word]) -> [Word] {
        for key in [wordKey(stripParticles(head)), wordKey(stripParticles(chForC(head)))] {
            if let word = byID[key] { return [word] }
        }
        let parts = stripParticles(head).split(separator: " ").map(String.init)
        if parts.count > 1 {
            let hits = parts.compactMap { byID[wordKey($0)] ?? byID[wordKey(chForC($0))] }
            if hits.count == parts.count { return hits }
        }
        return []
    }

    /// Same key `tools/build_deck.py` uses, so a gloss head finds its word card.
    private static func wordKey(_ head: String) -> String {
        var s = head.precomposedStringWithCanonicalMapping.lowercased()
        s = s.replacingOccurrences(of: "ṁ", with: "ṃ")
            .replacingOccurrences(of: "ō", with: "o")
            .replacingOccurrences(of: "ē", with: "e")
            .replacingOccurrences(of: "'", with: "’")
            .replacingOccurrences(of: "-", with: "")
        s = String(s.filter { $0.isLetter || $0.isNumber || $0 == "’" })
        if s.hasSuffix("ṃ") {
            s.removeLast()
            s.append("m")
        }
        let stops: [Character: Character] = ["d": "t", "g": "k", "b": "p", "ḍ": "ṭ"]
        if let last = s.last, let replacement = stops[last] {
            s.removeLast()
            s.append(replacement)
        }
        return s
    }

    /// Gita pages spell च as "ch". "chh" (छ) is left as "ch".
    private static func chForC(_ text: String) -> String {
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("chh") {
                out.append("ch")
                index = text.index(index, offsetBy: 3)
                continue
            }
            if text[index...].hasPrefix("ch") {
                let previous = index == text.startIndex ? nil : text[text.index(before: index)]
                out.append(previous == "c" ? "ch" : "c")
                index = text.index(index, offsetBy: 2)
                continue
            }
            out.append(text[index])
            index = text.index(after: index)
        }
        return out
    }

    private static func isParticle(_ token: String) -> Bool {
        particles.contains(wordKey(chForC(token)))
    }

    private static func stripParticles(_ iast: String) -> String {
        var tokens = iast.split(separator: " ").map(String.init)
        while tokens.count > 1 && isParticle(tokens[tokens.count - 1]) { tokens.removeLast() }
        while tokens.count > 1 && isParticle(tokens[0]) { tokens.removeFirst() }
        return tokens.joined(separator: " ")
    }

    private static func glossHeads(_ text: String) -> [(String, String)] {
        var items: [(String, String)] = []
        var cur = ""
        var depth = 0
        func flush() {
            let item = cur.trimmingCharacters(in: .whitespaces)
            cur = ""
            if let parsed = parseGloss(item) { items.append(parsed) }
        }
        for ch in text {
            if ch == "(" { depth += 1 }
            else if ch == ")" { depth = max(0, depth - 1) }
            if (ch == "," || ch == ";") && depth == 0 { flush() }
            else { cur.append(ch) }
        }
        flush()
        return items
    }

    private static func parseGloss(_ item: String) -> (String, String)? {
        guard let start = item.firstIndex(of: "("), start != item.startIndex else { return nil }
        var depth = 0
        var end: String.Index?
        var index = start
        while index < item.endIndex {
            if item[index] == "(" { depth += 1 }
            else if item[index] == ")" {
                depth -= 1
                if depth == 0 { end = index; break }
            }
            index = item.index(after: index)
        }
        guard let end else { return nil }
        let head = rstrip(item[..<start].trimmingCharacters(in: .whitespaces), in: ".:")
        let meaning = rstrip(
            item[item.index(after: start)..<end].trimmingCharacters(in: .whitespaces),
            in: "."
        ).trimmingCharacters(in: .whitespaces)
        if head.isEmpty || meaning.isEmpty { return nil }
        return (head, meaning)
    }

    private static func rstrip(_ text: some StringProtocol, in chars: String) -> String {
        var result = String(text)
        while let last = result.last, chars.contains(last) { result.removeLast() }
        return result
    }
}
