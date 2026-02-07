import Foundation
@preconcurrency internal import GameKit
import UIKit

extension GameCenterManager: GameCenterEventListenerDelegate {
    func gameCenterDidReceiveTurnEvent(for match: GKTurnBasedMatch, didBecomeActive: Bool) {
        acceptInviteIfNeeded(for: match)
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

extension GameCenterManager: GKTurnBasedMatchmakerViewControllerDelegate {
    nonisolated func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
        let boxedViewController = UncheckedSendable(value: viewController)
        Task { @MainActor in
            boxedViewController.value.dismiss(animated: true)
        }
    }

    nonisolated func turnBasedMatchmakerViewController(
        _ viewController: GKTurnBasedMatchmakerViewController,
        didFailWithError error: Error
    ) {
        let boxedViewController = UncheckedSendable(value: viewController)
        let errorDescription = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastError = errorDescription
            boxedViewController.value.dismiss(animated: true)
        }
    }

    nonisolated func turnBasedMatchmakerViewController(
        _ viewController: GKTurnBasedMatchmakerViewController,
        didFind match: GKTurnBasedMatch
    ) {
        let boxedViewController = UncheckedSendable(value: viewController)
        let boxedMatch = UncheckedSendable(value: match)
        Task { @MainActor [weak self] in
            guard let self else { return }
            boxedViewController.value.dismiss(animated: true)
            self.pendingAutoMatchID = boxedMatch.value.matchID
            self.pendingAutoMatch = boxedMatch.value
            self.handleAutoMatchResult(boxedMatch.value)
        }
    }
}
