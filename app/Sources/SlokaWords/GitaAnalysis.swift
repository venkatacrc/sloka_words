import Foundation

// Samsaadhanii's Gītā analysis: word split, anvaya, word analysis and kāraka graph.
// gita_analysis.json says where each verse's file is; the file itself is downloaded from
// Samsaadhanii's GitHub the first time the verse is opened, then kept in Application Support.
// Mirrors web/analysis.js.

struct GitaAnalysisIndex: Decodable {
    struct SourceInfo: Decodable {
        let name: String
        let repo: String
        let commit: String
        let dir: String
        let url: String
        let credit: String
    }

    let source: SourceInfo
    let verses: [String: [String]]
    let relations: [String: RelationInfo]
    let aliases: [String: String]
    let tags: [String: TagInfo]
}

/// Our own draft analysis, bundled with the app: verse id → TSV text.
struct BundledAnalysis: Decodable {
    struct SourceInfo: Decodable {
        let name: String
        let credit: String
        let draft: Bool
    }

    let source: SourceInfo
    let verses: [String: String]
}

struct RelationInfo: Decodable, Hashable {
    let sa: String
    let kind: String
    let te: String
    let en: String
}

struct TagInfo: Decodable, Hashable {
    let sa: String
    let te: String
}

enum AnalysisScript: String, CaseIterable, Identifiable {
    case te, deva
    var id: String { rawValue }
    var title: String { self == .te ? "తెలుగు" : "देवनागरी" }
}

enum AnalysisTab: String, CaseIterable, Identifiable {
    case split, anvaya, words, graph
    var id: String { rawValue }
}

struct AnalysisRow {
    let id: String
    let parts: [String]
    let word: String
    let poem: Double?
    let sandhi: String
    let morph: String
    let rel: ParsedRelation
    let en: String
}

struct ParsedRelation {
    let name: String
    let target: String
    let info: RelationInfo?
}

struct Morph {
    var stem = ""
    var tags: [String] = []
    var root = ""
    var rootTags: [String] = []
    var isRoot = false
}

/// A word: one row, the rows of a compound ("4.1", "4.2"), or an understood word ("4.1.1").
final class AnalysisWord: Identifiable {
    let id: String
    let supplied: Bool
    var rows: [AnalysisRow] = []
    var poem: Double?
    var en = ""
    var text = ""
    var compound: [(word: String, rel: RelationInfo?)]?
    var morph = Morph()
    var rel: RelationInfo?
    weak var target: AnalysisWord?
    weak var parent: AnalysisWord?
    var children: [AnalysisWord] = []

    init(id: String, supplied: Bool) {
        self.id = id
        self.supplied = supplied
    }
}

struct SandhiGroup {
    let joined: String
    var words: [AnalysisWord]
}

struct AnalysisModel {
    let words: [AnalysisWord]
    let verseOrder: [AnalysisWord]
    let anvaya: [AnalysisWord]
    let sentences: [AnalysisWord]
    let splits: [SandhiGroup]
}

@MainActor
final class GitaAnalysisStore: ObservableObject {
    static let windowID = "analysis"

    @Published private(set) var savedCount = 0
    @Published private(set) var saving: (done: Int, total: Int, failed: Int)?
    /// Verse shown in the analysis window, with its deck words for Telugu meanings.
    @Published private(set) var verse: Verse?
    @Published private(set) var deckWords: [VerseWord] = []
    /// While the window is open it follows the verse card the reader moves to.
    var windowOpen = false

    let index: GitaAnalysisIndex?
    /// Vishnu Sahasranamam; Samsaadhanii has no analysis of it.
    let bundled: BundledAnalysis?
    private var models: [String: AnalysisModel] = [:]
    private static let bundledPrefix = "vs:"

    init() {
        func resource<T: Decodable>(_ name: String, as type: T.Type) -> T? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json")
                    ?? Bundle.module.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        index = resource("gita_analysis", as: GitaAnalysisIndex.self)
        bundled = resource("vs_analysis", as: BundledAnalysis.self)
        refreshSavedCount()
    }

    func isBundled(_ verse: Verse) -> Bool { verse.src == "vs" }

    func files(for verse: Verse) -> [String] {
        if isBundled(verse) {
            return bundled?.verses[verse.id] != nil ? [Self.bundledPrefix + verse.id] : []
        }
        guard verse.src == "gita", let index else { return [] }
        let parts = verse.id.split(separator: ":")
        guard parts.count == 3 else { return [] }
        return index.verses["\(parts[1]):\(parts[2])"] ?? []
    }

    func has(_ verse: Verse) -> Bool { !files(for: verse).isEmpty }

    func show(_ verse: Verse, words: [VerseWord]) {
        guard self.verse != verse || deckWords != words else { return }
        self.verse = verse
        deckWords = words
    }

    /// Verse numbers ("1.4") a file covers, for files that analyse several verses together.
    func versesInFile(_ stem: String) -> [String] {
        guard let index, !stem.hasPrefix(Self.bundledPrefix) else { return [] }
        return index.verses.filter { $0.value.contains(stem) }.keys
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
            .map { $0.replacingOccurrences(of: ":", with: ".") }
    }

    var allFiles: [String] {
        guard let index else { return [] }
        return Array(Set(index.verses.values.joined())).sorted()
    }

    private var cacheDir: URL? {
        guard let index else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SlokaWords/samsaadhanii/\(index.source.commit)", isDirectory: true)
    }

    private func cachedFile(_ stem: String) -> URL? {
        cacheDir?.appendingPathComponent(stem + ".tsv")
    }

    private func remoteURL(_ stem: String) -> URL? {
        guard let index else { return nil }
        let name = stem.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stem
        return URL(string: index.source.url + name + ".tsv")
    }

    func refreshSavedCount() {
        guard let dir = cacheDir else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        savedCount = names.filter { $0.hasSuffix(".tsv") }.count
    }

    private func download(_ stem: String) async throws -> String {
        guard let url = remoteURL(stem), let file = cachedFile(stem) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "GitaAnalysis", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return String(decoding: data, as: UTF8.self)
    }

    func model(_ stem: String) async throws -> AnalysisModel {
        if let model = models[stem] { return model }
        let text: String
        if stem.hasPrefix(Self.bundledPrefix) {
            guard let tsv = bundled?.verses[String(stem.dropFirst(Self.bundledPrefix.count))] else {
                throw URLError(.fileDoesNotExist)
            }
            text = tsv
        } else if let file = cachedFile(stem), let saved = try? String(contentsOf: file, encoding: .utf8) {
            text = saved
        } else {
            text = try await download(stem)
            refreshSavedCount()
        }
        guard let index else { throw URLError(.fileDoesNotExist) }
        let model = AnalysisParser(index: index).build(text)
        models[stem] = model
        return model
    }

    func downloadAll() async {
        let files = allFiles
        let todo = files.filter { stem in
            guard let file = cachedFile(stem) else { return false }
            return !FileManager.default.fileExists(atPath: file.path)
        }
        var done = files.count - todo.count
        var failed = 0
        saving = (done, files.count, failed)
        var queue = todo[...]
        await withTaskGroup(of: Bool.self) { group in
            func next() {
                guard let stem = queue.popFirst() else { return }
                group.addTask { [weak self] in
                    guard let self else { return false }
                    return (try? await self.download(stem)) != nil
                }
            }
            for _ in 0..<6 { next() }
            for await ok in group {
                if ok { done += 1 } else { failed += 1 }
                saving = (done, files.count, failed)
                next()
            }
        }
        refreshSavedCount()
        saving = failed > 0 ? (done, files.count, failed) : nil
    }
}

// MARK: - Script

enum Script {
    private static let anusvaraRules: [(NSRegularExpression, String)] = [
        ("ఙ్(-?)(?=[కఖగఘ])", "ం$1"), ("ఞ్(-?)(?=[చఛజఝ])", "ం$1"), ("ణ్(-?)(?=[టఠడఢ])", "ం$1"),
        ("న్(-?)(?=[తథదధ])", "ం$1"), ("మ్(-?)(?=[పఫబభ])", "ం$1"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// Same conversion the deck builder uses for its Telugu lines.
    static func devaToTelugu(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let c = scalar.value
            if scalar == "ॐ" {
                out.append(contentsOf: "ఓం".unicodeScalars)
            } else if c == 0x093C {
                continue
            } else if c >= 0x0901 && c <= 0x0963 && c != 0x0964 && c != 0x0965, let te = Unicode.Scalar(c + 0x300) {
                out.append(te)
            } else {
                out.append(scalar)
            }
        }
        var result = String(out)
        for (re, template) in anusvaraRules {
            result = re.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        return result
    }

    static func show(_ deva: String, _ script: AnalysisScript) -> String {
        script == .te ? devaToTelugu(deva) : deva
    }
}

extension String {
    /// Suffix test on Unicode scalars, so a vowel sign such as "ा" can be matched on its own.
    func endsWithScalars(_ suffix: String) -> Bool {
        unicodeScalars.reversed().starts(with: suffix.unicodeScalars.reversed())
    }
}

// MARK: - Parsing

struct AnalysisParser {
    let index: GitaAnalysisIndex

    private static let zeroWidth: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{00A0}"]
    private static let dottedTarget = try! NSRegularExpression(pattern: #"^(.*?[^\d.])\.(\d+(?:\.\d+)*)$"#)
    private static let morphShape = try! NSRegularExpression(pattern: #"^([^{]*)\{(.*)\}\s*$"#)
    private static let braceJoin = try! NSRegularExpression(pattern: #"\}\s*\{"#)
    private static let finiteTags: Set<String> = [
        "लट्", "लिट्", "लुट्", "लृट्", "लोट्", "लङ्", "विधिलिङ्", "आशीर्लिङ्", "लुङ्", "लृङ्", "ल्यप्", "क्त्वा", "तुमुन्",
    ]

    static func relationKey(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in name.unicodeScalars where !zeroWidth.contains(s) {
            if s.properties.isWhitespace || s == "_" || s == "." || s == "-" || ("0"..."9").contains(s) { continue }
            scalars.append(s)
        }
        if scalars.last == "ः" { scalars.removeLast() }
        return String(scalars)
    }

    func relationInfo(_ name: String) -> RelationInfo? {
        guard !name.isEmpty else { return nil }
        var key = Self.relationKey(name)
        guard !key.isEmpty else { return nil }
        key = index.aliases[key] ?? key
        return index.relations[key]
            ?? RelationInfo(sa: name.replacingOccurrences(of: "_", with: " "), kind: "other", te: "", en: "")
    }

    /// "कर्ता,10.1" → name and target; also "अभिहित_कर्ता.15.3.1" with a dot for the comma.
    func parseRelation(_ raw: String) -> ParsedRelation {
        let first = (raw.split(separator: ";", omittingEmptySubsequences: false).first.map(String.init) ?? "").trimmed
        var name = first
        var target = ""
        if let comma = first.firstIndex(of: ",") {
            name = first[..<comma].trimmed
            target = first[first.index(after: comma)...].trimmed
        } else if let m = Self.dottedTarget.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)),
                  let n = Range(m.range(at: 1), in: first), let t = Range(m.range(at: 2), in: first) {
            name = String(first[n])
            target = String(first[t])
        }
        target = String(target.unicodeScalars.filter { $0 == "." || ("0"..."9").contains($0) }.map(Character.init))
        return ParsedRelation(name: name, target: target, info: relationInfo(name))
    }

    func parseTsv(_ text: String) -> [AnalysisRow] {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        let lines = body.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        guard let headLine = lines.first else { return [] }
        let head = headLine.components(separatedBy: "\t").map { $0.trimmed.lowercased() }
        func col(_ name: String) -> Int { head.firstIndex { $0 == name || $0.hasPrefix(name + ".") } ?? -1 }
        let cIndex = [col("index"), col("anvaya_no"), 0].first { $0 >= 0 } ?? 0
        let cWord = col("word"), cPoem = col("poem"), cSandhi = col("sandhied_word")
        let cMorph = col("morph_in_context"), cRel = col("kaaraka_sambandha"), cEn = col("english_meaning")
        var rows: [AnalysisRow] = []
        for line in lines.dropFirst() {
            let cells = line.components(separatedBy: "\t")
            func get(_ i: Int) -> String { i >= 0 && i < cells.count ? cells[i].trimmed : "" }
            var id = get(cIndex)
            while id.hasSuffix(".") { id.removeLast() }
            let parts = id.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !id.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }), !get(cWord).isEmpty else { continue }
            let sandhi = get(cSandhi)
            rows.append(AnalysisRow(
                id: id,
                parts: parts,
                word: get(cWord),
                poem: Scanner(string: get(cPoem)).scanDouble(),
                sandhi: sandhi == "-" ? "" : sandhi,
                morph: get(cMorph),
                rel: parseRelation(get(cRel)),
                en: get(cEn).replacingOccurrences(of: "_", with: " ")
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")))
        }
        return rows
    }

    private static func wordID(_ rowID: String) -> String {
        let parts = rowID.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 3 ? rowID : String(parts.first ?? "")
    }

    func build(_ text: String) -> AnalysisModel {
        let rows = parseTsv(text)
        var words: [AnalysisWord] = []
        var byID: [String: AnalysisWord] = [:]
        for row in rows {
            let wid = Self.wordID(row.id)
            let w: AnalysisWord
            if let existing = byID[wid] {
                w = existing
            } else {
                w = AnalysisWord(id: wid, supplied: row.parts.count >= 3)
                byID[wid] = w
                words.append(w)
            }
            w.rows.append(row)
            if w.poem == nil, let poem = row.poem { w.poem = poem }
            if w.en.isEmpty { w.en = row.en }
        }
        func resolve(_ target: String) -> AnalysisWord? {
            guard !target.isEmpty else { return nil }
            if let exact = byID[target], exact.supplied { return exact }
            return byID[Self.wordID(target)]
                ?? byID[String(target.split(separator: ".", omittingEmptySubsequences: false).first ?? "")]
        }
        for w in words {
            w.text = w.rows.map(\.word).joined()
            w.compound = w.rows.count > 1
                ? w.rows.map { r in (r.word, resolve(r.rel.target) === w ? r.rel.info : nil) }
                : nil
            let outward = w.rows.reversed().first { r in
                guard let t = resolve(r.rel.target) else { return false }
                return t !== w
            }
            let headRow = outward ?? w.rows[w.rows.count - 1]
            w.morph = parseMorph(headRow.morph)
            w.rel = headRow.rel.info
            w.target = outward.flatMap { resolve($0.rel.target) }
        }

        // Parents: a word hangs under the word its relation points to. The verb's own
        // "abhihita" relation only notes agreement, so it does not make an edge.
        for w in words {
            w.parent = (w.target != nil && w.rel != nil && w.rel?.kind != "verb") ? w.target : nil
            w.children = []
        }
        for w in words {
            var seen: Set<ObjectIdentifier> = [ObjectIdentifier(w)]
            var p = w.parent
            while let node = p {
                if !seen.insert(ObjectIdentifier(node)).inserted { w.parent = nil; break }
                p = node.parent
            }
        }
        for w in words { w.parent?.children.append(w) }

        let anvaya = words.enumerated()
            .sorted { a, b in
                let pa = a.element.poem ?? 1e9, pb = b.element.poem ?? 1e9
                return pa != pb ? pa < pb : a.offset < b.offset
            }
            .map(\.element)
        var rank: [ObjectIdentifier: Int] = [:]
        for (i, w) in anvaya.enumerated() { rank[ObjectIdentifier(w)] = i }
        for w in words { w.children.sort { rank[ObjectIdentifier($0)]! < rank[ObjectIdentifier($1)]! } }
        let sentences = anvaya.filter { $0.parent == nil }

        let verseOrder = words.filter { !$0.supplied }
        var sandhi: [SandhiGroup] = []
        for row in rows where row.parts.count < 3 {
            if !row.sandhi.isEmpty || sandhi.isEmpty { sandhi.append(SandhiGroup(joined: row.sandhi, words: [])) }
            guard let w = byID[Self.wordID(row.id)] else { continue }
            if !sandhi[sandhi.count - 1].words.contains(where: { $0 === w }) { sandhi[sandhi.count - 1].words.append(w) }
        }
        func plain(_ s: String) -> String { String(s.filter { $0 != "-" && !$0.isWhitespace }) }
        let splits = sandhi.filter { g in
            !g.joined.isEmpty && !g.words.isEmpty && (g.words.count > 1 || plain(g.joined) != plain(g.words[0].text))
        }
        return AnalysisModel(words: words, verseOrder: verseOrder, anvaya: anvaya, sentences: sentences, splits: splits)
    }

    /// "सञ्जनयत्{पुं;1;एक(जन्2;शतृ_लट्;जनी;:दिवादिः)}" → stem, tags, and the root it comes from.
    func parseMorph(_ raw: String) -> Morph {
        var s = raw.trimmed
        if s.hasPrefix("(") && s.hasSuffix(")") && s.count >= 2 { s = String(s.dropFirst().dropLast()) }
        s = String(s.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
        s = Self.braceJoin.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: ";")
        func cleanStem(_ t: String) -> String {
            t.filter { !$0.isASCIIDigit }.split(separator: "_").map(String.init).joined(separator: " + ")
        }
        guard let m = Self.morphShape.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let stemRange = Range(m.range(at: 1), in: s), let bodyRange = Range(m.range(at: 2), in: s) else {
            return Morph(stem: cleanStem(s))
        }
        var depth = 0
        var cur = String.UnicodeScalarView(), inner = String.UnicodeScalarView()
        var main: [String] = []
        func pushCur() {
            let t = String(cur).trimmed
            if !t.isEmpty { main.append(t) }
            cur = String.UnicodeScalarView()
        }
        for ch in s[bodyRange].unicodeScalars {
            if ch == "(" {
                depth += 1
                if depth == 1 { pushCur(); continue }
            }
            if ch == ")" {
                depth -= 1
                if depth == 0 { continue }
            }
            if depth > 0 { inner.append(ch) }
            else if ch == ";" { pushCur() }
            else { cur.append(ch) }
        }
        pushCur()
        let tags = index.tags
        func tokens(_ list: [String]) -> [String] {
            list.flatMap { t -> [String] in
                let last = t.split(separator: ":").map(String.init).last ?? ""
                let pieces = last.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
                return pieces.count > 1 && pieces.allSatisfy({ tags[$0] != nil }) ? pieces : [last]
            }
            .filter { !$0.isEmpty && $0 != "कृत्_प्रत्ययः" && $0 != "कृत्" }
        }
        // A verb's tags end with its dhātupāṭha form ("असँ"), which repeats the root.
        func known(_ list: [String]) -> [String] {
            list.contains { $0.endsWithScalars("ादिः") } ? list.filter { tags[$0] != nil } : list
        }
        let tagList = known(tokens(main))
        let innerText = String(inner)
        let deriv = innerText.isEmpty ? [] : innerText.split(separator: ";").map { String($0).trimmed }.filter { !$0.isEmpty }
        let root = deriv.first.map(cleanStem) ?? ""
        return Morph(
            stem: cleanStem(String(s[stemRange])),
            tags: tagList,
            root: root,
            rootTags: tokens(Array(deriv.dropFirst())).filter { tags[$0] != nil },
            isRoot: root.isEmpty && tagList.contains { Self.finiteTags.contains($0) })
    }
}

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
