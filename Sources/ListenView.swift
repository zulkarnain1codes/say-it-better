import SwiftUI

struct ListenView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var listener: Listener
    @AppStorage("accent") private var accent: String = Accents.defaultID

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusRow
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                transcript
                controls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            .navigationTitle("Say it better")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: accent) {
            guard listener.isActive else { return }
            Task {
                await listener.stop()
                await listener.start(localeID: accent)
            }
        }
    }

    // MARK: - Parts

    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: listener.status == .listening)
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            if wordCount > 0 {
                Text(plural(wordCount, "word") + " so far")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showsIntro {
                        ListenIntro()
                    }
                    ForEach(recentSegments) { segment in
                        Text(segment.text)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                    if !listener.liveText.isEmpty {
                        Text(listener.liveText)
                            .font(.system(.title2, design: .serif).weight(.medium))
                    } else if listener.status == .listening {
                        Text("Start talking. Your words will appear here.")
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .onChange(of: listener.liveText) {
                proxy.scrollTo("end", anchor: .bottom)
            }
            .onChange(of: store.current?.updated) {
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if let message = listener.message ?? store.saveError {
                Text(message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            Button {
                Task {
                    if listener.isActive {
                        await listener.stop()
                    } else {
                        await listener.start(localeID: accent)
                    }
                }
            } label: {
                Label(listener.isActive ? "Stop listening" : "Start listening",
                      systemImage: listener.isActive ? "stop.fill" : "mic.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 58)
            }
            .buttonStyle(BigButtonStyle(active: listener.isActive))

            Text("Keeps listening when your phone is locked. Pauses during phone calls and starts again after.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                Text("Accent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Accent", selection: $accent) {
                    ForEach(Accents.all) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                if wordCount > 0 {
                    Button("New session") {
                        store.startNewSession()
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Helpers

    private var recentSegments: [Segment] {
        Array((store.current?.segments ?? []).suffix(4))
    }

    private var wordCount: Int {
        store.current?.wordCount ?? 0
    }

    private var showsIntro: Bool {
        listener.status == .idle && recentSegments.isEmpty && listener.liveText.isEmpty
    }

    private var statusText: String {
        switch listener.status {
        case .idle: return "Ready"
        case .preparing(let text): return text
        case .listening: return "Listening"
        case .paused(let text): return text
        }
    }

    private var statusColor: Color {
        switch listener.status {
        case .idle: return .secondary
        case .preparing, .paused: return Theme.highlighter
        case .listening: return Theme.go
        }
    }
}

struct ListenIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tap Start listening and talk. Your words show up here, and it keeps listening when your phone is locked.")
                .font(.system(.title3, design: .serif))
            VStack(alignment: .leading, spacing: 6) {
                Text("Later, Review marks your mistakes like this:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(Highlighter.demo)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
            }
        }
    }
}

struct BigButtonStyle: ButtonStyle {
    var active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Color.white : Color(.systemBackground))
            .background(Capsule().fill(active ? Theme.go : Color.primary))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
