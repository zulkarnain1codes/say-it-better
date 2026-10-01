import AVFoundation
import Foundation

/// Hands the source buffer to AVAudioConverter exactly once.
private final class OneShotInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        let next = buffer
        buffer = nil
        return next
    }
}

/// Converts microphone buffers to the format the speech model asks for.
/// Use one instance per listening run, only from the audio tap.
final class BufferConverter {
    enum Failure: Error {
        case cannotCreateConverter
        case cannotCreateBuffer
        case conversionFailed
    }

    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format

        // The tap may reuse its buffer, so always hand on a copy we own.
        guard inputFormat != format else {
            guard let copy = buffer.copy() as? AVAudioPCMBuffer else { throw Failure.cannotCreateBuffer }
            return copy
        }

        if converter == nil || converter?.inputFormat != inputFormat || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw Failure.cannotCreateConverter }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw Failure.cannotCreateBuffer
        }

        var error: NSError?
        let input = OneShotInput(buffer)
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            let next = input.take()
            inputStatus.pointee = next == nil ? .noDataNow : .haveData
            return next
        }
        guard status != .error else { throw Failure.conversionFailed }
        return output
    }
}
