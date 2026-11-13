import SwiftUI

struct VerseCardView: View {
    let verse: Verse
    let words: [VerseWord]
    let onStudy: () -> Void
    let onReveal: () -> Void
    /// Opens Samsaadhanii's word analysis; nil when the verse has none.
    let onAnalysis: (() -> Void)?
    let openWordID: String?
    let setOpenWordID: (String?) -> Void
    let flipped: Bool
    let isKnown: Bool
    let isReview: Bool
    @AppStorage(MainScript.storageKey) private var mainRaw = MainScript.te.rawValue

    private var mainScript: MainScript { MainScript(rawValue: mainRaw) ?? .te }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    Text(verse.label).font(.headline).foregroundStyle(.secondary)
                    if verse.edited { CardBadge(text: "Edited", color: .purple) }
                    if isKnown { CardBadge(text: "Known", color: .green) }
                    if isReview { CardBadge(text: "Review", color: .orange) }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onReveal)
                if flipped {
                    fullVerse
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onReveal)
                    Divider().padding(.horizontal, 40)
                    meanings
                } else {
                    firstLine
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onReveal)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(flipped ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }

    private var firstLine: some View {
        VStack(spacing: 16) {
            scripts(main: 34, other: 20) { Array($0.prefix(1)) }
            Text(verse.te.count > 1
                 ? "Recite the rest of the verse, then click the card or press Space to check"
                 : "Click the card or press Space to see the meaning")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 20)
        }
    }

    private var fullVerse: some View {
        VStack(spacing: 16) {
            scripts(main: 29, other: 18) { $0 }
        }
    }

    private func scripts(main: CGFloat, other: CGFloat, lines: @escaping ([String]) -> [String]) -> some View {
        ForEach(Array(mainScript.order.enumerated()), id: \.element) { i, script in
            VerseLines(label: script.cardLabel,
                       speaker: verse.speaker.map { script.text($0.te, $0.deva, $0.iast) },
                       lines: lines(script == .te ? verse.te : script == .deva ? verse.deva : verse.iast),
                       size: (i == 0 ? main : other) * script.scale,
                       weight: i == 0 ? .semibold : .regular,
                       italic: script == .iast,
                       secondary: i > 0)
        }
    }

    private var meanings: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !verse.teMeaning.isEmpty {
                block("తెలుగు భావం") { Text(verse.teMeaning).font(.system(size: 19)) }
            }
            if !verse.enMeaning.isEmpty {
                block("English meaning") { Text(verse.enMeaning).font(.system(size: 16)) }
            }
            if let onAnalysis {
                Button(action: onAnalysis) {
                    Label("పద విశ్లేషణ · Kāraka graph (A)", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            if !words.isEmpty {
                wordList
            } else if !verse.words.isEmpty {
                block("Word by word") {
                    Text(verse.words).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    private var wordList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Words")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if words.contains(where: { $0.cardID != nil }) {
                    Button("Study these words", action: onStudy)
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                }
            }
            Text("Click a word to see its meaning.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(words) { entry in
                wordRow(entry)
            }
        }
    }

    private func wordRow(_ entry: VerseWord) -> some View {
        let open = openWordID == entry.id
        // The main script and one other in the row; the third shows when the row opens.
        let main = mainScript
        let second: MainScript = main == .iast ? .te : .iast
        let rest = MainScript.allCases.first { $0 != main && $0 != second }!
        let text = { (s: MainScript) in s.text(entry.te, entry.deva, entry.iast) }
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                setOpenWordID(open ? nil : entry.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if !text(main).isEmpty {
                        Text(text(main)).font(.system(size: 21 * main.scale, weight: .semibold)).italic(main == .iast)
                    }
                    if !text(second).isEmpty {
                        Text(text(second)).italic(second == .iast).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 4) {
                    if !text(rest).isEmpty {
                        Text(text(rest)).foregroundStyle(.secondary)
                    }
                    if !entry.teMeaning.isEmpty {
                        Text(entry.teMeaning).font(.system(size: 18))
                    } else if entry.cardID != nil {
                        Text("Telugu meaning not added yet").italic().foregroundStyle(.secondary)
                    }
                    Text(entry.en.joined(separator: "\n"))
                        .font(.body)
                }
                .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(open ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func block<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            content()
        }
        .textSelection(.enabled)
    }
}

private struct VerseLines: View {
    let label: String
    var speaker: String?
    let lines: [String]
    let size: CGFloat
    var weight: Font.Weight = .regular
    var italic = false
    var secondary = false

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            if let speaker {
                Text(speaker)
                    .font(.system(size: size * 0.7, weight: .medium))
                    .italic(italic)
                    .foregroundStyle(Color.accentColor)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: size, weight: weight))
                    .italic(italic)
                    .foregroundStyle(secondary ? .secondary : .primary)
                    .multilineTextAlignment(.center)
            }
        }
        .textSelection(.enabled)
    }
}

struct CardBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
