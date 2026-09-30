import AVFoundation
import os

private let log = Logger(subsystem: "dev.unsaid", category: "audio")

/// Something to play: a dictation's WAV (read from Wispr when played) or a kept clip.
enum Playable {
    case data(Data)
    case file(URL)
}

/// Plays one or more recordings back to back, with a short pause between them.
final class Player: NSObject, AVAudioPlayerDelegate {
    private var queue: [Playable] = []
    private var current: AVAudioPlayer?

    func play(_ items: [Playable]) {
        current?.stop()
        queue = items
        next()
    }

    private func next() {
        guard !queue.isEmpty else { current = nil; return }
        let item = queue.removeFirst()
        do {
            let p: AVAudioPlayer
            switch item {
            case .data(let d): p = try AVAudioPlayer(data: d)
            case .file(let u): p = try AVAudioPlayer(contentsOf: u)
            }
            p.delegate = self
            current = p
            p.play()
            log.info("playing \(p.duration, format: .fixed(precision: 1)) s")
        } catch {
            log.error("can't play: \(error.localizedDescription)")
            next()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.next() }
    }
}

/// Cuts a stretch of a call recording (Wispr's `upload.ogg`, Opus) into a small mono AAC file.
enum ClipCutter {
    static let padMs: Double = 250

    static func cut(_ audio: URL, fromMs: Double, toMs: Double, into out: URL) throws {
        let file = try AVAudioFile(forReading: audio)
        let format = file.processingFormat
        let rate = format.sampleRate
        let start = max(0, AVAudioFramePosition((fromMs - padMs) / 1000 * rate))
        let end = min(file.length, AVAudioFramePosition((toMs + padMs) / 1000 * rate))
        guard end > start, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(end - start)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        file.framePosition = start
        try file.read(into: buffer, frameCount: AVAudioFrameCount(end - start))

        // Wispr's two channels aren't cleanly mic and call audio, so mix them down.
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength),
              let src = buffer.floatChannelData, let dst = mono.floatChannelData else { throw CocoaError(.fileReadUnknown) }
        mono.frameLength = buffer.frameLength
        let channels = Int(format.channelCount)
        for i in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for c in 0..<channels { sum += src[c][i] }
            dst[0][i] = sum / Float(channels)
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000]
        let output = try AVAudioFile(forWriting: out, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try output.write(from: mono)
    }
}
