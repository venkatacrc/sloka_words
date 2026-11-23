import AppKit
import SwiftUI

@MainActor
final class PrintRequest: ObservableObject {
    @Published var isPresented = false
}

struct PrintOptions {
    var te = true
    var deva = true
    var iast = true
    var teMeaning = true
    var enMeaning = true
    var words = false
    /// Print each word separately so the Devanagari top line breaks between words.
    var split = false
}

/// The traditional opening and closing lines of each Gita chapter.
enum GitaColophon {
    private static let ordinals = ["प्रथम", "द्वितीय", "तृतीय", "चतुर्थ", "पञ्चम", "षष्ठ", "सप्तम", "अष्टम", "नवम",
                                   "दशम", "एकादश", "द्वादश", "त्रयोदश", "चतुर्दश", "पञ्चदश", "षोडश", "सप्तदश", "अष्टादश"]
    private static let yogas = ["अर्जुनविषादयोगो", "साङ्ख्ययोगो", "कर्मयोगो", "ज्ञानकर्मसंन्यासयोगो", "कर्मसंन्यासयोगो",
                                "ध्यानयोगो", "ज्ञानविज्ञानयोगो", "अक्षरब्रह्मयोगो", "राजविद्याराजगुह्ययोगो", "विभूतियोगो",
                                "विश्वरूपदर्शनयोगो", "भक्तियोगो", "क्षेत्रक्षेत्रज्ञविभागयोगो", "गुणत्रयविभागयोगो",
                                "पुरुषोत्तमयोगो", "दैवासुरसम्पद्विभागयोगो", "श्रद्धात्रयविभागयोगो", "मोक्षसंन्यासयोगो"]

    /// The chapter number for verses of Gita chapters 1–18; nil for the Dhyānam and other texts.
    static func chapter(of verse: Verse) -> Int? {
        guard verse.src == "gita", let n = Int(verse.group), (1...18).contains(n) else { return nil }
        return n
    }

    static func opening(_ chapter: Int) -> String { "अथ \(ordinals[chapter - 1])ोऽध्यायः" }

    static func closing(_ chapter: Int) -> String {
        "इति श्रीमद्भगवद्गीतासूपनिषत्सु ब्रह्मविद्यायां योगशास्त्रे श्रीकृष्णार्जुनसंवादे "
            + "\(yogas[chapter - 1]) नाम \(ordinals[chapter - 1])ोऽध्यायः ॥"
    }

    /// Devanagari and Telugu letters sit at the same offsets in their Unicode blocks.
    static func telugu(_ deva: String) -> String {
        String(String.UnicodeScalarView(deva.unicodeScalars.map { s in
            (0x0901...0x094D).contains(s.value) ? Unicode.Scalar(s.value + 0x300)! : s
        }))
    }
}

/// Lays the selected verses out as text and sends them to the print system, which paginates
/// them and either shows the Print dialog or saves a PDF.
@MainActor
enum VersePrinter {
    static func run(verses: [Verse], heading: (Verse) -> String, title: String,
                    options: PrintOptions, saveTo url: URL?) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595.28, height: 841.89)
        info.orientation = .portrait
        info.topMargin = 34
        info.bottomMargin = 38
        info.leftMargin = 40
        info.rightMargin = 40
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.isHorizontallyCentered = false
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter.rawValue] = true
        if let url {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = url
        }

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = PrintTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.jobTitle = title
        view.isEditable = false
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(document(verses: verses, heading: heading, options: options, width: width))
        if let layout = view.layoutManager, let container = view.textContainer, let storage = view.textStorage {
            layout.ensureLayout(for: container)
            view.setFrameSize(NSSize(width: width, height: ceil(layout.usedRect(for: container).height)))
            storage.enumerateAttribute(verseBlock, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard value != nil else { return }
                let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                view.blocks.append(rect.minY...rect.maxY)
            }
        }

        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = title
        op.showsPrintPanel = url == nil
        op.showsProgressPanel = true
        op.run()
    }

    /// Each verse sits between two empty lines left for handwritten corrections. The speaker
    /// ("arjuna uvāca") is printed only where it changes, and the verse number goes in the
    /// left margin of the first line instead of a line of its own.
    static func document(verses: [Verse], heading: (Verse) -> String, options: PrintOptions,
                         width: CGFloat) -> NSAttributedString {
        let doc = NSMutableAttributedString()
        let ink = NSColor.black
        let accent = NSColor(red: 0.10, green: 0.32, blue: 0.46, alpha: 1)
        let muted = NSColor(white: 0.35, alpha: 1)

        let telugu = NSFont(name: "KohinoorTelugu-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        let deva = NSFont(name: "KohinoorDevanagari-Regular", size: 13) ?? .systemFont(ofSize: 13)
        let iast = NSFontManager.shared.convert(.systemFont(ofSize: 10), toHaveTrait: .italicFontMask)
        let teSmall = NSFont(name: "KohinoorTelugu-Regular", size: 9.5) ?? .systemFont(ofSize: 9.5)
        let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .medium)
        let blankHeight: CGFloat = 17
        var lastWasBlank = false

        func style(center: Bool = true, before: CGFloat = 0, after: CGFloat = 0) -> NSMutableParagraphStyle {
            let s = NSMutableParagraphStyle()
            s.alignment = center ? .center : .left
            s.paragraphSpacingBefore = before
            s.paragraphSpacing = after
            s.lineHeightMultiple = 1.02
            return s
        }
        func append(_ text: NSAttributedString) {
            doc.append(text)
            lastWasBlank = false
        }
        func add(_ text: String, _ font: NSFont, _ color: NSColor = ink,
                 before: CGFloat = 0, after: CGFloat = 0, center: Bool = true) {
            append(NSAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: style(center: center, before: before, after: after),
            ]))
        }
        func blank() {
            guard !lastWasBlank, doc.length > 0 else { return }
            let s = style()
            s.minimumLineHeight = blankHeight
            s.maximumLineHeight = blankHeight
            doc.append(NSAttributedString(string: "\n", attributes: [.font: labelFont, .paragraphStyle: s]))
            lastWasBlank = true
        }
        /// A verse line, with `label` at the left margin and the text centred on the page.
        func labelled(_ label: String, _ line: String, _ font: NSFont, _ color: NSColor) {
            let s = style(center: false)
            s.tabStops = [NSTextTab(textAlignment: .center, location: width / 2)]
            let text = NSMutableAttributedString(string: label, attributes: [
                .font: labelFont, .foregroundColor: muted, .paragraphStyle: s,
            ])
            text.append(NSAttributedString(string: "\t" + line + "\n", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: s,
            ]))
            append(text)
        }
        func meaning(_ head: String, _ text: String, _ font: NSFont) {
            guard !text.isEmpty else { return }
            let s = style(center: false, after: 2)
            s.lineHeightMultiple = 1.08
            let para = NSMutableAttributedString(string: head + "  ", attributes: [
                .font: NSFont.systemFont(ofSize: 7, weight: .bold), .foregroundColor: accent, .paragraphStyle: s,
            ])
            para.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: ink, .paragraphStyle: s,
            ]))
            append(para)
        }
        /// The chapter's opening or closing line, in Telugu and/or Devanagari to match the verses.
        func colophon(_ text: String, size: CGFloat) {
            if options.te {
                add(GitaColophon.telugu(text), NSFontManager.shared.convert(telugu, toSize: size), accent, after: 2)
            }
            if options.deva || !options.te {
                add(text, NSFontManager.shared.convert(deva, toSize: size), accent, after: 2)
            }
        }

        /// In word-separated lines the verse's own spaces print three wide; breaks added by
        /// tools/verse_split.py (thin spaces in the deck) print as one plain space.
        func pick(_ plain: [String], _ split: [String]?) -> [String] {
            guard options.split, let split else { return plain }
            return split.map {
                $0.replacingOccurrences(of: " ", with: "   ").replacingOccurrences(of: "\u{2009}", with: " ")
            }
        }
        let scripts: [(on: Bool, lines: (Verse) -> [String], speaker: (Speaker) -> String, font: NSFont, color: NSColor)] = [
            (options.te, { pick($0.te, $0.split?.te) }, \.te, telugu, ink),
            (options.deva, { pick($0.deva, $0.split?.deva) }, \.deva, deva, ink),
            (options.iast, { pick($0.iast, $0.split?.iast) }, \.iast, iast, muted),
        ]

        var lastHeading: String?
        var lastSpeaker: String?
        var chapter: Int?
        var blockID = 0
        func closeChapter() {
            guard let chapter else { return }
            blank()
            colophon(GitaColophon.closing(chapter), size: 10)
        }
        for verse in verses {
            let h = heading(verse)
            if h != lastHeading { closeChapter() }
            let blockStart = doc.length
            if h != lastHeading {
                add(h, .systemFont(ofSize: 13, weight: .bold), accent, before: lastHeading == nil ? 0 : 14, after: 3, center: false)
                lastWasBlank = false
                lastHeading = h
                lastSpeaker = nil
                chapter = GitaColophon.chapter(of: verse)
                if let chapter { colophon(GitaColophon.opening(chapter), size: 12) }
            }
            let speakerChanged = verse.speaker?.iast != lastSpeaker
            lastSpeaker = verse.speaker?.iast
            let label = verse.label.hasPrefix("Gita ") ? String(verse.label.dropFirst(5)) : verse.label
            var labelled1 = false
            blank()
            for script in scripts where script.on {
                if speakerChanged, let speaker = verse.speaker {
                    add(script.speaker(speaker), NSFontManager.shared.convert(script.font, toSize: script.font.pointSize * 0.8), accent)
                }
                for line in script.lines(verse) {
                    if labelled1 {
                        add(line, script.font, script.color)
                    } else {
                        labelled(label, line, script.font, script.color)
                        labelled1 = true
                    }
                }
                blank()
            }
            if options.teMeaning { meaning("తెలుగు భావం", verse.teMeaning, teSmall) }
            if options.enMeaning { meaning("MEANING", verse.enMeaning, .systemFont(ofSize: 8.5)) }
            if options.words { meaning("WORD BY WORD", verse.words, .systemFont(ofSize: 8)) }
            blockID += 1
            doc.addAttribute(verseBlock, value: blockID, range: NSRange(location: blockStart, length: doc.length - blockStart))
        }
        closeChapter()
        return doc
    }

    /// Marks the text of one verse (with its chapter heading, if it starts a chapter) so a page
    /// break doesn't fall inside it.
    static let verseBlock = NSAttributedString.Key("SlokaWordsVerseBlock")
}

private final class PrintTextView: NSTextView {
    var jobTitle = "Sloka Words"
    /// The vertical extent of each verse in view coordinates.
    var blocks: [ClosedRange<CGFloat>] = []
    override var printJobTitle: String { jobTitle }

    /// A verse with meanings can take a third of a page; let the page end that much early
    /// rather than split it.
    override var heightAdjustLimit: CGFloat { 0.4 }

    override func adjustPageHeightNew(_ newBottom: UnsafeMutablePointer<CGFloat>, top oldTop: CGFloat,
                                      bottom oldBottom: CGFloat, limit bottomLimit: CGFloat) {
        super.adjustPageHeightNew(newBottom, top: oldTop, bottom: oldBottom, limit: bottomLimit)
        let bottom = newBottom.pointee
        if let block = blocks.first(where: { $0.lowerBound < bottom && $0.upperBound > bottom }),
           block.lowerBound > oldTop, block.lowerBound >= bottomLimit {
            newBottom.pointee = floor(block.lowerBound)
        }
    }
    /// Only the page number in the footer; the default header repeats the title and date.
    override var pageHeader: NSAttributedString { NSAttributedString() }
}

struct PrintVersesView: View {
    /// The verses in the sidebar selection, in deck order, with the app's verse edits applied.
    let verses: [Verse]
    let reviewIDs: Set<String>
    let heading: (Verse) -> String
    let title: String
    let onClose: () -> Void

    @AppStorage("printTe") private var te = true
    @AppStorage("printDeva") private var deva = true
    @AppStorage("printIast") private var iast = true
    @AppStorage("printTeMeaning") private var teMeaning = true
    @AppStorage("printEnMeaning") private var enMeaning = true
    @AppStorage("printWords") private var words = false
    @AppStorage("printReviewOnly") private var reviewOnly = false
    @AppStorage("printSplit") private var split = false

    private var picked: [Verse] { reviewOnly ? verses.filter { reviewIDs.contains($0.id) } : verses }
    private var options: PrintOptions {
        PrintOptions(te: te, deva: deva, iast: iast, teMeaning: teMeaning, enMeaning: enMeaning, words: words,
                     split: split)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Print verses").font(.title2.weight(.semibold))
            Text("Prints the verses in the chapters and sections ticked in the sidebar.")
                .font(.callout).foregroundStyle(.secondary)

            GroupBox("Verses") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Only verses marked for review", isOn: $reviewOnly)
                    Text("\(picked.count) verse\(picked.count == 1 ? "" : "s") will be printed")
                        .font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Include") {
                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("తెలుగు script", isOn: $te)
                        Toggle("हिन्दी (Devanagari)", isOn: $deva)
                        Toggle("IAST", isOn: $iast)
                        Toggle("Word-separated (శ్లోక విభాగం)", isOn: $split)
                            .help("Each word printed separately so the top line breaks between words: "
                                  + "विष्णुर्   वषट्कारो. The sound stays as chanted.")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("తెలుగు భావం (Telugu meaning)", isOn: $teMeaning)
                        Toggle("English meaning", isOn: $enMeaning)
                        Toggle("Word-by-word meanings", isOn: $words)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Save as PDF…") { savePDF() }
                Button("Print…") { print() }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(picked.isEmpty || !(te || deva || iast))
        }
        .padding(24)
        .frame(width: 560)
    }

    private func print() {
        let (verses, options) = (picked, options)
        onClose()
        DispatchQueue.main.async {
            VersePrinter.run(verses: verses, heading: heading, title: title, options: options, saveTo: nil)
        }
    }

    private func savePDF() {
        let panel = NSSavePanel()
        panel.title = "Save verses as PDF"
        panel.nameFieldStringValue = "\(title).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let (verses, options) = (picked, options)
        onClose()
        DispatchQueue.main.async {
            VersePrinter.run(verses: verses, heading: heading, title: title, options: options, saveTo: url)
        }
    }
}
