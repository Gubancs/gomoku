import Foundation
internal import GameKit

protocol GameCenterEventListenerDelegate: AnyObject {
    func gameCenterDidReceiveTurnEvent()
}

/// Listens for Game Center turn updates and forwards to the manager.
final class GameCenterEventListener: NSObject, GKLocalPlayerListener {
    weak var delegate: GameCenterEventListenerDelegate?

    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        delegate?.gameCenterDidReceiveTurnEvent()
    }

    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        delegate?.gameCenterDidReceiveTurnEvent()
    }
}
