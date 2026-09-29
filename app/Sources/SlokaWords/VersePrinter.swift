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
}

/// Lays the selected verses out as text and sends them to the print system, which paginates
/// them and either shows the Print dialog or saves a PDF.
@MainActor
enum VersePrinter {
    static func run(verses: [Verse], heading: (Verse) -> String, title: String,
                    options: PrintOptions, saveTo url: URL?) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 48
        info.bottomMargin = 48
        info.leftMargin = 54
        info.rightMargin = 54
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
        view.textStorage?.setAttributedString(document(verses: verses, heading: heading, title: title, options: options))
        if let layout = view.layoutManager, let container = view.textContainer {
            layout.ensureLayout(for: container)
            view.setFrameSize(NSSize(width: width, height: ceil(layout.usedRect(for: container).height)))
        }

        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = title
        op.showsPrintPanel = url == nil
        op.showsProgressPanel = true
        op.run()
    }

    static func document(verses: [Verse], heading: (Verse) -> String, title: String,
                         options: PrintOptions) -> NSAttributedString {
        let doc = NSMutableAttributedString()
        let ink = NSColor.black
        let accent = NSColor(red: 0.10, green: 0.32, blue: 0.46, alpha: 1)
        let muted = NSColor(white: 0.35, alpha: 1)

        func add(_ text: String, _ font: NSFont, _ color: NSColor = ink,
                 before: CGFloat = 0, after: CGFloat = 2, center: Bool = true) {
            let style = NSMutableParagraphStyle()
            style.alignment = center ? .center : .left
            style.paragraphSpacingBefore = before
            style.paragraphSpacing = after
            style.lineHeightMultiple = 1.1
            doc.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: style,
            ]))
        }
        func lines(_ lines: [String], _ font: NSFont, _ color: NSColor = ink) {
            for (i, line) in lines.enumerated() {
                add(line, font, color, before: i == 0 ? 6 : 0)
            }
        }
        func meaning(_ head: String, _ text: String, size: CGFloat = 11) {
            guard !text.isEmpty else { return }
            add(head, .systemFont(ofSize: 8.5, weight: .bold), accent, before: 6, after: 1, center: false)
            add(text, .systemFont(ofSize: size), ink, after: 2, center: false)
        }
        let italic = NSFontManager.shared.convert(.systemFont(ofSize: 11), toHaveTrait: .italicFontMask)
        let telugu = NSFont(name: "KohinoorTelugu-Medium", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)

        add(title, .systemFont(ofSize: 20, weight: .bold), ink, after: 4)
        add("\(verses.count) verse\(verses.count == 1 ? "" : "s")", .systemFont(ofSize: 10), muted, after: 10)

        var lastHeading = ""
        for verse in verses {
            let h = heading(verse)
            if h != lastHeading {
                add(h, .systemFont(ofSize: 14, weight: .bold), accent, before: 18, after: 4, center: false)
                lastHeading = h
            }
            add(verse.label, .systemFont(ofSize: 10, weight: .semibold), muted, before: 14, after: 0, center: false)
            if options.te { lines(verse.te, telugu) }
            if options.deva { lines(verse.deva, .systemFont(ofSize: 14)) }
            if options.iast { lines(verse.iast, italic, muted) }
            if options.teMeaning { meaning("తెలుగు భావం", verse.teMeaning, size: 12) }
            if options.enMeaning { meaning("MEANING", verse.enMeaning) }
            if options.words { meaning("WORD BY WORD", verse.words, size: 10) }
        }
        return doc
    }
}

private final class PrintTextView: NSTextView {
    var jobTitle = "Sloka Words"
    override var printJobTitle: String { jobTitle }
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

    private var picked: [Verse] { reviewOnly ? verses.filter { reviewIDs.contains($0.id) } : verses }
    private var options: PrintOptions {
        PrintOptions(te: te, deva: deva, iast: iast, teMeaning: teMeaning, enMeaning: enMeaning, words: words)
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
