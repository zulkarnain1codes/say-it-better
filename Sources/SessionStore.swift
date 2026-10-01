import Foundation
import SwiftUI

/// Keeps every session on the iPhone, one file per session.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var currentID: UUID?
    @Published var saveError: String?

    /// Keep adding to the same session if the last words were less than this long ago.
    private let resumeWindow: TimeInterval = 2 * 60 * 60
    /// Start a fresh session once one gets this long.
    private let sessionCharacterCap = 150_000
    /// Words heard within this many seconds join the same paragraph.
    private let paragraphWindow: TimeInterval = 30
    private let paragraphWordLimit = 60

    private let folder: URL
    private var pendingSaves: Set<UUID> = []
    private var saveTask: Task<Void, Never>?
    private var lastAppend: Date?

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    var current: Session? {
        guard let currentID else { return nil }
        return session(currentID)
    }

    func session(_ id: UUID) -> Session? {
        sessions.first { $0.id == id }
    }

    @discardableResult
    func startNewSession() -> UUID {
        let now = Date()
        let session = Session(started: now, updated: now)
        sessions.insert(session, at: 0)
        currentID = session.id
        lastAppend = nil
        return session.id
    }

    /// Adds words that were just heard.
    func append(_ raw: String, at date: Date = Date()) {
        let text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return }
        let index = indexForNewWords()
        var session = sessions[index]

        if let last = session.segments.indices.last,
           !session.segments[last].checked,
           let lastAppend, date.timeIntervalSince(lastAppend) < paragraphWindow,
           session.segments[last].text.wordCount < paragraphWordLimit {
            session.segments[last].text += " " + text
        } else {
            session.segments.append(Segment(date: date, text: text))
        }
        lastAppend = date
        session.updated = date
        if !session.tips.isEmpty { session.tipsStale = true }
        sessions[index] = session

        if session.characterCount >= sessionCharacterCap {
            currentID = nil
        }
        scheduleSave(session.id)
    }

    func update(_ id: UUID, _ change: (inout Session) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
        scheduleSave(id)
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        pendingSaves.remove(id)
        if currentID == id {
            currentID = nil
            lastAppend = nil
        }
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    /// Writes any unsaved changes to disk right away.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var failed = false
        for id in pendingSaves {
            guard let session = session(id), !session.segments.isEmpty else { continue }
            do {
                let data = try encoder.encode(session)
                try data.write(to: fileURL(id), options: .atomic)
            } catch {
                failed = true
            }
        }
        pendingSaves.removeAll()
        saveError = failed ? "Couldn't save your words. Free up some space on your iPhone." : nil
    }

    // MARK: - Private

    private func indexForNewWords() -> Int {
        if let currentID, let index = sessions.firstIndex(where: { $0.id == currentID }) {
            let session = sessions[index]
            if session.segments.isEmpty || isFresh(session) { return index }
        }
        if let latest = sessions.filter({ !$0.segments.isEmpty }).max(by: { $0.updated < $1.updated }),
           isFresh(latest),
           let index = sessions.firstIndex(where: { $0.id == latest.id }) {
            currentID = latest.id
            return index
        }
        let id = startNewSession()
        return sessions.firstIndex(where: { $0.id == id }) ?? 0
    }

    private func isFresh(_ session: Session) -> Bool {
        Date().timeIntervalSince(session.updated) < resumeWindow && session.characterCount < sessionCharacterCap
    }

    private func fileURL(_ id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json")
    }

    private func scheduleSave(_ id: UUID) {
        pendingSaves.insert(id)
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Session] = []
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let session = try? decoder.decode(Session.self, from: data) {
                loaded.append(session)
            }
        }
        sessions = loaded.sorted { $0.started > $1.started }
        if let latest = sessions.max(by: { $0.updated < $1.updated }), isFresh(latest) {
            currentID = latest.id
        }
    }
}
