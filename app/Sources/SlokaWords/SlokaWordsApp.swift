import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct SlokaWordsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DeckStore()
    @StateObject private var progress = ProgressStore()
    @StateObject private var verseEdits = VerseEditStore()
    @StateObject private var pusher = RepoPushStore()
    @StateObject private var printRequest = PrintRequest()

    var body: some Scene {
        WindowGroup("Sloka Words") {
            ContentView()
                .environmentObject(store)
                .environmentObject(progress)
                .environmentObject(verseEdits)
                .environmentObject(pusher)
                .environmentObject(printRequest)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .printItem) {
                Button("Print Verses / Save as PDF…") { printRequest.isPresented = true }
                    .keyboardShortcut("p")
            }
            CommandGroup(after: .newItem) {
                Button("Import Deck…") { store.importDeck() }
                    .keyboardShortcut("o")
                Button("Reload Deck") { store.load() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Use Built-in Deck") { store.revertToBuiltIn() }
                Divider()
                Button("Export Verse Edits…") { verseEdits.exportEdits() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(verseEdits.edits.isEmpty)
                Button("Push Verse Edits to Repos…") { pusher.begin() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(verseEdits.edits.isEmpty)
                Button("Choose Repo Folders…") { pusher.chooseFolders() }
                Divider()
                Button("Reset Progress…") { progress.reset() }
            }
        }
    }
}
