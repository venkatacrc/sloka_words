import SwiftUI

enum PracticeMode: String, CaseIterable, Identifiable {
    case all, notKnown, review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All cards"
        case .notKnown: "Not yet known"
        case .review: "Review only"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var verseEdits: VerseEditStore

    /// Newline-separated `src|group` keys; `*` means every group in the deck.
    @AppStorage("selectedGroups") private var selectedRaw = "*"
    @AppStorage("excludedLangs") private var excludedRaw = ""
    @AppStorage("shuffle") private var shuffle = false
    @AppStorage("practiceMode") private var modeRaw = PracticeMode.all.rawValue
    @AppStorage("cardKind") private var kindRaw = CardKind.words.rawValue

    @StateObject private var session = StudySession()
    @StateObject private var draft = VerseDraft()

    private var words: [Word] { store.deck.words }
    private var verses: [Verse] { store.deck.verses }
    private var kind: CardKind { CardKind(rawValue: kindRaw) ?? .words }
    private var mode: PracticeMode { PracticeMode(rawValue: modeRaw) ?? .all }
    private var order: [Int] { session.order }
    private var position: Int { session.position }
    private var flipped: Bool { session.flipped }

    private var allGroupKeys: Set<String> {
        Set(store.deck.sources.flatMap { s in s.groups.map { GroupKey.make(s.id, $0.id) } })
    }

    private var selected: Binding<Set<String>> {
        Binding(
            get: {
                selectedRaw == "*" ? allGroupKeys : Set(selectedRaw.split(separator: "\n").map(String.init))
            },
            set: { selectedRaw = $0.sorted().joined(separator: "\n") })
    }

    private var excludedLangs: Binding<Set<String>> {
        Binding(
            get: { Set(excludedRaw.split(separator: ",").map(String.init)) },
            set: { excludedRaw = $0.sorted().joined(separator: ",") })
    }

    private var currentIndex: Int? {
        order.indices.contains(position) ? order[position] : nil
    }

    private func verse(at index: Int) -> Verse {
        verses[index].applying(verseEdits.edits[verses[index].id])
    }

    private func cardID(at index: Int) -> String {
        kind == .words ? words[index].id : verses[index].id
    }

    var body: some View {
        NavigationSplitView {
            FilterView(
                deck: store.deck,
                selected: selected,
                excludedLangs: excludedLangs,
                collapsed: $session.collapsedSources,
                cardCount: order.count,
                cardNoun: kind == .words ? "word cards" : "verse cards")
            .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } detail: {
            detail
                .padding(24)
                .toolbar { toolbar }
        }
        .onAppear(perform: rebuild)
        .onChange(of: selectedRaw) { rebuild() }
        .onChange(of: excludedRaw) { rebuild() }
        .onChange(of: shuffle) { rebuild() }
        .onChange(of: modeRaw) { rebuild() }
        .onChange(of: kindRaw) { rebuild() }
        .onChange(of: store.revision) { rebuild() }
        .sheet(isPresented: Binding(
            get: { session.editingVerse != nil },
            set: { if !$0 { session.editingVerse = nil } })
        ) {
            if let index = session.editingVerse {
                VerseEditorView(
                    original: verses[index],
                    hasLocalEdit: verseEdits.edits[verses[index].id] != nil,
                    draft: draft,
                    onSave: { edit in
                        verseEdits.save(edit, for: verses[index].id)
                        session.editingVerse = nil
                    },
                    onRevert: {
                        verseEdits.revert(verses[index].id)
                        session.editingVerse = nil
                    },
                    onCancel: { session.editingVerse = nil })
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil || verseEdits.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil; verseEdits.errorMessage = nil } })
        ) {
            Button("OK") { store.errorMessage = nil; verseEdits.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? verseEdits.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let index = currentIndex {
            let id = cardID(at: index)
            VStack(spacing: 18) {
                header
                Group {
                    if kind == .words {
                        CardView(
                            word: words[index],
                            flipped: flipped,
                            isKnown: progress.known.contains(id),
                            isReview: progress.review.contains(id))
                    } else {
                        VerseCardView(
                            verse: verse(at: index),
                            flipped: flipped,
                            isKnown: progress.known.contains(id),
                            isReview: progress.review.contains(id))
                    }
                }
                .onTapGesture { session.flipped.toggle() }
                .animation(.easeInOut(duration: 0.15), value: flipped)
                controls(index: index, id: id)
                    .disabled(session.editingVerse != nil)
            }
        } else {
            ContentUnavailableView(
                "No cards to practice",
                systemImage: "rectangle.stack",
                description: Text(emptyHint))
        }
    }

    private var emptyHint: String {
        switch mode {
        case .review: "No cards are marked for review in the selected chapters. Press R on a card to mark it."
        case .notKnown: "Every card in the selected chapters is marked known."
        case .all: "Tick at least one chapter or section in the sidebar."
        }
    }

    private var header: some View {
        HStack {
            Text("Card \(position + 1) of \(order.count)")
                .font(.headline)
            Spacer()
            let ids = Set(order.map(cardID(at:)))
            Text("Known \(ids.intersection(progress.known).count) · Review \(ids.intersection(progress.review).count)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func controls(index: Int, id: String) -> some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button { session.flipped.toggle() } label: {
                Label(flipped ? "Hide" : (kind == .words ? "Show meaning" : "Show verse"), systemImage: "arrow.2.squarepath")
            }
            .keyboardShortcut(.space, modifiers: [])
            Button { move(1) } label: { Label("Next", systemImage: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Spacer()
            if kind == .verses {
                Button {
                    draft.load(verse(at: index))
                    session.editingVerse = index
                } label: { Label("Edit verse (E)", systemImage: "pencil") }
                .keyboardShortcut("e", modifiers: [])
            }
            Button { progress.toggleKnown(id) } label: {
                Label("Known (K)", systemImage: progress.known.contains(id) ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .keyboardShortcut("k", modifiers: [])
            Button { progress.toggleReview(id) } label: {
                Label("Review (R)", systemImage: progress.review.contains(id) ? "flag.fill" : "flag")
            }
            .keyboardShortcut("r", modifiers: [])
        }
        .controlSize(.large)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Cards", selection: $kindRaw) {
                ForEach(CardKind.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .help("Practice words or whole verses")
        }
        ToolbarItemGroup {
            Picker("Practice", selection: $modeRaw) {
                ForEach(PracticeMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $shuffle) { Label("Shuffle", systemImage: "shuffle") }
                .help("Shuffle the cards")
            Button { rebuild() } label: { Label("Restart", systemImage: "arrow.counterclockwise") }
                .help("Start again from the first card")
        }
    }

    private func move(_ delta: Int) {
        guard !order.isEmpty else { return }
        session.position = (position + delta + order.count) % order.count
        session.flipped = false
    }

    private func rebuild() {
        let keys = selected.wrappedValue
        let langs = Dictionary(uniqueKeysWithValues: store.deck.sources.map { ($0.id, $0.lang) })
        let excluded = excludedLangs.wrappedValue
        let included: (String, String) -> Bool = { key, src in
            keys.contains(key) && !excluded.contains(langs[src] ?? "")
        }
        var picked: [Int]
        switch kind {
        case .words:
            picked = words.indices.filter { i in words[i].refs.contains { included($0.key, $0.src) } }
        case .verses:
            picked = verses.indices.filter { included(verses[$0].key, verses[$0].src) }
        }
        switch mode {
        case .all: break
        case .notKnown: picked.removeAll { progress.known.contains(cardID(at: $0)) }
        case .review: picked.removeAll { !progress.review.contains(cardID(at: $0)) }
        }
        session.order = shuffle ? picked.shuffled() : picked
        session.position = 0
        session.flipped = false
    }
}

@MainActor
final class StudySession: ObservableObject {
    @Published var order: [Int] = []
    @Published var position = 0
    @Published var flipped = false
    @Published var collapsedSources: Set<String> = []
    @Published var editingVerse: Int?
}
