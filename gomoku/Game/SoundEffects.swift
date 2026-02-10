import AudioToolbox
import AVFoundation
import Foundation

enum SoundEffects {
    static let volumeStorageKey = "soundVolume"
    static let defaultVolume: Double = 0.85

    private static var isPrepared = false
    private static let moveSound: SystemSoundID = 1104
    private static let sampleRate: Double = 44_100
    private static let soundQueue = DispatchQueue(label: "gomoku.soundeffects.queue")
    private static var engine: AVAudioEngine?
    private static var playerNode: AVAudioPlayerNode?
    private static var audioFormat: AVAudioFormat?

    static func clampedVolume(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func setVolume(_ value: Double) {
        let volume = clampedVolume(value)
        UserDefaults.standard.set(volume, forKey: volumeStorageKey)
    }

    static func currentVolume() -> Double {
        let stored = UserDefaults.standard.object(forKey: volumeStorageKey) as? Double
        return clampedVolume(stored ?? defaultVolume)
    }

    static func playMove(for player: Player) {
        _ = player
        guard currentVolume() > 0 else { return }
        AudioServicesPlaySystemSound(moveSound)
    }

    static func playMatchStart() {
        soundQueue.async {
            prepareIfNeededOnQueue()
            scheduleTone(frequency: 700, duration: 0.07, gain: 0.75)
            scheduleTone(frequency: 900, duration: 0.09, gain: 0.95)
        }
    }

    static func playVictory() {
        soundQueue.async {
            prepareIfNeededOnQueue()
            scheduleTone(frequency: 740, duration: 0.08, gain: 0.8)
            scheduleTone(frequency: 988, duration: 0.11, gain: 0.95)
            scheduleTone(frequency: 1319, duration: 0.13, gain: 1.0)
        }
    }

    static func playDefeat() {
        soundQueue.async {
            prepareIfNeededOnQueue()
            scheduleTone(frequency: 520, duration: 0.08, gain: 0.78)
            scheduleTone(frequency: 438, duration: 0.10, gain: 0.9)
            scheduleTone(frequency: 349, duration: 0.13, gain: 0.96)
        }
    }

    static func playClockTick() {
        guard currentVolume() > 0 else { return }
        soundQueue.async {
            prepareIfNeededOnQueue()
            scheduleTone(frequency: 1200, duration: 0.035, gain: 0.6)
        }
    }

    static func prepare() {
        soundQueue.async {
            prepareIfNeededOnQueue()
        }
    }

    private static func prepareIfNeededOnQueue() {
        guard !isPrepared else { return }
        isPrepared = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            isPrepared = false
            return
        }
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try? engine.start()

        Self.engine = engine
        Self.playerNode = playerNode
        Self.audioFormat = format
    }

    private static func scheduleTone(frequency: Double, duration: Double, gain: Float) {
        guard let playerNode, let audioFormat else { return }
        let volume = Float(currentVolume())
        if volume <= 0 { return }

        let frames = AVAudioFrameCount(max(1, Int(duration * sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let amplitude = gain * volume
        let totalFrames = Int(frames)
        guard let channelData = buffer.floatChannelData?[0] else { return }

        for frame in 0..<totalFrames {
            let phase = 2 * Double.pi * frequency * Double(frame) / sampleRate
            // Very short fade-in/out to avoid click artifacts.
            let edge = min(frame, totalFrames - 1 - frame)
            let fadeFrames = max(1, Int(sampleRate * 0.004))
            let envelope = min(1.0, Double(edge) / Double(fadeFrames))
            channelData[frame] = Float(sin(phase)) * amplitude * Float(envelope)
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
}
