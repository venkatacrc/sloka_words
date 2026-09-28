import SwiftUI

struct CardView: View {
    let word: Word
    let flipped: Bool
    let isKnown: Bool
    let isReview: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    status
                    scripts
                    if flipped {
                        Divider().padding(.horizontal, 40)
                        meanings
                    } else {
                        Text("Click the card or press Space to see the meanings")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
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

    private var status: some View {
        HStack {
            if isKnown { CardBadge(text: "Known", color: .green) }
            if isReview { CardBadge(text: "Review", color: .orange) }
            Spacer()
        }
        .frame(height: 20)
    }

    private var scripts: some View {
        VStack(spacing: 14) {
            ScriptLine(label: "తెలుగు", text: word.te, size: flipped ? 38 : 50, weight: .semibold)
            ScriptLine(label: "हिन्दी", text: word.deva, size: flipped ? 30 : 38, weight: .regular)
            ScriptLine(label: "IAST", text: word.iast, size: flipped ? 18 : 22, weight: .regular, italic: true)
        }
    }

    private var meanings: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeaningBlock(title: "తెలుగు భావం") {
                if word.teMeaning.isEmpty {
                    Text("Telugu meaning not added yet")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    Text(word.teMeaning).font(.system(size: 22))
                }
            }
            MeaningBlock(title: "English meaning") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(word.en, id: \.self) { meaning in
                        Text(word.en.count > 1 ? "• \(meaning)" : meaning)
                            .font(.system(size: 17))
                    }
                }
            }
            MeaningBlock(title: "Found in") {
                Text(refSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .textSelection(.enabled)
    }

    private var refSummary: String {
        let labels = word.refs.map(\.label)
        let shown = labels.prefix(6).joined(separator: ", ")
        return labels.count > 6 ? "\(shown) and \(labels.count - 6) more" : shown
    }
}

private struct ScriptLine: View {
    let label: String
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    var italic = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: size, weight: weight))
                .italic(italic)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
    }
}

private struct MeaningBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            content
        }
    }
}
