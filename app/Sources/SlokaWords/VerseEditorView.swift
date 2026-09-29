import SwiftUI

@MainActor
final class VerseDraft: ObservableObject {
    @Published var te = ""
    @Published var deva = ""
    @Published var iast = ""

    func load(_ verse: Verse) {
        te = verse.te.joined(separator: "\n")
        deva = verse.deva.joined(separator: "\n")
        iast = verse.iast.joined(separator: "\n")
    }

    var edit: VerseEdit { VerseEdit(te: te, deva: deva, iast: iast) }
}

struct VerseEditorView: View {
    /// The verse as it is in the deck, before any edit saved in the app.
    let original: Verse
    let hasLocalEdit: Bool
    @ObservedObject var draft: VerseDraft
    let onSave: (VerseEdit) -> Void
    let onRevert: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(original.label)")
                .font(.title2.weight(.semibold))
            Text("Rewrite the lines the way the verse is chanted, one line per row. The edit is saved in the app; use File → Push Verse Edits to Repos… to write it into the bhakti pages and the deck.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            field("తెలుగు", text: $draft.te, size: 20)
            field("हिन्दी (Devanagari)", text: $draft.deva, size: 18)
            field("IAST", text: $draft.iast, size: 14)

            HStack {
                Button("Reset to deck text") { draft.load(original) }
                if hasLocalEdit {
                    Button("Remove my edit", role: .destructive) { onRevert() }
                }
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft.edit) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.te.lines.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 720)
    }

    private func field(_ label: String, text: Binding<String>, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
            TextEditor(text: text)
                .font(.system(size: size))
                .frame(height: 86)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))
        }
    }
}
