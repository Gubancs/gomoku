import AudioToolbox
import AVFoundation

enum SoundEffects {
    private static let moveSound: SystemSoundID = 1104
    private static var isPrepared = false

    static func playMove(for player: Player) {
        AudioServicesPlaySystemSound(moveSound)
    }

    static func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
