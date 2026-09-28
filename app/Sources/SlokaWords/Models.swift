import Foundation

struct Deck: Codable {
    var sources: [Source]
    var words: [Word]
    var verses: [Verse]

    static let empty = Deck(sources: [], words: [], verses: [])

    init(sources: [Source], words: [Word], verses: [Verse]) {
        self.sources = sources
        self.words = words
        self.verses = verses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = try c.decode([Source].self, forKey: .sources)
        words = try c.decode([Word].self, forKey: .words)
        verses = try c.decodeIfPresent([Verse].self, forKey: .verses) ?? []
    }
}

struct Verse: Codable, Identifiable, Hashable {
    let id: String
    let src: String
    let group: String
    let label: String
    var deva: [String]
    var te: [String]
    var iast: [String]
    let teMeaning: String
    let enMeaning: String
    let words: String
    var edited: Bool

    var key: String { GroupKey.make(src, group) }

    enum CodingKeys: String, CodingKey {
        case id, src, group, label, deva, te, iast, words, edited
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
    case words, verses

    var id: String { rawValue }
    var title: String { self == .words ? "Words" : "Verses" }
}

struct Source: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let lang: String
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
