import Foundation
internal import GameKit
import UIKit
import Combine

/// Central coordinator for Game Center authentication, matches, and leaderboards.
@MainActor
final class GameCenterManager: NSObject, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var activeMatches: [GKTurnBasedMatch] = []
    @Published var currentMatch: GKTurnBasedMatch?
    @Published var playerScore: Int?
    @Published var playerRank: Int?
    @Published var leaderboardTitle: String?
    @Published var lastError: String?
    @Published var isFindingMatch: Bool = false
    @Published var isAwaitingRematch: Bool = false
    @Published var needsAuthentication: Bool = false
    @Published var isDebugMatchActive: Bool = false
    @Published var finishedMatchesCount: Int = 0
    @Published var isPurgingFinishedMatches: Bool = false

    let leaderboardID: String

    private let eventListener = GameCenterEventListener()
    private let eloStorageKey = "gomoku.elo.local"
    private let processedMatchesKey = "gomoku.elo.processedMatches"
    private let defaultEloRating = 1200
    private let eloKFactor = 32
    private var shouldPresentAuthUI: Bool = false
    private var pendingAuthViewController: UIViewController?
    private var pendingAutoMatchID: String?
    private var pendingAutoMatch: GKTurnBasedMatch?
    private var pendingRematchID: String?
    @Published private var playerRatingCache: [String: Int] = [:]
    @Published private var playerAvatarCache: [String: UIImage] = [:]
    private var isRefreshingRatings: Bool = false
    private var loadingAvatars: Set<String> = []

    struct EloChange {
        let localDelta: Int
        let opponentDelta: Int
        let localRating: Int
        let opponentRating: Int
    }

    init(leaderboardID: String = "gomoku.points") {
        self.leaderboardID = leaderboardID
        super.init()
        eventListener.delegate = self
    }

    func refreshAuthenticationState() {
        setAuthenticateHandler(shouldPresentUI: false)
    }

    func beginAuthentication() {
        shouldPresentAuthUI = true
        if let pendingAuthViewController {
            present(pendingAuthViewController)
            self.pendingAuthViewController = nil
        } else {
            setAuthenticateHandler(shouldPresentUI: true)
        }
    }

    private func setAuthenticateHandler(shouldPresentUI: Bool) {
        shouldPresentAuthUI = shouldPresentUI
        let localPlayer = GKLocalPlayer.local
        localPlayer.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }

            if let viewController {
                self.pendingAuthViewController = viewController
                self.needsAuthentication = true
                if self.shouldPresentAuthUI {
                    self.present(viewController)
                    self.pendingAuthViewController = nil
                }
                return
            }

            if let error {
                self.lastError = error.localizedDescription
            }

            self.isAuthenticated = localPlayer.isAuthenticated
            self.needsAuthentication = !self.isAuthenticated
            if self.isAuthenticated {
                self.pendingAuthViewController = nil
                GKLocalPlayer.local.register(self.eventListener)
                self.loadMatches()
                self.refreshLeaderboard()
            }
        }
    }

    func loadMatches() {
        guard isAuthenticated else { return }
        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    return
                }
                let allMatches = matches ?? []
                let finishedMatches = allMatches.filter { $0.status == .ended }
                self?.finishedMatchesCount = finishedMatches.count
                self?.activeMatches = allMatches.filter { $0.status != .ended }
                if let currentID = self?.currentMatch?.matchID,
                   let updated = matches?.first(where: { $0.matchID == currentID }) {
                    self?.currentMatch = updated
                }
                self?.processFinishedMatches(allMatches)
                self?.updateAutoMatchStatus(with: allMatches)
                self?.updateRematchStatus(with: allMatches)
            }
        }
    }

    func refreshLeaderboard() {
        guard isAuthenticated else { return }
        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { [weak self] leaderboards, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    return
                }
                guard let leaderboard = leaderboards?.first else { return }
                self?.leaderboardTitle = leaderboard.title
                leaderboard.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime) { localEntry, _, error in
                    Task { @MainActor in
                        if let error {
                            self?.lastError = error.localizedDescription
                            return
                        }
                        if let score = localEntry?.score {
                            self?.setLocalEloRating(Int(score))
                        }
                        self?.playerRank = localEntry?.rank
                    }
                }
            }
        }
    }

    func startMatchmaking() {
        guard isAuthenticated else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2

        isFindingMatch = true
        pendingAutoMatchID = nil
        pendingAutoMatch = nil

        GKTurnBasedMatch.find(for: request) { [weak self] match, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    self?.isFindingMatch = false
                    return
                }

                guard let match else {
                    self?.isFindingMatch = false
                    return
                }

                self?.pendingAutoMatchID = match.matchID
                self?.pendingAutoMatch = match
                self?.handleAutoMatchResult(match)
            }
        }
    }

    func cancelMatchmaking() {
        guard isFindingMatch else { return }
        isFindingMatch = false

        if let pendingAutoMatch {
            pendingAutoMatch.remove { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.lastError = error.localizedDescription
                        self?.loadMatches()
                        return
                    }
                    self?.loadMatches()
                }
            }
            self.pendingAutoMatch = nil
            self.pendingAutoMatchID = nil
            return
        }

        guard let pendingID = pendingAutoMatchID else { return }
        pendingAutoMatchID = nil

        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    self?.loadMatches()
                    return
                }
                guard let match = matches?.first(where: { $0.matchID == pendingID }) else { return }
                match.remove { [weak self] error in
                    Task { @MainActor in
                        if let error {
                            self?.lastError = error.localizedDescription
                        }
                        self?.pendingAutoMatch = nil
                        self?.loadMatches()
                    }
                }
            }
        }
    }

    func handleMatchSelected(_ match: GKTurnBasedMatch) {
        currentMatch = match
        isFindingMatch = false
        isAwaitingRematch = false
        pendingAutoMatchID = nil
        pendingAutoMatch = nil
        pendingRematchID = nil
        refreshRatings(for: match)
    }

    func loadState(from match: GKTurnBasedMatch) -> GameState? {
        guard let data = match.matchData, !data.isEmpty else { return nil }
        return GameState.decoded(from: data)
    }

    func localPlayerColor(in match: GKTurnBasedMatch) -> Player? {
        guard let index = localParticipantIndex(in: match) else { return nil }
        return index == 0 ? .black : .white
    }

    func isLocalPlayersTurn(in match: GKTurnBasedMatch) -> Bool {
        guard let current = match.currentParticipant?.player?.gamePlayerID else { return false }
        return current == GKLocalPlayer.local.gamePlayerID
    }

    var isCurrentMatchReady: Bool {
        guard let match = currentMatch else { return false }
        return isMatchReady(match)
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

    func submitTurn(game: GomokuGame, match: GKTurnBasedMatch) {
        guard let data = game.makeState().encoded() else { return }

        if let winner = game.winner {
            finishMatch(match, data: data, winner: winner)
            return
        }

        if game.isDraw {
            finishMatch(match, data: data, winner: nil)
            return
        }

        guard let nextParticipant = nextActiveParticipant(after: match.currentParticipant, in: match) else { return }
        match.endTurn(
            withNextParticipants: [nextParticipant],
            turnTimeout: GKTurnTimeoutDefault,
            match: data,
            completionHandler: { [weak self] (error: Error?) in
                Task { @MainActor in
                    if let error {
                        self?.lastError = error.localizedDescription
                        return
                    }
                    self?.loadMatches()
                }
            }
        )
    }

    func resignCurrentMatch(using game: GomokuGame, shouldClearCurrentMatch: Bool = true, completion: ((Bool) -> Void)? = nil) {
        guard let match = currentMatch else { return }
        let data = game.makeState().encoded() ?? Data()

        if isLocalPlayersTurn(in: match),
           let nextParticipant = nextActiveParticipant(after: match.currentParticipant, in: match) {
            match.participantQuitInTurn(
                with: .lost,
                nextParticipants: [nextParticipant],
                turnTimeout: GKTurnTimeoutDefault,
                match: data
            ) { [weak self] (error: Error?) in
                Task { @MainActor in
                    if let error {
                        self?.lastError = error.localizedDescription
                        completion?(false)
                        return
                    }
                    if shouldClearCurrentMatch {
                        self?.currentMatch = nil
                    }
                    self?.loadMatches()
                    completion?(true)
                }
            }
        } else {
            match.participantQuitOutOfTurn(with: .lost) { [weak self] (error: Error?) in
                Task { @MainActor in
                    if let error {
                        self?.lastError = error.localizedDescription
                        completion?(false)
                        return
                    }
                    if shouldClearCurrentMatch {
                        self?.currentMatch = nil
                    }
                    self?.loadMatches()
                    completion?(true)
                }
            }
        }
    }

    func requestRematch(for match: GKTurnBasedMatch) {
        isAwaitingRematch = true
        pendingRematchID = nil

        match.rematch { [weak self] newMatch, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    self?.isAwaitingRematch = false
                    return
                }

                guard let newMatch else {
                    self?.isAwaitingRematch = false
                    return
                }

                if self?.isMatchReady(newMatch) == true {
                    self?.currentMatch = newMatch
                    self?.isAwaitingRematch = false
                    self?.pendingRematchID = nil
                    self?.refreshRatings(for: newMatch)
                    self?.loadMatches()
                } else {
                    self?.pendingRematchID = newMatch.matchID
                    self?.isAwaitingRematch = true
                    self?.loadMatches()
                }
            }
        }
    }

    func purgeFinishedMatches() {
        guard isAuthenticated else { return }
        guard !isPurgingFinishedMatches else { return }
        isPurgingFinishedMatches = true

        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    self?.isPurgingFinishedMatches = false
                    return
                }

                let finished = (matches ?? []).filter { $0.status == .ended }
                guard !finished.isEmpty else {
                    self?.isPurgingFinishedMatches = false
                    self?.loadMatches()
                    return
                }

                var remaining = finished.count
                for match in finished {
                    match.remove { [weak self] error in
                        Task { @MainActor in
                            if let error {
                                self?.lastError = error.localizedDescription
                            }
                            remaining -= 1
                            if remaining <= 0 {
                                self?.isPurgingFinishedMatches = false
                                self?.loadMatches()
                            }
                        }
                    }
                }
            }
        }
    }

    private func finishMatch(_ match: GKTurnBasedMatch, data: Data, winner: Player?) {
        let participants = match.participants
        if let winner {
            for (index, participant) in participants.enumerated() {
                let isWinner = (winner == .black && index == 0) || (winner == .white && index == 1)
                participant.matchOutcome = isWinner ? .won : .lost
            }
        } else {
            participants.forEach { $0.matchOutcome = .tied }
        }

        match.endMatchInTurn(withMatch: data) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    return
                }
                self?.loadMatches()
            }
        }
    }

    private func setLocalEloRating(_ value: Int) {
        UserDefaults.standard.set(value, forKey: eloStorageKey)
        playerScore = value
    }

    private func loadAvatar(for player: GKPlayer) {
        let id = player.gamePlayerID
        guard !loadingAvatars.contains(id) else { return }
        loadingAvatars.insert(id)

        player.loadPhoto(for: .normal) { [weak self] image, _ in
            Task { @MainActor in
                self?.loadingAvatars.remove(id)
                guard let image else { return }
                self?.playerAvatarCache[id] = image
            }
        }
    }

    private func submitScore(_ score: Int) {
        let gkScore = GKScore(leaderboardIdentifier: leaderboardID)
        gkScore.value = Int64(score)
        GKScore.report([gkScore]) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                    return
                }
                self?.refreshLeaderboard()
            }
        }
    }

    private func localParticipantIndex(in match: GKTurnBasedMatch) -> Int? {
        match.participants.firstIndex { participant in
            participant.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        }
    }

    private func nextActiveParticipant(after current: GKTurnBasedParticipant?, in match: GKTurnBasedMatch) -> GKTurnBasedParticipant? {
        let participants = match.participants
        guard !participants.isEmpty else { return nil }

        let startIndex: Int
        if let current,
           let currentIndex = participants.firstIndex(where: { $0.player?.gamePlayerID == current.player?.gamePlayerID }) {
            startIndex = currentIndex
        } else if let localIndex = localParticipantIndex(in: match) {
            startIndex = localIndex
        } else {
            startIndex = 0
        }

        for offset in 1...participants.count {
            let index = (startIndex + offset) % participants.count
            let participant = participants[index]
            if participant.status == .active || participant.status == .invited {
                return participant
            }
        }

        return nil
    }

    private func handleAutoMatchResult(_ match: GKTurnBasedMatch) {
        if isMatchReady(match) {
            currentMatch = match
            pendingAutoMatchID = nil
            isFindingMatch = false
            refreshRatings(for: match)
            loadMatches()
        } else {
            isFindingMatch = true
            loadMatches()
        }
    }

    private func updateAutoMatchStatus(with matches: [GKTurnBasedMatch]) {
        guard let pendingID = pendingAutoMatchID else { return }
        guard let pendingMatch = matches.first(where: { $0.matchID == pendingID }) else {
            pendingAutoMatchID = nil
            pendingAutoMatch = nil
            isFindingMatch = false
            return
        }

        if isMatchReady(pendingMatch) {
            currentMatch = pendingMatch
            pendingAutoMatchID = nil
            pendingAutoMatch = nil
            isFindingMatch = false
            refreshRatings(for: pendingMatch)
        } else {
            isFindingMatch = true
        }
    }

    private func updateRematchStatus(with matches: [GKTurnBasedMatch]) {
        guard let pendingID = pendingRematchID else { return }
        guard let pendingMatch = matches.first(where: { $0.matchID == pendingID }) else {
            pendingRematchID = nil
            isAwaitingRematch = false
            return
        }

        if isMatchReady(pendingMatch) {
            currentMatch = pendingMatch
            pendingRematchID = nil
            isAwaitingRematch = false
            refreshRatings(for: pendingMatch)
        } else {
            isAwaitingRematch = true
        }
    }

    private func isMatchReady(_ match: GKTurnBasedMatch) -> Bool {
        if match.status == .matching {
            return false
        }
        let playerCount = match.participants.filter { $0.player != nil }.count
        return playerCount >= 2
    }

    private func refreshRatings(for match: GKTurnBasedMatch) {
        let players = match.participants.compactMap { $0.player }
        refreshRatings(for: players)
    }

    private func refreshRatings(for players: [GKPlayer]) {
        guard isAuthenticated else { return }
        guard !players.isEmpty else { return }
        guard !isRefreshingRatings else { return }
        isRefreshingRatings = true

        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { [weak self] leaderboards, error in
            Task { @MainActor in
                defer { self?.isRefreshingRatings = false }
                if let error {
                    self?.lastError = error.localizedDescription
                    return
                }
                guard let leaderboard = leaderboards?.first else { return }
                leaderboard.loadEntries(for: players, timeScope: .allTime) { localEntry, entries, error in
                    Task { @MainActor in
                        if let error {
                            self?.lastError = error.localizedDescription
                            return
                        }
                        if let localEntry {
                            self?.setLocalEloRating(Int(localEntry.score))
                        }
                        entries?.forEach { entry in
                            self?.playerRatingCache[entry.player.gamePlayerID] = Int(entry.score)
                        }
                    }
                }
            }
        }
    }

    private func processFinishedMatches(_ matches: [GKTurnBasedMatch]) {
        guard isAuthenticated else { return }
        let processed = processedMatchIDs
        for match in matches where match.status == .ended {
            if processed.contains(match.matchID) {
                continue
            }
            updateEloIfNeeded(for: match)
        }
    }

    private func updateEloIfNeeded(for match: GKTurnBasedMatch) {
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

    private func outcomeScore(for outcome: GKTurnBasedMatch.Outcome) -> Double? {
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

    private var processedMatchIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: processedMatchesKey) ?? []
            return Set(stored)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: processedMatchesKey)
        }
    }

    private func present(_ viewController: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else {
            return
        }
        root.present(viewController, animated: true)
    }
}

extension GameCenterManager: GameCenterEventListenerDelegate {
    func gameCenterDidReceiveTurnEvent() {
        loadMatches()
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
