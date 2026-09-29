import AppKit
import Foundation

struct PushPlan: Decodable {
    struct Change: Decodable {
        let before: [String]
        let after: [String]
    }

    struct PlanVerse: Decodable, Identifiable {
        let id: String
        let label: String
        let file: String
        let changes: [String: Change]
    }

    struct RepoInfo: Decodable {
        let path: String
        let branch: String
        let remote: String
        let files: [String]
        let other_changes: [String]
    }

    let message: String
    let verses: [PlanVerse]
    let unchanged: [String]
    let unknown: [String]
    let bhakti: RepoInfo
    let sloka_words: RepoInfo
}

private struct ToolResult: Decodable {
    let ok: Bool
    let error: String?
    let log: [String]?
    let deck: String?
}

/// Runs tools/push_edits.py from the sloka_words checkout: a dry run to build the
/// confirmation sheet, then the real run that commits and pushes both repos.
@MainActor
final class RepoPushStore: ObservableObject {
    enum Phase {
        case checking
        case review(PushPlan)
        case pushing
        case done([String])
        case failed(String)
    }

    @Published var isPresented = false
    @Published private(set) var phase: Phase = .checking
    @Published var message = ""
    @Published private(set) var slokaPath: String
    @Published private(set) var bhaktiPath: String

    private let defaults = UserDefaults.standard

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        slokaPath = defaults.string(forKey: "slokaRepoPath") ?? "\(home)/code/sloka_words"
        bhaktiPath = defaults.string(forKey: "bhaktiRepoPath") ?? "\(home)/code/bhakti"
    }

    private var toolPath: String { "\(slokaPath)/tools/push_edits.py" }

    private var reposFound: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: toolPath) && fm.fileExists(atPath: "\(bhaktiPath)/.git")
    }

    func begin() {
        if !reposFound && !chooseFolders() { return }
        isPresented = true
        check()
    }

    /// Asks for both checkouts; returns false if the user cancels or picks the wrong folders.
    @discardableResult
    func chooseFolders() -> Bool {
        guard let sloka = pickFolder("Choose your sloka_words checkout", start: slokaPath),
              let bhakti = pickFolder("Choose your bhakti checkout", start: bhaktiPath) else { return false }
        slokaPath = sloka
        bhaktiPath = bhakti
        defaults.set(sloka, forKey: "slokaRepoPath")
        defaults.set(bhakti, forKey: "bhaktiRepoPath")
        guard reposFound else {
            phase = .failed("Those folders don't look right. The sloka_words folder must contain tools/push_edits.py, and the bhakti folder must be a git checkout.")
            isPresented = true
            return false
        }
        return true
    }

    func check() {
        phase = .checking
        Task {
            do {
                let data = try await run(["--dry-run"])
                let result = try JSONDecoder().decode(ToolResult.self, from: data)
                if !result.ok { throw ToolError(result.error ?? "The dry run failed.") }
                let plan = try JSONDecoder().decode(PushPlan.self, from: data)
                message = plan.message
                phase = .review(plan)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func push(then reloadDeck: @escaping (URL) -> Void) {
        phase = .pushing
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let data = try await run(message.isEmpty ? [] : ["--message", message])
                let result = try JSONDecoder().decode(ToolResult.self, from: data)
                if !result.ok { throw ToolError(result.error ?? "The push failed.") }
                if let deck = result.deck { reloadDeck(URL(fileURLWithPath: deck)) }
                phase = .done(result.log ?? [])
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func run(_ extra: [String]) async throws -> Data {
        let args = [toolPath, "--repo", bhaktiPath, "--edits", VerseEditStore.fileURL.path] + extra
        let cwd = URL(fileURLWithPath: slokaPath)
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3"] + args
            process.currentDirectoryURL = cwd
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            env["GIT_TERMINAL_PROMPT"] = "0"
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if data.isEmpty {
                throw ToolError(String(data: errData, encoding: .utf8) ?? "push_edits.py printed nothing.")
            }
            return data
        }.value
    }

    private func pickFolder(_ title: String, start: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: start)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

struct ToolError: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}
