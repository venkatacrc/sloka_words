import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var deck: Deck = .empty
    @Published private(set) var origin = ""
    @Published private(set) var revision = 0
    @Published var errorMessage: String?

    static var userDeckURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SlokaWords", isDirectory: true)
            .appendingPathComponent("words.json")
    }

    init() { load() }

    /// Prefers an imported deck in Application Support, then the copy inside the .app,
    /// then the SwiftPM resource bundle (used by `swift run`).
    func load() {
        var candidates: [(URL, String)] = []
        if FileManager.default.fileExists(atPath: Self.userDeckURL.path) {
            candidates.append((Self.userDeckURL, "Imported deck"))
        }
        if let url = Bundle.main.url(forResource: "words", withExtension: "json") {
            candidates.append((url, "Built-in deck"))
        } else if let url = Bundle.module.url(forResource: "words", withExtension: "json") {
            candidates.append((url, "Built-in deck"))
        }
        for (url, name) in candidates {
            do {
                let data = try Data(contentsOf: url)
                deck = try JSONDecoder().decode(Deck.self, from: data)
                origin = name
                revision += 1
                return
            } catch {
                errorMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func importDeck() {
        let panel = NSOpenPanel()
        panel.title = "Import a words.json deck"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importDeck(from: url)
    }

    func importDeck(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            _ = try JSONDecoder().decode(Deck.self, from: data)
            let dest = Self.userDeckURL
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try data.write(to: dest)
            load()
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func revertToBuiltIn() {
        try? FileManager.default.removeItem(at: Self.userDeckURL)
        load()
    }
}

/// Chanting-style verse edits, saved as `verse_edits.json` in Application Support and
/// exportable to the sloka_words repo so `build_deck.py` bakes them into the deck.
@MainActor
final class VerseEditStore: ObservableObject {
    @Published private(set) var edits: [String: VerseEdit] = [:]
    @Published var errorMessage: String?

    static var fileURL: URL {
        DeckStore.userDeckURL.deletingLastPathComponent().appendingPathComponent("verse_edits.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([String: VerseEdit].self, from: data) {
            edits = decoded
        }
    }

    func save(_ edit: VerseEdit, for id: String) {
        edits[id] = edit
        persist()
    }

    func revert(_ id: String) {
        edits.removeValue(forKey: id)
        persist()
    }

    func exportEdits() {
        let panel = NSSavePanel()
        panel.title = "Export verse edits"
        panel.message = "Save as verse_edits.json in the sloka_words folder, then rerun tools/build_deck.py."
        panel.nameFieldStringValue = "verse_edits.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var merged: [String: VerseEdit] = [:]
            if let data = try? Data(contentsOf: url) {
                merged = (try? JSONDecoder().decode([String: VerseEdit].self, from: data)) ?? [:]
            }
            merged.merge(edits) { _, new in new }
            try encoded(merged).write(to: url)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded(edits).write(to: Self.fileURL)
        } catch {
            errorMessage = "Could not save verse edits: \(error.localizedDescription)"
        }
    }

    private func encoded(_ value: [String: VerseEdit]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var known: Set<String>
    @Published private(set) var review: Set<String>

    private let defaults = UserDefaults.standard

    init() {
        known = Set(defaults.stringArray(forKey: "knownWords") ?? [])
        review = Set(defaults.stringArray(forKey: "reviewWords") ?? [])
    }

    func toggleKnown(_ id: String) {
        if known.remove(id) == nil {
            known.insert(id)
            review.remove(id)
        }
        save()
    }

    func toggleReview(_ id: String) {
        if review.remove(id) == nil {
            review.insert(id)
            known.remove(id)
        }
        save()
    }

    func markKnown(_ id: String) {
        known.insert(id)
        review.remove(id)
        save()
    }

    func markReview(_ id: String) {
        review.insert(id)
        known.remove(id)
        save()
    }

    func reset() {
        known = []
        review = []
        save()
    }

    private func save() {
        defaults.set(Array(known), forKey: "knownWords")
        defaults.set(Array(review), forKey: "reviewWords")
    }
}
