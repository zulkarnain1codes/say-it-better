import Foundation
import FoundationModels
import UIKit

// What we ask Apple's on-device model to fill in.

@Generable
struct CheckResult {
    @Guide(description: "Clear mistakes in the transcript. Use an empty list if there are none.")
    let mistakes: [FoundMistake]
}

@Generable
struct FoundMistake {
    @Guide(description: "The exact words copied from the transcript that contain the mistake, usually 1 to 6 words.")
    let quote: String
    @Guide(description: "The corrected version of the quoted words.")
    let fix: String
    @Guide(.anyOf(["grammar", "word choice"]))
    let kind: String
    @Guide(description: "One short sentence in simple English that explains the fix.")
    let why: String
}

@Generable
struct PatternResult {
    @Guide(description: "Up to three tips about the mistakes this person makes most often.")
    let tips: [PatternTip]
}

@Generable
struct PatternTip {
    @Guide(description: "A short tip in simple English, at most 20 words.")
    let tip: String
    @Guide(description: "One example of what the person said, copied from the list.")
    let said: String
    @Guide(description: "The better way to say that example.")
    let better: String
}

/// Checks transcripts for grammar and word-choice mistakes, entirely on the iPhone.
@MainActor
final class Coach: ObservableObject {
    @Published private(set) var checkingID: UUID?
    @Published private(set) var patternsID: UUID?
    @Published private(set) var progress = ""
    @Published var notes: [UUID: String] = [:]

    var isBusy: Bool { checkingID != nil || patternsID != nil }

    private var work: Task<Void, Never>?

    private static let instructions = """
    You are a friendly English speaking coach. You read automatic speech-to-text transcripts \
    of one person talking out loud, and you find real mistakes in what they said.
    Report two kinds of mistakes:
    - grammar: verb tense, subject-verb agreement, a/an/the, prepositions, plurals, word order, missing or extra words.
    - word choice: a wrong word, or a phrase a fluent speaker would say differently.
    Ignore punctuation, capital letters, filler words (um, uh, like, you know), repeated words, \
    false starts and normal casual speech (gonna, wanna, yeah, contractions).
    The speech recognizer sometimes mishears words. If a problem is probably a recognition error, skip it.
    Only report clear mistakes. Copy each quote exactly from the transcript.
    """

    /// Why checking can't run on this iPhone right now, if it can't.
    static var problem: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri to check grammar."
        case .unavailable(.modelNotReady):
            return "Apple's AI is still getting ready. Leave your iPhone charging on Wi-Fi for a while, then try again."
        case .unavailable:
            return "This iPhone can't run Apple's AI, so grammar checking isn't available."
        }
    }

    // MARK: - Checking

    func check(_ id: UUID, store: SessionStore) {
        guard !isBusy, let session = store.session(id) else { return }
        if let problem = Coach.problem {
            notes[id] = problem
            return
        }
        let batches = Coach.batches(from: session.segments.filter { !$0.checked })
        guard !batches.isEmpty else { return }
        checkingID = id
        notes[id] = nil
        UIApplication.shared.isIdleTimerDisabled = true
        work = Task { [weak self] in
            await self?.runCheck(id, batches: batches, store: store)
        }
    }

    func stop() {
        work?.cancel()
    }

    private func runCheck(_ id: UUID, batches: [[Segment]], store: SessionStore) async {
        defer { finishCheck() }
        for (index, batch) in batches.enumerated() {
            if Task.isCancelled { break }
            progress = "Checking part \(index + 1) of \(batches.count). Keep the app open."
            let text = batch.map(\.text).joined(separator: "\n")
            do {
                let found = try await Coach.findMistakes(in: text)
                store.update(id) { session in Coach.apply(found, to: batch, in: &session) }
            } catch LanguageModelSession.GenerationError.guardrailViolation {
                store.update(id) { session in Coach.markSkipped(batch, in: &session) }
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                store.update(id) { session in Coach.markSkipped(batch, in: &session) }
            } catch {
                if !Task.isCancelled {
                    notes[id] = "The check stopped before it finished. Tap the button to keep going."
                }
                break
            }
        }
    }

    private func finishCheck() {
        checkingID = nil
        progress = ""
        work = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private static func findMistakes(in text: String) async throws -> [FoundMistake] {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "Find the mistakes in this transcript:\n\n\(text)",
                                                  generating: CheckResult.self)
        return response.content.mistakes
    }

    /// Groups paragraphs into small batches so each fits the on-device model.
    private static func batches(from segments: [Segment]) -> [[Segment]] {
        var result: [[Segment]] = []
        var current: [Segment] = []
        var words = 0
        for segment in segments {
            let count = segment.text.wordCount
            if !current.isEmpty && words + count > 180 {
                result.append(current)
                current = []
                words = 0
            }
            current.append(segment)
            words += count
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
    }

    private static func apply(_ found: [FoundMistake], to batch: [Segment], in session: inout Session) {
        var perSegment: [UUID: [Issue]] = [:]
        for mistake in found {
            let quote = mistake.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            let fix = mistake.fix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty, !fix.isEmpty,
                  normalized(quote).lowercased() != normalized(fix).lowercased() else { continue }
            // Keep only mistakes whose words really appear in what was said.
            guard let owner = batch.first(where: {
                normalized($0.text).range(of: normalized(quote), options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }) else { continue }
            let kind: Issue.Kind = mistake.kind.lowercased().contains("word") ? .word : .grammar
            let why = mistake.why.trimmingCharacters(in: .whitespacesAndNewlines)
            perSegment[owner.id, default: []].append(Issue(kind: kind, quote: quote, fix: fix, why: why))
        }
        for checkedSegment in batch {
            guard let index = session.segments.firstIndex(where: { $0.id == checkedSegment.id }) else { continue }
            // If more words were added while checking, check this paragraph again next time.
            guard session.segments[index].text == checkedSegment.text else { continue }
            session.segments[index].issues = Array((perSegment[checkedSegment.id] ?? []).prefix(12))
            session.segments[index].checked = true
            session.segments[index].couldNotCheck = false
        }
        if !session.tips.isEmpty { session.tipsStale = true }
    }

    private static func markSkipped(_ batch: [Segment], in session: inout Session) {
        for skipped in batch {
            guard let index = session.segments.firstIndex(where: { $0.id == skipped.id }),
                  session.segments[index].text == skipped.text else { continue }
            session.segments[index].checked = true
            session.segments[index].couldNotCheck = true
            session.segments[index].issues = []
        }
    }

    // MARK: - Patterns

    func findPatterns(_ id: UUID, store: SessionStore) {
        guard !isBusy, let session = store.session(id) else { return }
        if let problem = Coach.problem {
            notes[id] = problem
            return
        }
        let issues = Array(session.segments.flatMap(\.issues).suffix(40))
        guard issues.count >= 3 else { return }
        patternsID = id
        notes[id] = nil
        work = Task { [weak self] in
            await self?.runPatterns(id, issues: issues, store: store)
        }
    }

    private func runPatterns(_ id: UUID, issues: [Issue], store: SessionStore) async {
        defer {
            patternsID = nil
            work = nil
        }
        let list = issues.map { issue -> String in
            let kind = issue.kind == .word ? "word choice" : "grammar"
            return "- \(kind): said \"\(issue.quote)\", better \"\(issue.fix)\""
        }.joined(separator: "\n")
        do {
            let session = LanguageModelSession(instructions: "You are a friendly English speaking coach. You spot patterns in a learner's spoken mistakes and give short, simple tips.")
            let response = try await session.respond(
                to: "Here are mistakes an English learner made while speaking. Find the three most common or most important patterns.\n\n\(list)",
                generating: PatternResult.self
            )
            let tips = response.content.tips.prefix(3).map { Tip(tip: $0.tip, said: $0.said, better: $0.better) }
            if tips.isEmpty {
                notes[id] = "No clear patterns yet. Try again after more talking."
            } else {
                store.update(id) { session in
                    session.tips = Array(tips)
                    session.tipsStale = false
                }
            }
        } catch {
            if !Task.isCancelled {
                notes[id] = "Couldn't find patterns this time. Try again."
            }
        }
    }
}
