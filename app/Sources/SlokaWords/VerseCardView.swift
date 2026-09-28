import SwiftUI

struct VerseCardView: View {
    let verse: Verse
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
                if flipped {
                    fullVerse
                    Divider().padding(.horizontal, 40)
                    meanings
                } else {
                    firstLine
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
            VerseLines(label: "తెలుగు", lines: Array(verse.te.prefix(1)), size: 32, weight: .semibold)
            VerseLines(label: "हिन्दी", lines: Array(verse.deva.prefix(1)), size: 26)
            VerseLines(label: "IAST", lines: Array(verse.iast.prefix(1)), size: 17, italic: true)
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
            VerseLines(label: "తెలుగు", lines: verse.te, size: 26, weight: .semibold)
            VerseLines(label: "हिन्दी", lines: verse.deva, size: 22)
            VerseLines(label: "IAST", lines: verse.iast, size: 15, italic: true)
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
            if !verse.words.isEmpty {
                block("Word by word") {
                    Text(verse.words).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .textSelection(.enabled)
    }

    private func block<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            content()
        }
    }
}

private struct VerseLines: View {
    let label: String
    let lines: [String]
    let size: CGFloat
    var weight: Font.Weight = .regular
    var italic = false

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
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
