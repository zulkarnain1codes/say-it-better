import AVFoundation
import Speech
import UIKit
import UserNotifications

/// Listens to the microphone (also in the background) and turns speech into text,
/// fully on the iPhone, with Apple's SpeechAnalyzer.
@MainActor
final class Listener: ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing(String)
        case listening
        case paused(String)
    }

    private enum ListenError: Error {
        case permanent(String)
        case temporary(String)
    }

    @Published private(set) var status: Status = .idle
    /// True from Start listening until Stop listening, including pauses.
    @Published private(set) var isActive = false
    /// Words heard so far that may still change.
    @Published private(set) var liveText = ""
    @Published var message: String?

    /// Called with each finished phrase.
    var onPhrase: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var isRunning = false
    private var isRestarting = false
    private var failures = 0
    private var localeID = "en-US"
    private var askedForNotifications = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: audioSession, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            let began = type == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor in self?.interruption(began: began) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: audioSession, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        })
    }

    // MARK: - Start and stop

    func start(localeID: String) async {
        guard !isActive else { return }
        self.localeID = localeID
        isActive = true
        failures = 0
        message = nil
        status = .preparing("Getting ready…")

        guard await Listener.microphoneAllowed() else {
            fail("Say it better needs the microphone. Turn it on in Settings → Apps → Say it better.")
            return
        }
        guard await Listener.speechAllowed() else {
            fail("Say it better needs Speech Recognition. Turn it on in Settings → Apps → Say it better.")
            return
        }
        await askForNotificationsOnce()
        await startPipeline()
    }

    func stop() async {
        guard isActive else { return }
        isActive = false
        await tearDown()
        status = .idle
    }

    /// Call when the app comes back to the screen.
    func appBecameActive() {
        guard isActive, !isRunning, !isRestarting else { return }
        if case .paused = status {
            failures = 0
            Task { await startPipeline() }
        }
    }

    // MARK: - The listening pipeline

    private func startPipeline() async {
        guard isActive, !isRunning else { return }
        do {
            guard await SpeechTranscriber.isAvailable else {
                throw ListenError.permanent("This iPhone can't turn speech into text on the device.")
            }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) else {
                throw ListenError.permanent("That accent isn't available on this iPhone. Pick a different one.")
            }
            let transcriber = SpeechTranscriber(locale: locale,
                                                transcriptionOptions: [],
                                                reportingOptions: [.volatileResults],
                                                attributeOptions: [])

            let installed = await Set(SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
            if !installed.contains(locale.identifier(.bcp47)) {
                status = .preparing("Downloading the speech model. This happens once and needs internet…")
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            }
            guard isActive else { return }

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord,
                                         mode: .default,
                                         options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true)

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw ListenError.temporary("The speech model isn't ready yet.")
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (sequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
            self.analyzer = analyzer
            self.inputBuilder = builder

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.received(String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    self?.resultsStopped()
                }
            }

            try await analyzer.start(inputSequence: sequence)

            let input = engine.inputNode
            let micFormat = input.outputFormat(forBus: 0)
            guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
                throw ListenError.temporary("The microphone is busy right now.")
            }
            input.removeTap(onBus: 0)
            Listener.installTap(on: input, micFormat: micFormat, target: analyzerFormat, builder: builder)
            engine.prepare()
            try engine.start()

            isRunning = true
            failures = 0
            status = .listening
        } catch let error as ListenError {
            await tearDown()
            switch error {
            case .permanent(let text):
                fail(text)
            case .temporary(let text):
                await retry(after: text)
            }
        } catch {
            await tearDown()
            await retry(after: "Listening hit a problem.")
        }
    }

    /// Kept outside the main actor: the tap runs on the audio thread.
    nonisolated private static func installTap(on input: AVAudioInputNode,
                                               micFormat: AVAudioFormat,
                                               target: AVAudioFormat,
                                               builder: AsyncStream<AnalyzerInput>.Continuation) {
        let converter = BufferConverter()
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            guard let converted = try? converter.convert(buffer, to: target) else { return }
            builder.yield(AnalyzerInput(buffer: converted))
        }
    }

    private func received(_ text: String, isFinal: Bool) {
        if isFinal {
            liveText = ""
            let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty { onPhrase?(phrase) }
        } else {
            liveText = text
        }
    }

    private func tearDown() async {
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        inputBuilder?.finish()
        inputBuilder = nil
        if let analyzer {
            self.analyzer = nil
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                try? await analyzer.cancelAndFinishNow()
            }
        }
        if let task = resultsTask {
            resultsTask = nil
            await task.value
        }
        if !liveText.isEmpty {
            let leftover = liveText
            liveText = ""
            onPhrase?(leftover)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Recovering from interruptions

    private func interruption(began: Bool) {
        guard isActive else { return }
        if began {
            Task {
                await tearDown()
                status = .paused("Paused for a call or another app. It starts again when that ends.")
            }
        } else {
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                failures = 0
                await startPipeline()
            }
        }
    }

    private func resultsStopped() {
        guard isRunning else { return }
        restart()
    }

    private func restart() {
        guard isActive, isRunning, !isRestarting else { return }
        isRestarting = true
        Task {
            await tearDown()
            try? await Task.sleep(nanoseconds: 500_000_000)
            isRestarting = false
            await startPipeline()
        }
    }

    private func retry(after text: String) async {
        guard isActive else { return }
        failures += 1
        if failures > 3 {
            fail(text + " Tap Start listening to try again.")
            return
        }
        status = .preparing("Starting again…")
        try? await Task.sleep(nanoseconds: UInt64(failures) * 2_000_000_000)
        await startPipeline()
    }

    private func fail(_ text: String) {
        isActive = false
        status = .idle
        message = text
        notifyIfInBackground("Say it better stopped listening. Open the app to start again.")
    }

    // MARK: - Permissions and alerts

    nonisolated private static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    nonisolated private static func speechAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    private func askForNotificationsOnce() async {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func notifyIfInBackground(_ text: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "Say it better"
        content.body = text
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
