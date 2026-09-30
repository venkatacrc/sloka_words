import SwiftUI

struct GrammarCardView: View {
    let card: GrammarCard
    let flipped: Bool
    let isKnown: Bool
    let isReview: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    Text(card.label).font(.headline).foregroundStyle(.secondary)
                    if isKnown { CardBadge(text: "Known", color: .green) }
                    if isReview { CardBadge(text: "Review", color: .orange) }
                    Spacer()
                    if let url = lessonURL {
                        Link(destination: url) { Label("Lesson", systemImage: "book") }
                            .font(.callout)
                            .help("Read this lesson on the bhakti site")
                    }
                }
                if !card.context.isEmpty {
                    Text(card.context)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                prompt
                if flipped {
                    Divider().padding(.horizontal, 40)
                    answer
                } else {
                    Text("Recall the answer, then click the card or press Space to check")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
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

    private var lessonURL: URL? {
        card.link.flatMap { URL(string: "https://venkatacrc.github.io/bhakti/\($0)") }
    }

    private var prompt: some View {
        VStack(spacing: 6) {
            if !card.prompt.head.isEmpty {
                Text(card.prompt.head)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            Text(card.prompt.text)
                .font(.system(size: card.prompt.text.count > 40 ? 24 : 32, weight: .semibold))
                .multilineTextAlignment(.center)
            if let te = card.prompt.te {
                Text(te)
                    .font(.system(size: card.prompt.text.count > 40 ? 20 : 24))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .textSelection(.enabled)
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(card.answer.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: 3) {
                    if !cell.head.isEmpty {
                        Text(cell.head)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(cell.text).font(.system(size: 20))
                    if let te = cell.te, te != cell.text {
                        Text(te).font(.system(size: 17)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .textSelection(.enabled)
    }
}
