import Foundation
@preconcurrency internal import GameKit
import UIKit

extension GameCenterManager {
    func refreshLeaderboard() {
        guard isAuthenticated else { return }
        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { [weak self] leaderboards, error in
            let boxedLeaderboards = UncheckedSendable(value: leaderboards)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    return
                }
                guard let leaderboard = boxedLeaderboards.value?.first else { return }
                self.leaderboardTitle = leaderboard.title
                leaderboard.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime) { localEntry, _, error in
                    let score = localEntry?.score
                    let rank = localEntry?.rank
                    let entryErrorDescription = error?.localizedDescription
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let entryErrorDescription {
                            self.lastError = entryErrorDescription
                            return
                        }
                        if let score {
                            self.setLocalEloRating(Int(score))
                        }
                        self.playerRank = rank
                    }
                }
            }
        }
    }

    var localEloRating: Int {
        let stored = UserDefaults.standard.integer(forKey: eloStorageKey)
        return stored == 0 ? defaultEloRating : stored
    }

    func eloRating(for player: GKPlayer?) -> Int {
        guard let player else { return localEloRating }
        if player.gamePlayerID == GKLocalPlayer.local.gamePlayerID {
            return localEloRating
        }
        return playerRatingCache[player.gamePlayerID] ?? defaultEloRating
    }

    func avatarImage(for player: GKPlayer?) -> UIImage? {
        guard let player else { return nil }
        if let cached = playerAvatarCache[player.gamePlayerID] {
            return cached
        }
        loadAvatar(for: player)
        return nil
    }

    func projectedEloChange(for match: GKTurnBasedMatch, winner: Player?, isDraw: Bool) -> EloChange? {
        guard let localColor = localPlayerColor(in: match) else { return nil }
        let localID = GKLocalPlayer.local.gamePlayerID
        let opponent = match.participants.first(where: { $0.player?.gamePlayerID != localID && $0.player != nil })

        let localRating = localEloRating
        let opponentRating = eloRating(for: opponent?.player)

        let score: Double
        if isDraw {
            score = 0.5
        } else if let winner, winner == localColor {
            score = 1.0
        } else if winner != nil {
            score = 0.0
        } else {
            return nil
        }

        let localUpdated = EloCalculator.updatedRating(
            current: localRating,
            opponent: opponentRating,
            score: score,
            kFactor: eloKFactor
        )
        let opponentUpdated = EloCalculator.updatedRating(
            current: opponentRating,
            opponent: localRating,
            score: 1.0 - score,
            kFactor: eloKFactor
        )

        return EloChange(
            localDelta: localUpdated - localRating,
            opponentDelta: opponentUpdated - opponentRating,
            localRating: localRating,
            opponentRating: opponentRating
        )
    }

    func refreshRatings(for match: GKTurnBasedMatch) {
        let players = match.participants.compactMap { $0.player }
        refreshRatings(for: players)
    }

    func updateEloIfNeeded(for match: GKTurnBasedMatch) {
        let localID = GKLocalPlayer.local.gamePlayerID
        guard let localParticipant = match.participants.first(where: { $0.player?.gamePlayerID == localID }) else {
            return
        }
        guard let score = outcomeScore(for: localParticipant.matchOutcome) else { return }

        let opponent = match.participants.first(where: { $0.player?.gamePlayerID != localID && $0.player != nil })
        let opponentRating = eloRating(for: opponent?.player)
        let currentRating = localEloRating
        let newRating = EloCalculator.updatedRating(
            current: currentRating,
            opponent: opponentRating,
            score: score,
            kFactor: eloKFactor
        )

        setLocalEloRating(newRating)
        var processed = processedMatchIDs
        processed.insert(match.matchID)
        processedMatchIDs = processed
        submitScore(newRating)
    }
}

private extension GameCenterManager {
    func refreshRatings(for players: [GKPlayer]) {
        guard isAuthenticated else { return }
        guard !players.isEmpty else { return }
        guard !isRefreshingRatings else { return }
        isRefreshingRatings = true

        let boxedPlayers = UncheckedSendable(value: players)
        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { [weak self] leaderboards, error in
            let boxedLeaderboards = UncheckedSendable(value: leaderboards)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.isRefreshingRatings = false }
                if let errorDescription {
                    self.lastError = errorDescription
                    return
                }
                guard let leaderboard = boxedLeaderboards.value?.first else { return }
                let playersValue = boxedPlayers.value
                leaderboard.loadEntries(for: playersValue, timeScope: .allTime) { localEntry, entries, error in
                    let entryErrorDescription = error?.localizedDescription
                    let localScore = localEntry?.score
                    let entryScores = entries?.map { (id: $0.player.gamePlayerID, score: Int($0.score)) }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let entryErrorDescription {
                            self.lastError = entryErrorDescription
                            return
                        }
                        if let localScore {
                            self.setLocalEloRating(Int(localScore))
                        }
                        entryScores?.forEach { entry in
                            self.playerRatingCache[entry.id] = entry.score
                        }
                    }
                }
            }
        }
    }

    func setLocalEloRating(_ value: Int) {
        UserDefaults.standard.set(value, forKey: eloStorageKey)
        playerScore = value
    }

    func loadAvatar(for player: GKPlayer) {
        let id = player.gamePlayerID
        guard !loadingAvatars.contains(id) else { return }
        loadingAvatars.insert(id)

        player.loadPhoto(for: .normal) { [weak self] image, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadingAvatars.remove(id)
                guard let image else { return }
                self.playerAvatarCache[id] = image
            }
        }
    }

    func submitScore(_ score: Int) {
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboardID]
        ) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                self.refreshLeaderboard()
            }
        }
    }

    func outcomeScore(for outcome: GKTurnBasedMatch.Outcome) -> Double? {
        switch outcome {
        case .won:
            return 1.0
        case .lost, .quit, .timeExpired:
            return 0.0
        case .tied:
            return 0.5
        default:
            return nil
        }
    }
}

private enum EloCalculator {
    static func expectedScore(current: Int, opponent: Int) -> Double {
        let exponent = Double(opponent - current) / 400.0
        return 1.0 / (1.0 + pow(10.0, exponent))
    }

    static func updatedRating(current: Int, opponent: Int, score: Double, kFactor: Int) -> Int {
        let expected = expectedScore(current: current, opponent: opponent)
        let delta = Double(kFactor) * (score - expected)
        return Int(round(Double(current) + delta))
    }
}
