import Foundation
@preconcurrency internal import GameKit

extension GameCenterManager: GameCenterEventListenerDelegate {
    func gameCenterDidReceiveTurnEvent(for match: GKTurnBasedMatch, didBecomeActive: Bool) {
        acceptInviteIfNeeded(for: match)
        if currentMatch?.matchID == match.matchID {
            currentMatch = match
        }
        if isMatchReady(match), (isFindingMatch || currentMatch == nil || didBecomeActive) {
            handleMatchSelected(match)
        }
        loadMatches()
    }

    func gameCenterDidMatchEnd(_ match: GKTurnBasedMatch) {
        if currentMatch?.matchID == match.matchID {
            currentMatch = match
        }
        loadMatches()
    }
}
