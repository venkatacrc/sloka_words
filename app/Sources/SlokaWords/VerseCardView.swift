import SwiftUI

struct VerseCardView: View {
    let verse: Verse
    let words: [VerseWord]
    let onStudy: () -> Void
    let onReveal: () -> Void
    let openWordID: String?
    let setOpenWordID: (String?) -> Void
    let flipped: Bool
    let isKnown: Bool
    let isReview: Bool

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
            VerseLines(label: "తెలుగు", speaker: verse.speaker?.te, lines: Array(verse.te.prefix(1)), size: 32, weight: .semibold)
            VerseLines(label: "हिन्दी", speaker: verse.speaker?.deva, lines: Array(verse.deva.prefix(1)), size: 26)
            VerseLines(label: "IAST", speaker: verse.speaker?.iast, lines: Array(verse.iast.prefix(1)), size: 17, italic: true)
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
            VerseLines(label: "తెలుగు", speaker: verse.speaker?.te, lines: verse.te, size: 26, weight: .semibold)
            VerseLines(label: "हिन्दी", speaker: verse.speaker?.deva, lines: verse.deva, size: 22)
            VerseLines(label: "IAST", speaker: verse.speaker?.iast, lines: verse.iast, size: 15, italic: true)
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
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                setOpenWordID(open ? nil : entry.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if !entry.te.isEmpty {
                        Text(entry.te).font(.system(size: 20, weight: .semibold))
                    }
                    Text(entry.iast).italic().foregroundStyle(.secondary)
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
                    if !entry.deva.isEmpty {
                        Text(entry.deva).foregroundStyle(.secondary)
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
