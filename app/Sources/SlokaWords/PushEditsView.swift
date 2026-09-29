import SwiftUI

struct PushEditsView: View {
    @ObservedObject var pusher: RepoPushStore
    let onPushed: (URL) -> Void

    private let fieldNames = ["te": "తెలుగు", "deva": "हिन्दी", "iast": "IAST"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Push verse edits to the repos")
                .font(.title2.weight(.semibold))
            content
        }
        .padding(24)
        .frame(width: 760)
        .frame(minHeight: 260)
    }

    @ViewBuilder
    private var content: some View {
        switch pusher.phase {
        case .checking:
            progress("Checking what will change…")
        case .pushing:
            progress("Committing and pushing…")
        case .review(let plan):
            review(plan)
        case .done(let log):
            Label("Pushed. The deck has been reloaded with your edits.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            logView(log)
            HStack {
                Spacer()
                Button("Close") { pusher.isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
        case .failed(let error):
            Label("The push did not complete.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            logView(error.components(separatedBy: "\n"))
            HStack {
                Button("Change folders…") { if pusher.chooseFolders() { pusher.check() } }
                Spacer()
                Button("Close") { pusher.isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Try again") { pusher.check() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func review(_ plan: PushPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            repoLine("bhakti", plan.bhakti,
                     plan.bhakti.files.isEmpty ? "no page changes" : "\(plan.bhakti.files.count) page(s)")
            repoLine("sloka_words", plan.sloka_words, "verse_edits.json and the rebuilt deck")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.verses) { verse in
                        verseDiff(verse)
                    }
                    if !plan.unchanged.isEmpty {
                        Text("\(plan.unchanged.count) edited verse(s) already match the bhakti pages; they are only recorded in verse_edits.json.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)

            ForEach(warnings(plan), id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Commit message").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                TextField("Commit message", text: $pusher.message)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Change folders…") { if pusher.chooseFolders() { pusher.check() } }
                Spacer()
                Button("Cancel", role: .cancel) { pusher.isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Commit and Push") { pusher.push(then: onPushed) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan.verses.isEmpty && plan.unchanged.isEmpty)
            }
        }
    }

    private func warnings(_ plan: PushPlan) -> [String] {
        var out: [String] = []
        let dirty = plan.bhakti.other_changes + plan.sloka_words.other_changes
        if !dirty.isEmpty {
            out.append("These files already have uncommitted changes, which will be committed too: \(dirty.joined(separator: ", "))")
        }
        if !plan.unknown.isEmpty {
            out.append("Skipped \(plan.unknown.count) edit(s) for verses no longer in the pages: \(plan.unknown.joined(separator: ", "))")
        }
        return out
    }

    private func repoLine(_ name: String, _ info: PushPlan.RepoInfo, _ what: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(name).font(.headline)
            Text("\(what) → \(info.branch) on \(info.remote.isEmpty ? info.path : info.remote)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func verseDiff(_ verse: PushPlan.PlanVerse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verse.label).font(.headline)
                Text(verse.file).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(["te", "deva", "iast"].filter { verse.changes[$0] != nil }, id: \.self) { key in
                let change = verse.changes[key]!
                VStack(alignment: .leading, spacing: 2) {
                    Text(fieldNames[key] ?? key).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    ForEach(Array(change.before.enumerated()), id: \.offset) { _, line in
                        Text("− " + line).foregroundStyle(.red).textSelection(.enabled)
                    }
                    ForEach(Array(change.after.enumerated()), id: \.offset) { _, line in
                        Text("+ " + line).foregroundStyle(.green).textSelection(.enabled)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func logView(_ lines: [String]) -> some View {
        ScrollView {
            Text(lines.joined(separator: "\n"))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
