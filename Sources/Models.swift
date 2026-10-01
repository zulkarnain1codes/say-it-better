import Foundation

/// One mistake found in what the person said.
struct Issue: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case grammar
        case word
    }

    var id = UUID()
    var kind: Kind
    var quote: String
    var fix: String
    var why: String
}

/// A paragraph of the transcript.
struct Segment: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
    var checked = false
    var couldNotCheck = false
    var issues: [Issue] = []
}

/// A short "what to work on" tip.
struct Tip: Codable, Identifiable, Hashable {
    var id = UUID()
    var tip: String
    var said: String
    var better: String
}

/// Everything heard during one stretch of listening (usually one shift).
struct Session: Codable, Identifiable, Hashable {
    var id = UUID()
    var started: Date
    var updated: Date
    var segments: [Segment] = []
    var tips: [Tip] = []
    var tipsStale = false

    var wordCount: Int { segments.reduce(0) { $0 + $1.text.wordCount } }
    var uncheckedWordCount: Int { segments.filter { !$0.checked }.reduce(0) { $0 + $1.text.wordCount } }
    var checkedWordCount: Int { wordCount - uncheckedWordCount }
    var grammarCount: Int { segments.reduce(0) { total, segment in total + segment.issues.filter { $0.kind == .grammar }.count } }
    var wordChoiceCount: Int { segments.reduce(0) { total, segment in total + segment.issues.filter { $0.kind == .word }.count } }
    var issueCount: Int { segments.reduce(0) { $0 + $1.issues.count } }
    var characterCount: Int { segments.reduce(0) { $0 + $1.text.count } }
    var plainText: String { segments.map(\.text).joined(separator: "\n\n") }
}

extension String {
    var wordCount: Int { split(whereSeparator: { $0.isWhitespace }).count }
}

func plural(_ count: Int, _ word: String) -> String {
    "\(count) \(word)\(count == 1 ? "" : "s")"
}
