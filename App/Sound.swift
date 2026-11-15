import AVFoundation

/// Chiptune music and effects, synthesised at launch from square, triangle and noise waves.
/// There are no audio files.
final class Sound: ObservableObject {
    static let shared = Sound()

    enum Effect: CaseIterable {
        case tick, work, gain, fail, built, discover, levelUp, blocked, night, morning, habitable, lost
    }

    @Published var muted = UserDefaults.standard.bool(forKey: "muted") {
        didSet {
            UserDefaults.standard.set(muted, forKey: "muted")
            engine.mainMixerNode.outputVolume = muted ? 0 : 1
        }
    }

    private let engine = AVAudioEngine()
    private let music = AVAudioPlayerNode()
    private let effects = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Tune.rate, channels: 1)!
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]

    private init() {
        engine.attach(music)
        engine.attach(effects)
        engine.connect(music, to: engine.mainMixerNode, format: format)
        engine.connect(effects, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = muted ? 0 : 1
        for effect in Effect.allCases { buffers[effect] = buffer(Tune.effect(effect)) }
        // No sound is a fine way to fail: the game plays the same without it.
        guard (try? engine.start()) != nil else { return }
        music.scheduleBuffer(buffer(Tune.song), at: nil, options: .loops)
        music.play()
        effects.play()
    }

    func play(_ effect: Effect) {
        guard engine.isRunning, let buffer = buffers[effect] else { return }
        effects.scheduleBuffer(buffer, at: nil, options: .interrupts)
        effects.play()
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}

/// The notes themselves.
private enum Tune {
    static let rate = 44100.0

    enum Wave {
        case square(Double), triangle, noise
    }

    /// Mixes one note into `samples`. `pitch` is a MIDI note number.
    static func note(_ samples: inout [Float], at start: Double, _ wave: Wave, pitch: Double, seconds: Double,
                     volume: Double, fade: Double = 3) {
        let first = Int(start * rate), count = Int(seconds * rate)
        if samples.count < first + count { samples += [Float](repeating: 0, count: first + count - samples.count) }
        let frequency = 440 * pow(2, (pitch - 69) / 12)
        var hiss: UInt32 = 0x1234_5678
        var held = 0.0
        for index in 0..<count {
            let time = Double(index) / rate, phase = (time * frequency).truncatingRemainder(dividingBy: 1)
            let value: Double
            switch wave {
            case let .square(duty): value = phase < duty ? 1 : -1
            case .triangle: value = 4 * abs(phase - 0.5) - 1
            case .noise:
                // Held for a few samples, like the old noise channel.
                if index % 6 == 0 {
                    hiss = hiss &* 1_664_525 &+ 1_013_904_223
                    held = Double(hiss >> 16 & 0xffff) / 32768 - 1
                }
                value = held
            }
            // A quick attack so notes do not click, then a decay, then a short release.
            let shape = min(1, time / 0.004) * exp(-fade * time / seconds) * min(1, (seconds - time) / 0.01)
            samples[first + index] += Float(value * volume * shape)
        }
    }

    /// Eight slow bars in A minor, for an empty shore: a lonely lead over a quiet arpeggio.
    static let song: [Float] = {
        let eighth = 0.3125
        var samples: [Float] = []
        let chords: [(bass: Double, arp: [Double])] = [
            (45, [57, 64, 60, 64]), (41, [53, 60, 57, 60]), (48, [55, 60, 64, 60]), (40, [52, 59, 55, 59]),
        ]
        let lead: [[(Double, Int)]] = [
            [(76, 4), (72, 2), (69, 2)], [(69, 6), (0, 2)], [(67, 2), (72, 2), (76, 4)], [(74, 2), (71, 6)],
            [(69, 2), (72, 2), (76, 2), (81, 2)], [(79, 4), (77, 2), (72, 2)], [(76, 6), (74, 2)], [(71, 8)],
        ]
        for bar in 0..<8 {
            let chord = chords[bar % 4], start = Double(bar * 8) * eighth
            for step in 0..<8 {
                let time = start + Double(step) * eighth
                note(&samples, at: time, .square(0.125), pitch: chord.arp[step % 4], seconds: eighth * 0.9, volume: 0.035)
                if step % 2 == 1 { note(&samples, at: time, .noise, pitch: 0, seconds: 0.03, volume: 0.02, fade: 6) }
            }
            note(&samples, at: start, .triangle, pitch: chord.bass, seconds: eighth * 3, volume: 0.16, fade: 1)
            note(&samples, at: start + eighth * 4, .triangle, pitch: chord.bass, seconds: eighth * 2, volume: 0.16, fade: 1)
            note(&samples, at: start + eighth * 6, .triangle, pitch: chord.bass + 7, seconds: eighth * 2, volume: 0.14, fade: 1)
            var step = 0
            for (pitch, length) in lead[bar] {
                if pitch > 0 {
                    note(&samples, at: start + Double(step) * eighth, .square(0.5), pitch: pitch,
                         seconds: Double(length) * eighth * 0.95, volume: 0.06, fade: 2.2)
                }
                step += length
            }
        }
        return samples
    }()

    /// A run of notes, each `seconds` long.
    private static func run(_ pitches: [Double], _ seconds: Double, _ wave: Wave = .square(0.5), volume: Double = 0.14) -> [Float] {
        var samples: [Float] = []
        for (index, pitch) in pitches.enumerated() {
            note(&samples, at: Double(index) * seconds, wave, pitch: pitch, seconds: seconds * 1.2, volume: volume)
        }
        return samples
    }

    static func effect(_ effect: Sound.Effect) -> [Float] {
        switch effect {
        case .tick: run([84], 0.04, .square(0.25), volume: 0.1)
        case .work: run([60, 55], 0.06, .noise, volume: 0.16)
        case .gain: run([76, 83], 0.07)
        case .fail: run([58, 52], 0.13, .square(0.25))
        case .built: run([64, 69, 76], 0.09)
        case .discover: run([69, 72, 76, 81, 88], 0.1)
        case .levelUp: run([72, 76, 79, 84, 79, 84], 0.07, .square(0.25))
        case .blocked: run([46, 46], 0.07, .square(0.25))
        case .night: run([76, 72, 69, 64], 0.22, .triangle, volume: 0.22)
        case .morning: run([64, 69, 72, 76], 0.16, .triangle, volume: 0.22)
        case .habitable: run([72, 72, 76, 79, 84, 79, 84, 88], 0.13)
        case .lost: run([64, 60, 57, 52, 45], 0.26, .square(0.25))
        }
    }
}
