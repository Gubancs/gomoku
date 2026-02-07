import Foundation
@preconcurrency internal import GameKit

@MainActor
protocol GameCenterEventListenerDelegate: AnyObject {
    func gameCenterDidReceiveTurnEvent(for match: GKTurnBasedMatch, didBecomeActive: Bool)
    func gameCenterDidMatchEnd(_ match: GKTurnBasedMatch)
}

/// Listens for Game Center turn updates and forwards to the manager.
final class GameCenterEventListener: NSObject, GKLocalPlayerListener {
    weak var delegate: GameCenterEventListenerDelegate?

    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        let boxedMatch = UncheckedSendable(value: match)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.gameCenterDidReceiveTurnEvent(for: boxedMatch.value, didBecomeActive: didBecomeActive)
        }
    }

    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        let boxedMatch = UncheckedSendable(value: match)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.gameCenterDidMatchEnd(boxedMatch.value)
        }
    }
}
