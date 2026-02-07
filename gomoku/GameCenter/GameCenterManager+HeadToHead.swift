import Foundation
@preconcurrency internal import GameKit

extension GameCenterManager {
    func refreshHeadToHead(for match: GKTurnBasedMatch) {
        guard isAuthenticated else {
            headToHeadSummary = nil
            return
        }

        let localID = GKLocalPlayer.local.gamePlayerID
        guard let opponentID = opponentPlayerID(in: match) else {
            headToHeadSummary = nil
            return
        }

        headToHeadSummary = nil
        let targetMatchID = match.matchID
        let store = headToHeadStore

        Task {
            do {
                let summary = try await store.fetchSummary(
                    localPlayerID: localID,
                    opponentPlayerID: opponentID
                )
                _ = await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.currentMatch?.matchID == targetMatchID else { return }
                    self.headToHeadSummary = summary
                }
            } catch {
                _ = await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.currentMatch?.matchID == targetMatchID else { return }
                    self.headToHeadSummary = nil
                }
            }
        }
    }

    func updateHeadToHeadIfNeeded(for match: GKTurnBasedMatch) {
        let matchID = match.matchID
        guard !syncingHeadToHeadMatchIDs.contains(matchID) else { return }

        let localID = GKLocalPlayer.local.gamePlayerID
        guard let localParticipant = match.participants.first(where: { $0.player?.gamePlayerID == localID }),
              let result = headToHeadResult(for: localParticipant.matchOutcome),
              let opponentID = opponentPlayerID(in: match) else {
            return
        }

        syncingHeadToHeadMatchIDs.insert(matchID)
        let store = headToHeadStore

        Task {
            do {
                let summary = try await store.recordResult(
                    matchID: matchID,
                    localPlayerID: localID,
                    opponentPlayerID: opponentID,
                    result: result
                )
                _ = await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.syncingHeadToHeadMatchIDs.remove(matchID)
                    var processed = self.processedHeadToHeadMatchIDs
                    processed.insert(matchID)
                    self.processedHeadToHeadMatchIDs = processed

                    if self.currentMatch?.matchID == matchID {
                        self.headToHeadSummary = summary
                    }
                }
            } catch {
                _ = await MainActor.run { [weak self] in
                    self?.syncingHeadToHeadMatchIDs.remove(matchID)
                }
                // Best-effort sync: transient CloudKit failures should not block gameplay.
            }
        }
    }
}

private extension GameCenterManager {
    func headToHeadResult(for outcome: GKTurnBasedMatch.Outcome) -> HeadToHeadMatchResult? {
        switch outcome {
        case .won:
            return .localWin
        case .lost, .quit, .timeExpired:
            return .localLoss
        case .tied:
            return .draw
        default:
            return nil
        }
    }

    func opponentPlayerID(in match: GKTurnBasedMatch) -> String? {
        let localID = GKLocalPlayer.local.gamePlayerID
        return match.participants.first { participant in
            participant.player?.gamePlayerID != localID && participant.player != nil
        }?.player?.gamePlayerID
    }
}
