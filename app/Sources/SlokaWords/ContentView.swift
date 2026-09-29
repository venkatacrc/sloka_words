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

enum StudyMode: String, CaseIterable, Identifiable {
    case learn, test

    var id: String { rawValue }
    var title: String { self == .learn ? "Learn" : "Test" }
}

struct ContentView: View {
    @EnvironmentObject private var store: DeckStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var verseEdits: VerseEditStore
    @EnvironmentObject private var pusher: RepoPushStore
    @EnvironmentObject private var printRequest: PrintRequest

    /// Newline-separated `src|group` keys; `*` means every group in the deck.
    @AppStorage("selectedGroups") private var selectedRaw = "*"
    @AppStorage("excludedLangs") private var excludedRaw = ""
    @AppStorage("shuffle") private var shuffle = false
    @AppStorage("practiceMode") private var modeRaw = PracticeMode.all.rawValue
    @AppStorage("cardKind") private var kindRaw = CardKind.words.rawValue
    @AppStorage("studyMode") private var studyRaw = StudyMode.learn.rawValue

    @StateObject private var session = StudySession()
    @StateObject private var draft = VerseDraft()

    private var words: [Word] { store.deck.words }
    private var verses: [Verse] { store.deck.verses }
    private var selectedKind: CardKind { CardKind(rawValue: kindRaw) ?? .words }
    /// The kind `session.order` was built for; lags `selectedKind` until `rebuild()` runs.
    private var kind: CardKind { session.kind }
    private var mode: PracticeMode { PracticeMode(rawValue: modeRaw) ?? .all }
    private var order: [Int] { session.order }
    private var position: Int { session.position }
    private var study: StudyMode { StudyMode(rawValue: studyRaw) ?? .learn }
    /// In Learn mode every card is shown in full; in Test mode the answer is hidden until revealed.
    private var flipped: Bool { study == .learn || session.flipped }

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
        let count = kind == .words ? words.count : verses.count
        guard order.indices.contains(position), order.allSatisfy({ $0 < count }) else { return nil }
        return order[position]
    }

    private func verse(at index: Int) -> Verse {
        verses[index].applying(verseEdits.edits[verses[index].id])
    }

    private func cardID(at index: Int) -> String {
        kind == .words ? words[index].id : verses[index].id
    }

    private func isIncluded(_ key: String, _ src: String) -> Bool {
        let langs = Dictionary(uniqueKeysWithValues: store.deck.sources.map { ($0.id, $0.lang) })
        return selected.wrappedValue.contains(key) && !excludedLangs.wrappedValue.contains(langs[src] ?? "")
    }

    private var selectedVerses: [Verse] {
        verses.indices.filter { isIncluded(verses[$0].key, verses[$0].src) }.map(verse(at:))
    }

    private func printHeading(_ verse: Verse) -> String {
        guard let source = store.deck.sources.first(where: { $0.id == verse.src }) else { return verse.src }
        let group = source.groups.first { $0.id == verse.group }?.label ?? verse.group
        return source.groups.count > 1 ? "\(source.title) — \(group)" : source.title
    }

    private var printTitle: String {
        let ids = Set(selectedVerses.map(\.src))
        let titles = store.deck.sources.filter { ids.contains($0.id) }.map(\.title)
        return titles.isEmpty ? "Sloka Words" : titles.joined(separator: ", ")
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
        .onChange(of: studyRaw) { rebuild() }
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
        .sheet(isPresented: $pusher.isPresented) {
            PushEditsView(pusher: pusher, onPushed: { store.importDeck(from: $0) })
        }
        .sheet(isPresented: $printRequest.isPresented) {
            PrintVersesView(
                verses: selectedVerses,
                reviewIDs: progress.review,
                heading: printHeading,
                title: printTitle,
                onClose: { printRequest.isPresented = false })
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
        if study == .test && session.finished {
            testSummary
        } else if let index = currentIndex {
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
                .onTapGesture { if study == .test { session.flipped = true } }
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
            if study == .test {
                let answered = session.answers.count
                let correct = session.answers.values.filter { $0 }.count
                Text("Score \(correct) of \(answered) · \(order.count - answered) to go")
                    .font(.callout.weight(.medium))
            } else {
                let ids = Set(order.map(cardID(at:)))
                Text("Known \(ids.intersection(progress.known).count) · Review \(ids.intersection(progress.review).count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var testSummary: some View {
        let correct = session.answers.values.filter { $0 }.count
        let missed = order.filter { session.answers[cardID(at: $0)] == false }
        let percent = order.isEmpty ? 0 : Int((Double(correct) / Double(order.count) * 100).rounded())
        VStack(spacing: 16) {
            Image(systemName: missed.isEmpty ? "star.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(missed.isEmpty ? .yellow : .green)
            Text("Test complete").font(.largeTitle.weight(.semibold))
            Text("\(correct) of \(order.count) correct (\(percent)%)").font(.title2)
            Text(missed.isEmpty
                 ? "Every card is now marked known."
                 : "Cards you got are marked known; the \(missed.count) you missed are marked for review.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if !missed.isEmpty {
                    Button("Retest the \(missed.count) missed") { retest(missed) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                Button("Start a new test") { rebuild() }
                Button("Switch to Learn") { studyRaw = StudyMode.learn.rawValue }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func controls(index: Int, id: String) -> some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: { Label("Previous", systemImage: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [])
            if study == .test {
                if flipped {
                    Button { answer(id, correct: false) } label: { Label("Missed it (M)", systemImage: "xmark.circle") }
                        .keyboardShortcut("m", modifiers: [])
                        .tint(.orange)
                    Button { answer(id, correct: true) } label: { Label("Got it (G)", systemImage: "checkmark.circle") }
                        .keyboardShortcut("g", modifiers: [])
                        .tint(.green)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { session.flipped = true } label: {
                        Label(kind == .words ? "Show answer" : "Show verse", systemImage: "eye")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .buttonStyle(.borderedProminent)
                }
            }
            Button { move(1) } label: {
                Label(study == .test ? "Skip" : "Next", systemImage: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            Spacer()
            if kind == .verses {
                Button {
                    draft.load(verse(at: index))
                    session.editingVerse = index
                } label: { Label("Edit verse (E)", systemImage: "pencil") }
                .keyboardShortcut("e", modifiers: [])
            }
            if study == .learn {
                Button { progress.toggleKnown(id) } label: {
                    Label("Known (K)", systemImage: progress.known.contains(id) ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .keyboardShortcut("k", modifiers: [])
                Button { progress.toggleReview(id) } label: {
                    Label("Review (R)", systemImage: progress.review.contains(id) ? "flag.fill" : "flag")
                }
                .keyboardShortcut("r", modifiers: [])
            }
        }
        .controlSize(.large)
    }

    /// Records the answer, updates known/review, and moves to the next unanswered card.
    private func answer(_ id: String, correct: Bool) {
        session.answers[id] = correct
        if correct { progress.markKnown(id) } else { progress.markReview(id) }
        let next = (1...order.count).map { (position + $0) % order.count }
            .first { session.answers[cardID(at: order[$0])] == nil }
        if let next {
            session.position = next
            session.flipped = false
        } else {
            session.finished = true
        }
    }

    private func retest(_ indices: [Int]) {
        session.order = shuffle ? indices.shuffled() : indices
        session.position = 0
        session.flipped = false
        session.answers = [:]
        session.finished = false
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
        ToolbarItem(placement: .navigation) {
            Picker("Mode", selection: $studyRaw) {
                ForEach(StudyMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .help("Learn: see each card in full. Test: recall it, then mark whether you got it.")
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
            Button { printRequest.isPresented = true } label: { Label("Print", systemImage: "printer") }
                .help("Print the selected verses or save them as a PDF")
        }
    }

    private func move(_ delta: Int) {
        guard !order.isEmpty else { return }
        session.position = (position + delta + order.count) % order.count
        session.flipped = false
    }

    private func rebuild() {
        let included = isIncluded
        session.kind = selectedKind
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
        session.answers = [:]
        session.finished = false
    }
}

@MainActor
final class StudySession: ObservableObject {
    @Published var order: [Int] = []
    @Published var kind: CardKind = .words
    @Published var position = 0
    @Published var flipped = false
    @Published var collapsedSources: Set<String> = []
    @Published var editingVerse: Int?
    /// Test mode: card id → whether it was recalled correctly in this run.
    @Published var answers: [String: Bool] = [:]
    @Published var finished = false
}
