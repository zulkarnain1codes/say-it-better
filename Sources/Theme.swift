import SwiftUI
import UIKit

enum Theme {
    /// Red pen: grammar mistakes.
    static let pen = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.42, blue: 0.48, alpha: 1)
            : UIColor(red: 0.80, green: 0.16, blue: 0.21, alpha: 1)
    })
    /// Highlighter: better word choices.
    static let highlighter = Color(red: 1.0, green: 0.875, blue: 0.37)
    static let highlighterInk = Color(red: 0.11, green: 0.094, blue: 0.024)
    /// Teal: listening and main actions.
    static let go = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.15, green: 0.69, blue: 0.61, alpha: 1)
            : UIColor(red: 0.05, green: 0.48, blue: 0.42, alpha: 1)
    })
}

struct Accent: Identifiable, Hashable {
    let id: String
    let name: String
}

enum Accents {
    static let all: [Accent] = [
        Accent(id: "en-AU", name: "Australian English"),
        Accent(id: "en-US", name: "American English"),
        Accent(id: "en-GB", name: "British English"),
        Accent(id: "en-NZ", name: "New Zealand English"),
        Accent(id: "en-IN", name: "Indian English"),
        Accent(id: "en-IE", name: "Irish English"),
        Accent(id: "en-ZA", name: "South African English"),
        Accent(id: "en-CA", name: "Canadian English"),
    ]

    static var defaultID: String {
        let here = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        return all.first(where: { here.hasPrefix($0.id) })?.id ?? "en-US"
    }
}

/// Builds text with the mistake marks.
enum Highlighter {
    private typealias Foreground = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
    private typealias Background = AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute
    private typealias Underline = AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute
    private typealias Strikethrough = AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute

    static func mark(_ text: String, kind: Issue.Kind) -> AttributedString {
        var piece = AttributedString(text)
        switch kind {
        case .grammar:
            piece[Underline.self] = Text.LineStyle(pattern: .dot, color: Theme.pen)
            piece[Foreground.self] = Theme.pen
        case .word:
            piece[Background.self] = Theme.highlighter
            piece[Foreground.self] = Theme.highlighterInk
        }
        return piece
    }

    /// "what you said → better", with what you said crossed out.
    static func correction(said: String, better: String) -> AttributedString {
        var wrong = AttributedString(said)
        wrong[Strikethrough.self] = Text.LineStyle(pattern: .solid, color: Theme.pen)
        var result = wrong
        result.append(AttributedString("  →  "))
        result.append(AttributedString(better))
        return result
    }

    static var demo: AttributedString {
        var text = AttributedString("Yesterday I ")
        text.append(mark("go", kind: .grammar))
        text.append(AttributedString(" to the shop and "))
        text.append(mark("did a mistake", kind: .word))
        text.append(AttributedString(" with the order."))
        return text
    }

    /// A paragraph with its mistakes marked.
    static func paragraph(_ segment: Segment) -> AttributedString {
        let text = segment.text
        var result = AttributedString()
        var cursor = text.startIndex
        for (range, kind) in ranges(in: text, for: segment.issues) {
            if cursor < range.lowerBound {
                result.append(AttributedString(String(text[cursor..<range.lowerBound])))
            }
            result.append(mark(String(text[range]), kind: kind))
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result.append(AttributedString(String(text[cursor...])))
        }
        return result
    }

    private static func ranges(in text: String, for issues: [Issue]) -> [(Range<String.Index>, Issue.Kind)] {
        var taken: [Range<String.Index>] = []
        var found: [(Range<String.Index>, Issue.Kind)] = []
        for issue in issues {
            let variants = [
                issue.quote,
                issue.quote.replacingOccurrences(of: "'", with: "’"),
                issue.quote.replacingOccurrences(of: "’", with: "'"),
            ]
            var match: Range<String.Index>?
            search: for variant in variants where !variant.isEmpty {
                var start = text.startIndex
                while start < text.endIndex,
                      let range = text.range(of: variant,
                                             options: [.caseInsensitive, .diacriticInsensitive],
                                             range: start..<text.endIndex) {
                    if !taken.contains(where: { $0.overlaps(range) }) && isWholeWords(range, in: text) {
                        match = range
                        break search
                    }
                    start = text.index(after: range.lowerBound)
                }
            }
            if let match {
                taken.append(match)
                found.append((match, issue.kind))
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }
    }

    private static func isWholeWords(_ range: Range<String.Index>, in text: String) -> Bool {
        let startsClean = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
        let endsClean = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
        return startsClean && endsClean
    }
}
