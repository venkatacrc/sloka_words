import Foundation

struct Deck: Codable {
    var sources: [Source]
    var words: [Word]
    var verses: [Verse]
    var grammar: [GrammarCard]

    static let empty = Deck(sources: [], words: [], verses: [], grammar: [])

    init(sources: [Source], words: [Word], verses: [Verse], grammar: [GrammarCard]) {
        self.sources = sources
        self.words = words
        self.verses = verses
        self.grammar = grammar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = try c.decode([Source].self, forKey: .sources)
        words = try c.decode([Word].self, forKey: .words)
        verses = try c.decodeIfPresent([Verse].self, forKey: .verses) ?? []
        grammar = try c.decodeIfPresent([GrammarCard].self, forKey: .grammar) ?? []
    }

    func sources(for kind: CardKind) -> [Source] {
        sources.filter { ($0.kind == "grammar") == (kind == .grammar) }
    }
}

/// A grammar lesson card: one table row, drill or dialogue line from a study page.
struct GrammarCard: Codable, Identifiable, Hashable {
    let id: String
    let src: String
    let group: String
    let label: String
    let context: String
    let prompt: Cell
    let answer: [Cell]
    let link: String?

    var key: String { GroupKey.make(src, group) }

    struct Cell: Codable, Hashable {
        let head: String
        let text: String
        /// Telugu-script reading, present when the text contains Devanagari.
        let te: String?
    }
}

struct Verse: Codable, Identifiable, Hashable {
    let id: String
    let src: String
    let group: String
    let label: String
    /// "arjuna uvāca" and similar, shown above the verse; not part of chanting-style edits.
    let speaker: Speaker?
    var deva: [String]
    var te: [String]
    var iast: [String]
    let teMeaning: String
    let enMeaning: String
    let words: String
    var edited: Bool
    /// The lines with a space at every word boundary, for word-separated printing
    /// (made by tools/verse_split.py). Nil once the verse is edited in the app.
    var split: SplitLines?

    var key: String { GroupKey.make(src, group) }

    enum CodingKeys: String, CodingKey {
        case id, src, group, label, speaker, deva, te, iast, words, edited, split
        case teMeaning = "te_meaning"
        case enMeaning = "en_meaning"
    }

    func applying(_ edit: VerseEdit?) -> Verse {
        guard let edit else { return self }
        var v = self
        v.te = edit.te.lines
        v.deva = edit.deva.lines
        v.iast = edit.iast.lines
        v.edited = true
        // An edit already pushed into the deck leaves the text as it is, and its split lines still fit.
        if v.te != te || v.deva != deva || v.iast != iast { v.split = nil }
        return v
    }
}

struct SplitLines: Codable, Hashable {
    let deva: [String]
    let te: [String]
    let iast: [String]

    /// The verse's own spaces shown three wide; breaks added by tools/verse_split.py (thin
    /// spaces in the deck) shown as one plain space.
    static func display(_ lines: [String]) -> [String] {
        lines.map { $0.replacingOccurrences(of: " ", with: "   ").replacingOccurrences(of: "\u{2009}", with: " ") }
    }
}

extension Verse {
    static let splitDevaKey = "splitDevanagari"

    /// The Devanagari lines, word-separated when asked and available.
    func devaLines(split: Bool) -> [String] {
        guard split, let lines = self.split?.deva else { return deva }
        return SplitLines.display(lines)
    }
}

struct Speaker: Codable, Hashable {
    let deva: String
    let te: String
    let iast: String
}

/// A chanting-style rewrite of a verse; each field holds the verse lines separated by newlines.
struct VerseEdit: Codable, Hashable {
    var te: String
    var deva: String
    var iast: String
}

extension String {
    var lines: [String] {
        split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

enum CardKind: String, CaseIterable, Identifiable {
    case words, verses, grammar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .words: "Words"
        case .verses: "Verses"
        case .grammar: "Grammar"
        }
    }
}

/// The script shown first and largest on the cards; the other two follow in smaller type.
enum MainScript: String, CaseIterable, Identifiable {
    case te, deva, iast

    static let storageKey = "mainScript"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .te: "తెలుగు"
        case .deva: "देवनागरी"
        case .iast: "English"
        }
    }

    var cardLabel: String {
        switch self {
        case .te: "తెలుగు"
        case .deva: "हिन्दी"
        case .iast: "IAST"
        }
    }

    /// Latin letters look bigger than Telugu or Devanagari at the same point size.
    var scale: CGFloat { self == .iast ? 0.8 : 1 }

    /// All three scripts, this one first.
    var order: [MainScript] { [self] + Self.allCases.filter { $0 != self } }

    func text(_ te: String, _ deva: String, _ iast: String) -> String {
        switch self {
        case .te: te
        case .deva: deva
        case .iast: iast
        }
    }
}

struct Source: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let lang: String
    /// `grammar` for lesson sources; nil for texts with word and verse cards.
    let kind: String?
    let groups: [SourceGroup]
}

struct SourceGroup: Codable, Identifiable, Hashable {
    let id: String
    let label: String
}

struct Ref: Codable, Hashable {
    let src: String
    let group: String
    let label: String

    var key: String { GroupKey.make(src, group) }
}

struct Word: Codable, Identifiable, Hashable {
    let id: String
    let iast: String
    let deva: String
    let te: String
    let en: [String]
    let teMeaning: String
    let refs: [Ref]

    enum CodingKeys: String, CodingKey {
        case id, iast, deva, te, en, refs
        case teMeaning = "te_meaning"
    }
}

/// A `(source, group)` pair such as `gita|12`, used for chapter/section selection.
enum GroupKey {
    static func make(_ src: String, _ group: String) -> String { "\(src)|\(group)" }
}
