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

    var key: String { GroupKey.make(src, group) }

    enum CodingKeys: String, CodingKey {
        case id, src, group, label, speaker, deva, te, iast, words, edited
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
        return v
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
