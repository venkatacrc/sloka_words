import AppKit
import SwiftUI

private struct AnalysisLabels {
    let split, anvaya, words, graph, stem, root, from, sentence, sandhi, verseOrder, proseOrder, compound, legend, supplied, tap: String

    static func of(_ script: AnalysisScript) -> AnalysisLabels {
        script == .te
            ? AnalysisLabels(
                split: "పదచ్ఛేదం", anvaya: "అన్వయం", words: "పద పరిచయం", graph: "కారక చిత్రం",
                stem: "ప్రాతిపదిక", root: "ధాతువు", from: "మూలం", sentence: "వాక్యం", sandhi: "సంధి విడదీత",
                verseOrder: "శ్లోకంలోని క్రమంలో పదాలు", proseOrder: "గద్య క్రమం", compound: "సమాసం",
                legend: "సంబంధాలు", supplied: "కుండలీకరణంలోని పదాలు శ్లోకంలో లేవు, అర్థం కోసం చేర్చినవి.",
                tap: "పదం మీద నొక్కితే దాని అర్థం కనిపిస్తుంది.")
            : AnalysisLabels(
                split: "पदच्छेदः", anvaya: "अन्वयः", words: "पदपरिचयः", graph: "कारकसम्बन्धः",
                stem: "प्रातिपदिकम्", root: "धातुः", from: "मूलम्", sentence: "वाक्यम्", sandhi: "सन्धिविच्छेदः",
                verseOrder: "श्लोके पदानि", proseOrder: "गद्यक्रमः", compound: "समासः",
                legend: "सम्बन्धाः", supplied: "Words in brackets are not in the verse; they are understood.",
                tap: "Click a word to see its meaning.")
    }

    func title(_ tab: AnalysisTab) -> String {
        switch tab {
        case .split: split
        case .anvaya: anvaya
        case .words: words
        case .graph: graph
        }
    }
}

@MainActor
final class AnalysisSheetState: ObservableObject {
    @Published var models: [(stem: String, model: AnalysisModel)]?
    @Published var error: String?
    @Published var picked: AnalysisWord?
}

struct GitaAnalysisView: View {
    let verse: Verse
    let deckWords: [VerseWord]
    @ObservedObject var store: GitaAnalysisStore
    let onClose: () -> Void

    @AppStorage("analysisScript") private var scriptRaw = AnalysisScript.te.rawValue
    @AppStorage("analysisTab") private var tabRaw = AnalysisTab.graph.rawValue
    @StateObject private var state = AnalysisSheetState()

    private var script: AnalysisScript { AnalysisScript(rawValue: scriptRaw) ?? .te }
    private var tab: AnalysisTab { AnalysisTab(rawValue: tabRaw) ?? .graph }
    private var L: AnalysisLabels { .of(script) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 560, idealHeight: 780)
        .task(id: verse.id) { await load() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verse.label).font(.headline)
                    Text("పద విశ్లేషణ · Word analysis").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 16) {
                Picker("Script", selection: $scriptRaw) {
                    ForEach(AnalysisScript.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                Picker("View", selection: $tabRaw) {
                    ForEach(AnalysisTab.allCases) { Text(L.title($0)).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            .labelsHidden()
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if let error = state.error {
            Text(error)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let models = state.models {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(models.enumerated()), id: \.offset) { i, item in
                    VStack(alignment: .leading, spacing: 8) {
                        let notes = blockNotes(item.stem, part: i, of: models.count)
                        if !notes.isEmpty {
                            Text(notes).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        }
                        tabView(item.model)
                    }
                    if i < models.count - 1 { Divider() }
                }
            }
            .textSelection(.enabled)
        } else {
            ProgressView("Downloading the analysis…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    private func blockNotes(_ stem: String, part: Int, of count: Int) -> String {
        let covers = store.versesInFile(stem)
        var notes: [String] = []
        if count > 1 { notes.append("భాగం \(part + 1) / \(count) · Part \(part + 1) of \(count)") }
        if covers.count > 1, let first = covers.first, let last = covers.last {
            notes.append("శ్లోకాలు \(first)–\(last) కలిపి · Verses \(first)–\(last) together")
        }
        return notes.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private func tabView(_ model: AnalysisModel) -> some View {
        switch tab {
        case .split: splitView(model)
        case .anvaya: anvayaView(model)
        case .words: wordsView(model)
        case .graph: graphView(model)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let source = store.index?.source {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(source.credit)
                    if let url = URL(string: "https://github.com/\(source.repo)") { Link("Source", destination: url) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack {
                Text(savedLine).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.savedCount < store.allFiles.count {
                    Button {
                        Task { await store.downloadAll() }
                    } label: {
                        Label("Save the whole Gītā for offline", systemImage: "arrow.down.circle")
                    }
                    .disabled(store.saving != nil && store.saving!.failed == 0 && store.saving!.done < store.saving!.total)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var savedLine: String {
        let total = store.allFiles.count
        if let s = store.saving {
            if s.done + s.failed < s.total { return "Saving \(s.done) of \(s.total)…" + (s.failed > 0 ? " (\(s.failed) failed)" : "") }
            if s.failed > 0 { return "\(s.failed) files could not be downloaded; try again later." }
        }
        return store.savedCount >= total
            ? "✓ The whole Gītā is saved for offline use."
            : "\(store.savedCount) of \(total) analysis files saved on this Mac."
    }

    private func load() async {
        state.models = nil
        state.error = nil
        state.picked = nil
        do {
            var models: [(stem: String, model: AnalysisModel)] = []
            for stem in store.files(for: verse) {
                models.append((stem, try await store.model(stem)))
            }
            state.models = models
        } catch {
            state.error = "Could not download the analysis (\(error.localizedDescription)). It is downloaded the first time a verse is opened, so connect to the internet once, or save the whole Gītā while online."
        }
    }

    // MARK: - Helpers

    private func show(_ deva: String) -> String { Script.show(deva, script) }

    private static func norm(_ s: String) -> String {
        let dropped: Set<Unicode.Scalar> = ["-", "(", ")", "\u{200C}", "\u{200D}", "\u{093C}"]
        var out = String.UnicodeScalarView()
        for scalar in s.precomposedStringWithCanonicalMapping.unicodeScalars {
            if dropped.contains(scalar) || scalar.properties.isWhitespace { continue }
            if scalar == "ं" { out.append(contentsOf: "म्".unicodeScalars) } else { out.append(scalar) }
        }
        return String(out)
    }

    private var teluguMeanings: [String: String] {
        var map: [String: String] = [:]
        for entry in deckWords where !entry.deva.isEmpty && !entry.teMeaning.isEmpty {
            map[Self.norm(entry.deva)] = entry.teMeaning
        }
        return map
    }

    private func meaning(_ w: AnalysisWord, _ map: [String: String]) -> (te: String, en: String) {
        (map[Self.norm(w.text)] ?? "", w.en)
    }

    private func tagLabel(_ tag: String) -> String {
        guard let t = store.index?.tags[tag] else { return show(tag) }
        return script == .te ? t.te : t.sa
    }

    private func relLabel(_ info: RelationInfo?) -> String { info.map { show($0.sa) } ?? "" }

    private func relGloss(_ info: RelationInfo) -> String {
        [info.te, info.en].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    fileprivate static func kindColor(_ kind: String?) -> Color {
        switch kind {
        case "karaka": .orange
        case "samasa": .purple
        default: .secondary
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(Color.accentColor).padding(.top, 4)
    }

    // MARK: - Views

    private func splitView(_ model: AnalysisModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L.verseOrder)
            Text(model.verseOrder.map { show($0.text) }.joined(separator: "   "))
                .font(.system(size: 22))
                .lineSpacing(6)
            if !model.splits.isEmpty {
                sectionTitle(L.sandhi)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.splits.enumerated()), id: \.offset) { _, g in
                        g.words.enumerated().reduce(
                            Text("• ") + Text(show(g.joined)).fontWeight(.semibold) + Text("  =  ")
                        ) { line, item in
                            line + Text(item.offset > 0 ? "  +  " : "") + Text(show(item.element.text)).foregroundStyle(Color.accentColor)
                        }
                        .font(.system(size: 18))
                    }
                }
            }
        }
    }

    private func anvayaView(_ model: AnalysisModel) -> some View {
        let map = teluguMeanings
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L.proseOrder)
            Text(model.anvaya.map { show($0.text) }.joined(separator: "   "))
                .font(.system(size: 22))
                .lineSpacing(6)
            FlowLayout(spacing: 8) {
                ForEach(model.anvaya) { w in
                    let m = meaning(w, map)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show(w.text)).font(.system(size: 17, weight: .semibold))
                        if !m.te.isEmpty { Text(m.te).font(.system(size: 14)) }
                        if !m.en.isEmpty { Text(m.en).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: 260, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: w.supplied ? [4, 3] : [])))
                }
            }
            if model.anvaya.contains(where: \.supplied) {
                Text(L.supplied).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func wordsView(_ model: AnalysisModel) -> some View {
        let map = teluguMeanings
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(model.words) { w in
                let m = meaning(w, map)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(show(w.text))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(w.supplied ? .secondary : .primary)
                        Text([m.te, m.en].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                    morphChips(w.morph)
                    if let parts = w.compound {
                        parts.enumerated().reduce(Text("\(L.compound):  ")) { line, item in
                            line + Text(item.offset > 0 ? "  " : "")
                                + Text(show(item.element.word)).foregroundStyle(Color.accentColor)
                                + Text(item.element.rel.map { " (\(relLabel($0)))" } ?? "").foregroundStyle(.secondary)
                        }
                    }
                    if let rel = w.rel {
                        Text(relLabel(rel)).fontWeight(.semibold).foregroundStyle(Self.kindColor(rel.kind))
                            + Text(w.target.map { " → " + show($0.text) } ?? "").foregroundStyle(Color.accentColor)
                            + Text(rel.te.isEmpty ? "" : " · " + rel.te).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private func morphChips(_ morph: Morph) -> some View {
        FlowLayout(spacing: 5) {
            if !morph.stem.isEmpty {
                chip(Text("\(morph.isRoot ? L.root : L.stem): ") + Text(show(morph.stem)).bold(), filled: true)
            }
            ForEach(Array(morph.tags.enumerated()), id: \.offset) { _, t in
                chip(Text(tagLabel(t)), filled: false)
                    .help(store.index?.tags[t]?.te ?? "")
            }
            if !morph.root.isEmpty {
                chip(Text("\(L.from): ") + Text(show(morph.root)).bold()
                     + Text(morph.rootTags.isEmpty ? "" : " (\(morph.rootTags.map(tagLabel).joined(separator: ", ")))"),
                     filled: true)
            }
        }
    }

    private func chip(_ text: Text, filled: Bool) -> some View {
        text
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filled ? Color.secondary.opacity(0.12) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? .clear : Color.secondary.opacity(0.35)))
    }

    private func graphView(_ model: AnalysisModel) -> some View {
        let map = teluguMeanings
        var used: [String: RelationInfo] = [:]
        var usedOrder: [String] = []
        for w in model.words {
            if w.parent != nil, let rel = w.rel, used[rel.sa] == nil {
                used[rel.sa] = rel
                usedOrder.append(rel.sa)
            }
        }
        return VStack(alignment: .leading, spacing: 12) {
            pickedInfo(map)
            ForEach(Array(model.sentences.enumerated()), id: \.offset) { i, root in
                VStack(alignment: .leading, spacing: 4) {
                    if model.sentences.count > 1 { sectionTitle("\(L.sentence) \(i + 1)") }
                    ScrollView(.horizontal) {
                        KarakaTree(layout: TreeLayout(root: root, script: script, label: relLabel),
                                   picked: state.picked, onPick: { state.picked = $0 })
                            .padding(.bottom, 6)
                    }
                }
            }
            if !usedOrder.isEmpty {
                sectionTitle(L.legend)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(usedOrder, id: \.self) { key in
                        let r = used[key]!
                        Text("• ") + Text(relLabel(r)).fontWeight(.semibold).foregroundStyle(Self.kindColor(r.kind))
                            + Text("  " + relGloss(r))
                    }
                }
            }
        }
    }

    private func pickedInfo(_ map: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let w = state.picked {
                let m = meaning(w, map)
                Text(show(w.text)).bold() + Text("  " + [m.te, m.en].filter { !$0.isEmpty }.joined(separator: " · "))
                if let rel = w.rel, let parent = w.parent {
                    Text("\(relLabel(rel)) → \(show(parent.text))" + (rel.te.isEmpty ? "" : " · \(rel.te)"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(L.tap).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Kāraka tree

private struct TreeNode: Identifiable {
    let id: Int
    let word: AnalysisWord
    let depth: Int
    let label: String
    let rel: String
    let boxW: CGFloat
    let relW: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0
    var children: [Int] = []
}

/// Lays out one sentence as a tree: head word on top, each dependent below it.
private struct TreeLayout {
    static let nodeH: CGFloat = 32, gap: CGFloat = 12, bus: CGFloat = 14, stub: CGFloat = 30, pad: CGFloat = 12
    static let level = nodeH + bus + stub
    static let wordFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static let labelFont = NSFont.systemFont(ofSize: 11.5, weight: .medium)

    var nodes: [TreeNode] = []
    var width: CGFloat = 0
    var height: CGFloat = 0

    init(root: AnalysisWord, script: AnalysisScript, label: (RelationInfo?) -> String) {
        func measure(_ text: String, _ font: NSFont) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: font]).size().width
        }
        var widths: [Int: CGFloat] = [:]
        func walk(_ w: AnalysisWord, _ depth: Int) -> Int {
            let text = Script.show(w.text, script)
            let rel = w.parent != nil ? label(w.rel) : ""
            let id = nodes.count
            nodes.append(TreeNode(
                id: id, word: w, depth: depth, label: text, rel: rel,
                boxW: max(measure(text, Self.wordFont) + 20, 40),
                relW: rel.isEmpty ? 0 : measure(rel, Self.labelFont) + 10))
            let kids = w.children.map { walk($0, depth + 1) }
            nodes[id].children = kids
            let colW = max(nodes[id].boxW, nodes[id].relW) + Self.gap
            widths[id] = max(colW, kids.reduce(0) { $0 + widths[$1]! })
            return id
        }
        let top = walk(root, 0)
        func place(_ id: Int, _ left: CGFloat) {
            let kids = nodes[id].children
            if kids.isEmpty {
                nodes[id].x = left + widths[id]! / 2
            } else {
                var x = left + (widths[id]! - kids.reduce(0) { $0 + widths[$1]! }) / 2
                for k in kids { place(k, x); x += widths[k]! }
                nodes[id].x = (nodes[kids.first!].x + nodes[kids.last!].x) / 2
            }
            nodes[id].y = Self.pad + CGFloat(nodes[id].depth) * Self.level + Self.nodeH / 2
        }
        place(top, Self.pad)
        let depth = nodes.map(\.depth).max() ?? 0
        width = ceil(widths[top]! + Self.pad * 2)
        height = ceil(Self.pad * 2 + CGFloat(depth) * Self.level + Self.nodeH)
    }
}

private struct TreeEdges: Shape {
    let segments: [(CGPoint, CGPoint)]

    init(layout: TreeLayout) {
        var segments: [(CGPoint, CGPoint)] = []
        for n in layout.nodes where !n.children.isEmpty {
            let bottom = n.y + TreeLayout.nodeH / 2
            let busY = bottom + TreeLayout.bus
            segments.append((CGPoint(x: n.x, y: bottom), CGPoint(x: n.x, y: busY)))
            let xs = n.children.map { layout.nodes[$0].x }
            let lo = min(n.x, xs.min()!), hi = max(n.x, xs.max()!)
            if hi > lo { segments.append((CGPoint(x: lo, y: busY), CGPoint(x: hi, y: busY))) }
            for c in n.children {
                let child = layout.nodes[c]
                segments.append((CGPoint(x: child.x, y: busY), CGPoint(x: child.x, y: child.y - TreeLayout.nodeH / 2)))
            }
        }
        self.segments = segments
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (a, b) in segments {
            p.move(to: a)
            p.addLine(to: b)
        }
        return p
    }
}

private struct KarakaTree: View {
    let layout: TreeLayout
    let picked: AnalysisWord?
    let onPick: (AnalysisWord) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            TreeEdges(layout: layout).stroke(Color.secondary.opacity(0.55), lineWidth: 1.3)
            ForEach(layout.nodes) { n in
                if !n.rel.isEmpty {
                    Text(n.rel)
                        .font(Font(TreeLayout.labelFont))
                        .fontWeight(n.word.rel?.kind == "karaka" ? .bold : .medium)
                        .foregroundStyle(GitaAnalysisView.kindColor(n.word.rel?.kind))
                        .fixedSize()
                        .padding(.horizontal, 3)
                        .background(Color(nsColor: .textBackgroundColor))
                        .position(x: n.x, y: n.y - TreeLayout.nodeH / 2 - 9)
                        .help(n.word.rel.map { [$0.te, $0.en].filter { !$0.isEmpty }.joined(separator: " · ") } ?? "")
                }
                node(n)
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    private func node(_ n: TreeNode) -> some View {
        let isRoot = n.depth == 0
        let selected = picked === n.word
        return Button { onPick(n.word) } label: {
            Text(n.label)
                .font(Font(TreeLayout.wordFont))
                .foregroundStyle(n.word.supplied ? .secondary : .primary)
                .fixedSize()
                .frame(width: n.boxW, height: TreeLayout.nodeH)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isRoot ? Color.orange.opacity(0.16) : Color(nsColor: .textBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(
                            selected || isRoot ? Color.orange : Color.secondary,
                            style: StrokeStyle(lineWidth: selected ? 2 : isRoot ? 1.6 : 1.2, dash: n.word.supplied ? [4, 3] : [])))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .position(x: n.x, y: n.y)
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (i, frame) in result.frames.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            if size.width > maxWidth { size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) }
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowH), frames)
    }
}
