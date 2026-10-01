import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Nothing to review yet",
                        systemImage: "text.bubble",
                        description: Text("Go to Listen, tap Start listening and talk for a while. Then come back here to check it.")
                    )
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(value: session.id) {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { sessions[$0].id }
                            ids.forEach { store.delete($0) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Your sessions")
            .navigationDestination(for: UUID.self) { id in
                SessionDetailView(sessionID: id)
            }
        }
    }

    private var sessions: [Session] {
        store.sessions.filter { !$0.segments.isEmpty }
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.started, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                .font(.headline)
            HStack(spacing: 10) {
                Text(plural(session.wordCount, "word"))
                    .foregroundStyle(.secondary)
                if session.grammarCount > 0 {
                    Text(Highlighter.mark("\(session.grammarCount) grammar", kind: .grammar))
                }
                if session.wordChoiceCount > 0 {
                    Text(Highlighter.mark("\(session.wordChoiceCount) word choice", kind: .word))
                }
            }
            .font(.subheadline)
            if session.uncheckedWordCount > 0 {
                Text(session.checkedWordCount > 0 ? "New words to check" : "Not checked yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if session.issueCount == 0 {
                Text("No mistakes found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SessionDetailView: View {
    let sessionID: UUID
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var coach: Coach

    var body: some View {
        if let session = store.session(sessionID) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header(session)
                    actions(session)
                    legend
                    if !session.tips.isEmpty || session.issueCount >= 3 {
                        tipsCard(session)
                    }
                    transcript(session)
                }
                .padding(20)
            }
            .navigationTitle(Text(session.started, format: .dateTime.weekday(.abbreviated).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: session.plainText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share the transcript")
                }
            }
        } else {
            ContentUnavailableView("This session was deleted", systemImage: "trash")
        }
    }

    // MARK: - Parts

    private func header(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.started, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                .font(.title3.weight(.semibold))
            Text(summary(session))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func actions(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if coach.checkingID == session.id {
                HStack(spacing: 12) {
                    ProgressView()
                    Button("Stop checking") { coach.stop() }
                        .buttonStyle(.bordered)
                }
            } else {
                Button(checkTitle(session)) {
                    coach.check(session.id, store: store)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.go)
                .disabled(session.uncheckedWordCount == 0 || coach.isBusy || Coach.problem != nil)
            }
            if let line = statusLine(session) {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            Text(Highlighter.mark("Grammar", kind: .grammar))
            Text(Highlighter.mark("Word choice", kind: .word))
            Spacer()
        }
        .font(.footnote)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tipsCard(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What to work on")
                .font(.headline)
            if session.tips.isEmpty {
                Text("See which mistakes you make most often in this session.")
                    .foregroundStyle(.secondary)
            }
            ForEach(session.tips) { tip in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tip.tip)
                    if !tip.said.isEmpty && !tip.better.isEmpty {
                        Text(Highlighter.correction(said: tip.said, better: tip.better))
                            .font(.system(.callout, design: .serif))
                    }
                }
            }
            if coach.patternsID == session.id {
                ProgressView("Looking for patterns…")
            } else if session.tips.isEmpty || session.tipsStale {
                Button(session.tips.isEmpty ? "Find my patterns" : "Update with new mistakes") {
                    coach.findPatterns(session.id, store: store)
                }
                .buttonStyle(.bordered)
                .disabled(coach.isBusy || Coach.problem != nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func transcript(_ session: Session) -> some View {
        ForEach(Array(session.segments.enumerated()), id: \.element.id) { index, segment in
            VStack(alignment: .leading, spacing: 8) {
                if index == 0 || segment.date.timeIntervalSince(session.segments[index - 1].date) > 300 {
                    Text(segment.date, format: .dateTime.hour().minute())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                if !segment.checked && (index == 0 || session.segments[index - 1].checked) {
                    Text("Not checked yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(Capsule().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3])))
                }
                SegmentView(sessionID: session.id, segment: segment)
            }
        }
    }

    // MARK: - Text

    private func summary(_ session: Session) -> String {
        var parts = [plural(session.wordCount, "word")]
        if session.checkedWordCount > 0 {
            parts.append(session.issueCount == 0 ? "no mistakes found so far" : plural(session.issueCount, "mark"))
        }
        return parts.joined(separator: ", ")
    }

    private func checkTitle(_ session: Session) -> String {
        if session.uncheckedWordCount == 0 { return "All checked" }
        return session.checkedWordCount > 0 ? "Check new words" : "Check grammar"
    }

    private func statusLine(_ session: Session) -> String? {
        if coach.checkingID == session.id { return coach.progress }
        if let note = coach.notes[session.id] { return note }
        if let problem = Coach.problem { return problem }
        if coach.isBusy { return "Another check is running. Wait for it to finish." }
        if session.uncheckedWordCount > 0 {
            return plural(session.uncheckedWordCount, "word") + " not checked yet. Checking runs on your iPhone and can take a few minutes for a long session."
        }
        return nil
    }
}

struct SegmentView: View {
    let sessionID: UUID
    let segment: Segment
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Highlighter.paragraph(segment))
                .font(.system(.body, design: .serif))
                .foregroundStyle(segment.checked ? Color.primary : Color.secondary)
                .lineSpacing(4)
                .textSelection(.enabled)
            if segment.couldNotCheck {
                Text("Apple's AI couldn't check this part.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(segment.issues) { issue in
                IssueRow(issue: issue) {
                    dismiss(issue)
                }
            }
        }
    }

    private func dismiss(_ issue: Issue) {
        store.update(sessionID) { session in
            guard let index = session.segments.firstIndex(where: { $0.id == segment.id }) else { return }
            session.segments[index].issues.removeAll { $0.id == issue.id }
            if !session.tips.isEmpty { session.tipsStale = true }
        }
    }
}

struct IssueRow: View {
    let issue: Issue
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(issue.kind == .word ? Theme.highlighter : Theme.pen)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.kind == .word ? "Word choice" : "Grammar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Highlighter.correction(said: issue.quote, better: issue.fix))
                    .font(.system(.callout, design: .serif))
                if !issue.why.isEmpty {
                    Text(issue.why)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Not a mistake")
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
