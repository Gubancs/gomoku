import Foundation
@preconcurrency internal import GameKit
import UIKit
import Combine

struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

/// Central coordinator for Game Center authentication, matches, and leaderboards.
@MainActor
final class GameCenterManager: NSObject, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var activeMatches: [GKTurnBasedMatch] = []
    @Published var finishedMatches: [GKTurnBasedMatch] = []
    @Published var currentMatch: GKTurnBasedMatch?
    @Published var headToHeadSummary: HeadToHeadSummary?
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
    @Published var partyCode: String?
    @Published var isPartyMode: Bool = false
    @Published var partyError: String?

    let leaderboardID: String

    let eventListener = GameCenterEventListener()
    let eloStorageKey = "gomoku.elo.local"
    let processedMatchesKey = "gomoku.elo.processedMatches"
    let processedHeadToHeadMatchesKey = "gomoku.h2h.processedMatches"
    let defaultEloRating = 1200
    let eloKFactor = 32
    let headToHeadStore = HeadToHeadCloudKitStore()
    let presenceStore = PresenceCloudKitStore()
    var shouldPresentAuthUI: Bool = false
    var pendingAuthViewController: UIViewController?
    var pendingAutoMatchID: String?
    var pendingAutoMatch: GKTurnBasedMatch?
    var pendingRematchID: String?
    var matchmakingStartedAt: Date?
    var pendingAutoMatchMissingSince: Date?
    var pendingAutoMatchRetryWorkItem: DispatchWorkItem?
    var currentPlayerGroup: Int?
    @Published var playerRatingCache: [String: Int] = [:]
    @Published var playerAvatarCache: [String: UIImage] = [:]
    var isRefreshingRatings: Bool = false
    var loadingAvatars: Set<String> = []
    var syncingHeadToHeadMatchIDs: Set<String> = []
    var acceptingInviteMatchIDs: Set<String> = []
    var matchStatusPollTimer: Timer?
    let matchStatusPollInterval: TimeInterval = 5.0
    // Minimal automatch flow: do not churn fresh pending matches.
    let pendingMatchStallTimeout: TimeInterval = 90
    let pendingMatchMissingTimeout: TimeInterval = 90
    let matchAdoptionWindow: TimeInterval = 180
    var inboxPollTimer: Timer?
    let inboxPollInterval: TimeInterval = 8.0
    let presenceHeartbeatInterval: TimeInterval = 20.0

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
            let boxedViewController = UncheckedSendable(value: viewController)
            let errorDescription = error?.localizedDescription
            let isAuthenticated = localPlayer.isAuthenticated
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let viewController = boxedViewController.value {
                    self.pendingAuthViewController = viewController
                    self.needsAuthentication = true
                    if self.shouldPresentAuthUI {
                        self.present(viewController)
                        self.pendingAuthViewController = nil
                    }
                    return
                }

                if let errorDescription {
                    self.lastError = errorDescription
                }

                self.isAuthenticated = isAuthenticated
                self.needsAuthentication = !self.isAuthenticated
                if self.isAuthenticated {
                    self.pendingAuthViewController = nil
                    GKLocalPlayer.local.register(self.eventListener)
                    self.startInboxPolling()
                    self.startPresenceHeartbeat()
                    self.loadMatches()
                    self.refreshLeaderboard()
                } else {
                    self.stopMatchStatusPolling()
                    self.stopInboxPolling()
                    self.stopPresenceHeartbeat()
                }
            }
        }
    }

    func loadMatches() {
        guard isAuthenticated else { return }
        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            let boxedMatches = UncheckedSendable(value: matches)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    self.debugLog("loadMatches error: \(errorDescription)")
                    return
                }
                let allMatches = boxedMatches.value ?? []
                let summaries = allMatches.map { self.matchSummary($0) }.joined(separator: " | ")
                self.debugLog("loadMatches returned \(allMatches.count) matches -> \(summaries)")
                allMatches.forEach { self.debugLog("match detail \(self.matchSummary($0)) parts: \(self.participantsDescription($0))") }
                let finishedMatches = allMatches.filter { $0.status == .ended }
                self.finishedMatchesCount = finishedMatches.count
                self.finishedMatches = finishedMatches
                self.activeMatches = allMatches.filter { $0.status != .ended }
                if let currentID = self.currentMatch?.matchID,
                   let updated = boxedMatches.value?.first(where: { $0.matchID == currentID }) {
                    self.currentMatch = updated
                }
                // Auto-accept any incoming invites so we converge to a single shared match.
                self.autoAcceptInvitedMatches(from: allMatches)
                self.processFinishedMatches(allMatches)
                self.updateAutoMatchStatus(with: allMatches)
                self.updateRematchStatus(with: allMatches)
                _ = self.adoptReadyMatchIfSearching(from: allMatches)
            }
        }
    }

    func startMatchmaking() {
        startMatchmaking(partyGroup: nil, partyCode: nil)
    }

    /// Presents the built-in Game Center turn-based matchmaker UI (for debugging GC pairing).
    func presentMatchmakerUI() {
        guard isAuthenticated else {
            shouldPresentAuthUI = true
            needsAuthentication = true
            return
        }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        request.playerGroup = currentPlayerGroup ?? 0

        let vc = GKTurnBasedMatchmakerViewController(matchRequest: request)
        vc.turnBasedMatchmakerDelegate = self
        present(vc)
    }

    func startPartyHostMatchmaking() {
        let code = generatePartyCode()
        let group = stablePartyGroup(for: code)
        startMatchmaking(partyGroup: group, partyCode: code.uppercased())
    }

    func startPartyJoinMatchmaking(code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            partyError = "Party code cannot be empty."
            return
        }
        guard normalized.count == 6, normalized.range(of: "^[A-Z2-9]{6}$", options: .regularExpression) != nil else {
            partyError = "Invalid party code format."
            return
        }
        let group = stablePartyGroup(for: normalized)
        startMatchmaking(partyGroup: group, partyCode: normalized)
    }

    private func startMatchmaking(partyGroup: Int?, partyCode: String?) {
        guard isAuthenticated else { return }
        lastError = nil
        cancelPendingAutoMatchRetry()
        isFindingMatch = true
        isPartyMode = partyGroup != nil
        self.partyCode = partyCode
        partyError = nil
        currentPlayerGroup = partyGroup
        pendingAutoMatchID = nil
        pendingAutoMatch = nil
        pendingAutoMatchMissingSince = nil
        matchmakingStartedAt = Date()
        startMatchStatusPolling()
        cleanUpDanglingMatchmakingSessions { [weak self] in
            guard self?.isFindingMatch == true else { return }
            self?.resumeExistingMatchOrBeginSearch()
        }
    }

    func cancelMatchmaking() {
        guard isFindingMatch else { return }
        cancelPendingAutoMatchRetry()
        isFindingMatch = false
        matchmakingStartedAt = nil
        pendingAutoMatchMissingSince = nil
        isPartyMode = false
        self.partyCode = nil
        currentPlayerGroup = nil
        stopMatchStatusPollingIfIdle()

        if let pendingAutoMatch {
            performMatchRemoval(
                pendingAutoMatch,
                onError: { [weak self] (error: Error) in
                    self?.lastError = error.localizedDescription
                    self?.loadMatches()
                },
                onSuccess: { [weak self] in
                    self?.loadMatches()
                }
            )
            self.pendingAutoMatch = nil
            self.pendingAutoMatchID = nil
            return
        }

        guard let pendingID = pendingAutoMatchID else { return }
        pendingAutoMatchID = nil

        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            let boxedMatches = UncheckedSendable(value: matches)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    self.pendingAutoMatch = nil
                    self.loadMatches()
                    return
                }
                guard let match = boxedMatches.value?.first(where: { $0.matchID == pendingID }) else { return }
                self.performMatchRemoval(
                    match,
                    onError: { [weak self] (error: Error) in
                        self?.lastError = error.localizedDescription
                        self?.pendingAutoMatch = nil
                        self?.loadMatches()
                    },
                    onSuccess: { [weak self] in
                        self?.pendingAutoMatch = nil
                        self?.loadMatches()
                    }
                )
            }
        }
    }

    func handleMatchSelected(_ match: GKTurnBasedMatch) {
        if isLocalParticipantInvited(in: match) {
            acceptInviteIfNeeded(for: match)
            return
        }

        currentMatch = match
        isFindingMatch = false
        isAwaitingRematch = false
        matchmakingStartedAt = nil
        pendingAutoMatchMissingSince = nil
        pendingAutoMatchID = nil
        pendingAutoMatch = nil
        cancelPendingAutoMatchRetry()
        pendingRematchID = nil
        stopMatchStatusPollingIfIdle()
        refreshRatings(for: match)
        refreshHeadToHead(for: match)
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
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.lastError = error.localizedDescription
                        return
                    }
                    self.loadMatches()
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
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.lastError = error.localizedDescription
                        completion?(false)
                        return
                    }
                    if shouldClearCurrentMatch {
                        self.currentMatch = nil
                    }
                    self.loadMatches()
                    completion?(true)
                }
            }
        } else {
            match.participantQuitOutOfTurn(with: .lost) { [weak self] (error: Error?) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.lastError = error.localizedDescription
                        completion?(false)
                        return
                    }
                    if shouldClearCurrentMatch {
                        self.currentMatch = nil
                    }
                    self.loadMatches()
                    completion?(true)
                }
            }
        }
    }

    func requestRematch(for match: GKTurnBasedMatch) {
        isAwaitingRematch = true
        pendingRematchID = nil
        startMatchStatusPolling()

        match.rematch { [weak self] newMatch, error in
            let boxedMatch = UncheckedSendable(value: newMatch)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    self.isAwaitingRematch = false
                    self.stopMatchStatusPollingIfIdle()
                    return
                }

                guard let newMatch = boxedMatch.value else {
                    self.isAwaitingRematch = false
                    self.stopMatchStatusPollingIfIdle()
                    return
                }

                if self.isMatchReady(newMatch) {
                    self.currentMatch = newMatch
                    self.isAwaitingRematch = false
                    self.pendingRematchID = nil
                    self.stopMatchStatusPollingIfIdle()
                    self.refreshRatings(for: newMatch)
                    self.refreshHeadToHead(for: newMatch)
                    self.loadMatches()
                } else {
                    self.pendingRematchID = newMatch.matchID
                    self.isAwaitingRematch = true
                    self.startMatchStatusPolling()
                    self.loadMatches()
                }
            }
        }
    }

    func purgeFinishedMatches() {
        guard isAuthenticated else { return }
        guard !isPurgingFinishedMatches else { return }
        isPurgingFinishedMatches = true

        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            let boxedMatches = UncheckedSendable(value: matches)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    self.isPurgingFinishedMatches = false
                    return
                }

                let finished = (boxedMatches.value ?? []).filter { $0.status == .ended }
                guard !finished.isEmpty else {
                    self.isPurgingFinishedMatches = false
                    self.loadMatches()
                    return
                }

                var remaining = finished.count
                for match in finished {
                    self.performMatchRemoval(
                        match,
                        onError: { [weak self] (error: Error) in
                            self?.lastError = error.localizedDescription
                            remaining -= 1
                            if remaining <= 0 {
                                self?.isPurgingFinishedMatches = false
                                self?.loadMatches()
                            }
                        },
                        onSuccess: { [weak self] in
                            remaining -= 1
                            if remaining <= 0 {
                                self?.isPurgingFinishedMatches = false
                                self?.loadMatches()
                            }
                        }
                    )
                }
            }
        }
    }

    func removeMatch(_ match: GKTurnBasedMatch) {
        performMatchRemoval(
            match,
            onError: { [weak self] (error: Error) in
                self?.lastError = error.localizedDescription
            },
            onSuccess: { [weak self] in
                guard let self else { return }
                if self.currentMatch?.matchID == match.matchID {
                    self.currentMatch = nil
                }
                self.loadMatches()
            }
        )
    }

    private func performMatchRemoval(
        _ match: GKTurnBasedMatch,
        onError: ((Error) -> Void)? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        let boxedMatch = UncheckedSendable(value: match)
        let boxedOnError = UncheckedSendable(value: onError)
        let boxedOnSuccess = UncheckedSendable(value: onSuccess)
        Task {
            do {
                try await boxedMatch.value.remove()
                _ = await MainActor.run {
                    boxedOnSuccess.value?()
                }
            } catch {
                _ = await MainActor.run {
                    boxedOnError.value?(error)
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                self.loadMatches()
            }
        }
    }

    func isLocalParticipantInvited(in match: GKTurnBasedMatch) -> Bool {
        let localID = GKLocalPlayer.local.gamePlayerID
        guard let localParticipant = match.participants.first(where: { $0.player?.gamePlayerID == localID }) else {
            return false
        }
        return localParticipant.status == .invited
    }

    private func acceptInvite(for match: GKTurnBasedMatch) {
        let inviteMatchID = match.matchID
        match.acceptInvite { [weak self] acceptedMatch, error in
            let boxedMatch = UncheckedSendable(value: acceptedMatch)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.acceptingInviteMatchIDs.remove(inviteMatchID)
                if let errorDescription {
                    self.lastError = errorDescription
                    return
                }

                guard let acceptedMatch = boxedMatch.value else {
                    self.loadMatches()
                    return
                }

                self.currentMatch = acceptedMatch
                self.isFindingMatch = false
                self.isAwaitingRematch = false
                self.matchmakingStartedAt = nil
                self.pendingAutoMatchID = nil
                self.pendingAutoMatch = nil
                self.cancelPendingAutoMatchRetry()
                self.pendingRematchID = nil
                self.stopMatchStatusPollingIfIdle()
                self.refreshRatings(for: acceptedMatch)
                self.refreshHeadToHead(for: acceptedMatch)
                self.loadMatches()
            }
        }
    }

    func acceptInviteIfNeeded(for match: GKTurnBasedMatch) {
        let matchID = match.matchID
        guard !matchID.isEmpty else { return }
        guard !acceptingInviteMatchIDs.contains(matchID) else { return }
        acceptingInviteMatchIDs.insert(matchID)
        acceptInvite(for: match)
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

    func handleAutoMatchResult(_ match: GKTurnBasedMatch) {
        debugLog("handleAutoMatchResult \(matchSummary(match))")
        if isMatchReady(match) {
            currentMatch = match
            pendingAutoMatchID = nil
            cancelPendingAutoMatchRetry()
            isFindingMatch = false
            matchmakingStartedAt = nil
            pendingAutoMatchMissingSince = nil
            stopMatchStatusPollingIfIdle()
            refreshRatings(for: match)
            refreshHeadToHead(for: match)
            loadMatches()
        } else {
            isFindingMatch = true
            startMatchStatusPolling()
            loadMatches()
        }
    }

    private func beginAutoMatchSearch() {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2

        debugLog("beginAutoMatchSearch() group=\(request.playerGroup) partyCode=\(partyCode ?? "-")")
        GKTurnBasedMatch.find(for: request) { [weak self] match, error in
            let boxedMatch = UncheckedSendable(value: match)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    self.isFindingMatch = false
                    self.matchmakingStartedAt = nil
                    self.pendingAutoMatchMissingSince = nil
                    self.cancelPendingAutoMatchRetry()
                    self.stopMatchStatusPollingIfIdle()
                    self.debugLog("find error: \(errorDescription)")
                    return
                }

                guard let match = boxedMatch.value else {
                    self.isFindingMatch = false
                    self.matchmakingStartedAt = nil
                    self.pendingAutoMatchMissingSince = nil
                    self.cancelPendingAutoMatchRetry()
                    self.stopMatchStatusPollingIfIdle()
                    self.debugLog("find returned nil match")
                    return
                }

                self.pendingAutoMatchID = match.matchID
                self.pendingAutoMatch = match
                self.debugLog("find returned match \(self.matchSummary(match)) parts: \(self.participantsDescription(match))")
                self.handleAutoMatchResult(match)
            }
        }
    }

    private func scheduleAutoMatchRetry() {
        pendingAutoMatchRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isFindingMatch else { return }
            self.restartAutoMatchSearch(removePendingMatch: true)
        }
        pendingAutoMatchRetryWorkItem = workItem
        let delay = Double.random(in: 0.8...1.6)
        debugLog("scheduleAutoMatchRetry in \(String(format: "%.2f", delay))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingAutoMatchRetry() {
        pendingAutoMatchRetryWorkItem?.cancel()
        pendingAutoMatchRetryWorkItem = nil
    }

    private func resumeExistingMatchOrBeginSearch() {
        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            let boxedMatches = UncheckedSendable(value: matches)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isFindingMatch else { return }

                // Party mode: always start a fresh search; do not adopt old pending matches.
                if currentPlayerGroup != nil {
                    self.beginAutoMatchSearch()
                    return
                }

                if let errorDescription {
                    self.lastError = errorDescription
                    self.beginAutoMatchSearch()
                    return
                }

                let allMatches = boxedMatches.value ?? []
                if let readyMatch = self.mostRecentMatch(in: allMatches, matching: { self.isMatchReady($0) }) {
                    self.handleAutoMatchResult(readyMatch)
                    return
                }

                if let pendingMatch = self.mostRecentMatch(in: allMatches, matching: { self.isMatchPending($0) }) {
                    self.pendingAutoMatchID = pendingMatch.matchID
                    self.pendingAutoMatch = pendingMatch
                    self.handleAutoMatchResult(pendingMatch)
                    return
                }

                self.beginAutoMatchSearch()
            }
        }
    }

    private func cleanUpDanglingMatchmakingSessions(completion: @escaping () -> Void) {
        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            let boxedMatches = UncheckedSendable(value: matches)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    completion()
                    return
                }

                let staleCutoff = Date().addingTimeInterval(-15 * 60)
                let staleMatches = (boxedMatches.value ?? []).filter { match in
                    let creationDate = (match.creationDate as Date?) ?? .distantPast
                    guard creationDate < staleCutoff else { return false }
                    if match.status == .matching {
                        return true
                    }
                    if match.status == .open {
                        let playerCount = match.participants.filter { $0.player != nil }.count
                        return playerCount < 2
                    }
                    return false
                }

                guard !staleMatches.isEmpty else {
                    completion()
                    return
                }

                var remaining = staleMatches.count
                for staleMatch in staleMatches {
                    self.performMatchRemoval(
                        staleMatch,
                        onError: { [weak self] (error: Error) in
                            self?.lastError = error.localizedDescription
                            remaining -= 1
                            if remaining <= 0 {
                                completion()
                            }
                        },
                        onSuccess: {
                            remaining -= 1
                            if remaining <= 0 {
                                completion()
                            }
                        }
                    )
                }
            }
        }
    }

    private func updateAutoMatchStatus(with matches: [GKTurnBasedMatch]) {
        guard let pendingID = pendingAutoMatchID else { return }
        debugLog("updateAutoMatchStatus pending \(shortID(pendingID)) in \(matches.count) matches")
        guard let pendingMatch = matches.first(where: { $0.matchID == pendingID }) else {
            debugLog("pending match \(shortID(pendingAutoMatchID)) missing; searching alternatives")
            if currentPlayerGroup == nil,
               let readyMatch = mostRecentMatch(in: matches, matching: { isMatchReady($0) }) {
                pendingAutoMatchMissingSince = nil
                debugLog("found ready match \(matchSummary(readyMatch)); adopting")
                handleAutoMatchResult(readyMatch)
                return
            }

            if currentPlayerGroup == nil,
               let pendingMatch = mostRecentMatch(in: matches, matching: { isMatchPending($0) }) {
                pendingAutoMatchMissingSince = nil
                pendingAutoMatchID = pendingMatch.matchID
                pendingAutoMatch = pendingMatch
                debugLog("found replacement pending match \(matchSummary(pendingMatch))")
                handleAutoMatchResult(pendingMatch)
                return
            }

            // Transient omission can happen; if it persists, re-run automatch search.
            if pendingAutoMatchMissingSince == nil {
                pendingAutoMatchMissingSince = Date()
            }
            isFindingMatch = true
            startMatchStatusPolling()
            return
        }

        pendingAutoMatchMissingSince = nil
        if isMatchReady(pendingMatch) {
            debugLog("pending match ready \(matchSummary(pendingMatch)); adopting")
            currentMatch = pendingMatch
            pendingAutoMatchID = nil
            pendingAutoMatch = nil
            cancelPendingAutoMatchRetry()
            isFindingMatch = false
            matchmakingStartedAt = nil
            pendingAutoMatchMissingSince = nil
            stopMatchStatusPollingIfIdle()
            refreshRatings(for: pendingMatch)
            refreshHeadToHead(for: pendingMatch)
        } else {
            // Keep waiting significantly longer before considering a stall.
            // In practice this avoids churn where both clients repeatedly create
            // separate pending matches instead of converging to one.
            isFindingMatch = true
            startMatchStatusPolling()
        }
    }

    private func updateRematchStatus(with matches: [GKTurnBasedMatch]) {
        guard let pendingID = pendingRematchID else { return }
        guard let pendingMatch = matches.first(where: { $0.matchID == pendingID }) else {
            // Keep waiting; rematch can appear with eventual consistency.
            isAwaitingRematch = true
            startMatchStatusPolling()
            return
        }

        if isMatchReady(pendingMatch) {
            currentMatch = pendingMatch
            pendingRematchID = nil
            isAwaitingRematch = false
            stopMatchStatusPollingIfIdle()
            refreshRatings(for: pendingMatch)
            refreshHeadToHead(for: pendingMatch)
        } else {
            isAwaitingRematch = true
            startMatchStatusPolling()
        }
    }

    func isMatchReady(_ match: GKTurnBasedMatch) -> Bool {
        if match.status == .matching {
            return false
        }
        let playerCount = match.participants.filter { $0.player != nil }.count
        return playerCount >= 2
    }

    private func isMatchPending(_ match: GKTurnBasedMatch) -> Bool {
        if match.status == .matching {
            return true
        }
        if match.status == .open {
            let playerCount = match.participants.filter { $0.player != nil }.count
            return playerCount < 2
        }
        return false
    }

    private func mostRecentMatch(
        in matches: [GKTurnBasedMatch],
        matching predicate: (GKTurnBasedMatch) -> Bool
    ) -> GKTurnBasedMatch? {
        matches
            .filter(predicate)
            .sorted {
                (($0.creationDate as Date?) ?? .distantPast) > (($1.creationDate as Date?) ?? .distantPast)
            }
            .first
    }

    private func processFinishedMatches(_ matches: [GKTurnBasedMatch]) {
        guard isAuthenticated else { return }
        let processedElo = processedMatchIDs
        let processedHeadToHead = processedHeadToHeadMatchIDs

        for match in matches where match.status == .ended {
            if !processedElo.contains(match.matchID) {
                updateEloIfNeeded(for: match)
            }
            if !processedHeadToHead.contains(match.matchID) {
                updateHeadToHeadIfNeeded(for: match)
            }
        }
    }

    @discardableResult
    private func adoptReadyMatchIfSearching(from matches: [GKTurnBasedMatch]) -> Bool {
        guard isFindingMatch else { return false }
        // In party mode we only want matches created with the current party group.
        guard currentPlayerGroup == nil else { return false }
        guard let startedAtUnwrapped = matchmakingStartedAt else { return false }

        let candidate = matches
            .filter { $0.status != .ended && isMatchReady($0) }
            .filter { match in
                let creationDate = (match.creationDate as Date?) ?? .distantPast
                return creationDate >= startedAtUnwrapped.addingTimeInterval(-matchAdoptionWindow)
            }
            .sorted {
                (($0.creationDate as Date?) ?? .distantPast) > (($1.creationDate as Date?) ?? .distantPast)
            }
            .first

        guard let candidate else { return false }
        currentMatch = candidate
        pendingAutoMatchID = nil
        pendingAutoMatch = nil
        isFindingMatch = false
        matchmakingStartedAt = nil
        pendingAutoMatchMissingSince = nil
        stopMatchStatusPollingIfIdle()
        refreshRatings(for: candidate)
        refreshHeadToHead(for: candidate)
        return true
    }

    private func autoAcceptInvitedMatches(from matches: [GKTurnBasedMatch]) {
        guard isAuthenticated else { return }
        let invited = matches.filter { isLocalParticipantInvited(in: $0) }
        for match in invited {
            acceptInviteIfNeeded(for: match)
        }
    }

    private func startMatchStatusPolling() {
        guard matchStatusPollTimer == nil else { return }

        let timer = Timer(timeInterval: matchStatusPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isAuthenticated else {
                    self.stopMatchStatusPolling()
                    return
                }
                guard self.isFindingMatch || self.isAwaitingRematch else {
                    self.stopMatchStatusPolling()
                    return
                }
                self.loadMatches()
            }
        }

        matchStatusPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMatchStatusPolling() {
        matchStatusPollTimer?.invalidate()
        matchStatusPollTimer = nil
    }

    private func stopMatchStatusPollingIfIdle() {
        guard !(isFindingMatch || isAwaitingRematch) else { return }
        stopMatchStatusPolling()
    }

    private func startInboxPolling() {
        guard inboxPollTimer == nil else { return }

        let timer = Timer(timeInterval: inboxPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isAuthenticated else {
                    self.stopInboxPolling()
                    return
                }
                guard !self.isFindingMatch else { return }
                guard !self.isAwaitingRematch else { return }
                self.loadMatches()
            }
        }

        inboxPollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopInboxPolling() {
        inboxPollTimer?.invalidate()
        inboxPollTimer = nil
    }

    func fetchOnlineCount() async -> Int? {
        let lookback: TimeInterval = 120 // seconds
        do {
            return try await presenceStore.onlineCount(within: lookback)
        } catch {
            await MainActor.run {
                self.partyError = error.localizedDescription
            }
            return nil
        }
    }

    private func startPresenceHeartbeat() {
        stopPresenceHeartbeat()
        let timer = Timer(timeInterval: presenceHeartbeatInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                guard self.isAuthenticated else {
                    self.stopPresenceHeartbeat()
                    return
                }
                let playerID = GKLocalPlayer.local.gamePlayerID
                do {
                    try await self.presenceStore.heartbeat(playerID: playerID)
                } catch {
                    await MainActor.run {
                        self.partyError = error.localizedDescription
                    }
                }
            }
        }
        presenceTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        Task {
            let playerID = GKLocalPlayer.local.gamePlayerID
            try? await presenceStore.heartbeat(playerID: playerID)
        }
    }

    private func stopPresenceHeartbeat() {
        presenceTimer?.invalidate()
        presenceTimer = nil
    }

    private func restartAutoMatchSearch(removePendingMatch: Bool) {
        cancelPendingAutoMatchRetry()

        let pendingMatch = pendingAutoMatch
        let pendingID = pendingAutoMatchID
        pendingAutoMatch = nil
        pendingAutoMatchID = nil
        pendingAutoMatchMissingSince = nil

        debugLog("restartAutoMatchSearch removePendingMatch=\(removePendingMatch) pending=\(shortID(pendingID))")
        let startSearch = { [weak self] in
            guard let self else { return }
            guard self.isFindingMatch else { return }
            self.matchmakingStartedAt = Date()
            self.beginAutoMatchSearch()
        }

        guard removePendingMatch else {
            startSearch()
            return
        }

        if let match = pendingMatch, isMatchPending(match) {
            debugLog("restartAutoMatchSearch removing local pending match \(matchSummary(match))")
            performMatchRemoval(
                match,
                onError: { [weak self] (error: Error) in
                    self?.lastError = error.localizedDescription
                    self?.debugLog("remove pending match error: \(error.localizedDescription)")
                    startSearch()
                },
                onSuccess: {
                    self.debugLog("removed pending match; restarting search")
                    startSearch()
                }
            )
            return
        }

        guard let pendingID else {
            startSearch()
            return
        }

        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            let boxedMatches = UncheckedSendable(value: matches)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    self.debugLog("restartAutoMatchSearch loadMatches error: \(errorDescription)")
                    startSearch()
                    return
                }

                if let match = boxedMatches.value?.first(where: { $0.matchID == pendingID }),
                   self.isMatchPending(match) {
                    self.debugLog("restartAutoMatchSearch removing fetched pending match \(self.matchSummary(match))")
                    self.performMatchRemoval(
                        match,
                        onError: { [weak self] (error: Error) in
                            self?.lastError = error.localizedDescription
                            self?.debugLog("remove pending match error: \(error.localizedDescription)")
                            startSearch()
                        },
                        onSuccess: {
                            self.debugLog("removed pending match; restarting search")
                            startSearch()
                        }
                    )
                } else {
                    self.debugLog("restartAutoMatchSearch no pending match found; restarting search")
                    startSearch()
                }
            }
        }
    }

    private func purgeLocalPendingMatches(completion: @escaping () -> Void) {
        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            let boxedMatches = UncheckedSendable(value: matches)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    completion()
                    return
                }

                let cutoff = Date().addingTimeInterval(-5 * 60)
                let pending = (boxedMatches.value ?? []).filter { match in
                    let creation = (match.creationDate as Date?) ?? .distantPast
                    if creation >= cutoff { return false }
                    if match.status == .matching {
                        return true
                    }
                    if match.status == .open {
                        let playerCount = match.participants.filter { $0.player != nil }.count
                        return playerCount < 2
                    }
                    return false
                }

                guard !pending.isEmpty else {
                    completion()
                    return
                }

                var remaining = pending.count
                for match in pending {
                    self.performMatchRemoval(
                        match,
                        onError: { [weak self] (error: Error) in
                            self?.lastError = error.localizedDescription
                            remaining -= 1
                            if remaining <= 0 {
                                completion()
                            }
                        },
                        onSuccess: {
                            remaining -= 1
                            if remaining <= 0 {
                                completion()
                            }
                        }
                    )
                }
            }
        }
    }

    var processedMatchIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: processedMatchesKey) ?? []
            return Set(stored)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: processedMatchesKey)
        }
    }

    var processedHeadToHeadMatchIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: processedHeadToHeadMatchesKey) ?? []
            return Set(stored)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: processedHeadToHeadMatchesKey)
        }
    }

    // MARK: - Environment info

    var gameCenterEnvironmentName: String {
        #if DEBUG
        return "DEBUG Sandbox"
        #else
        if let receipt = Bundle.main.appStoreReceiptURL {
            if receipt.lastPathComponent == "sandboxReceipt" {
                return "TestFlight/Sandbox"
            }
            return "Production"
        }
        return "Unknown"
        #endif
    }

    var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "-"
    }

    var appIdentifierPrefix: String {
        if let array = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? [String],
           let first = array.first {
            return first
        }
        if let single = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String {
            return single
        }
        if let prefix = (provisioningPlist?["ApplicationIdentifierPrefix"] as? [String])?.first {
            return prefix
        }
        return "-"
    }

    var teamIdentifier: String? {
        if let team = entitlements?["com.apple.developer.team-identifier"] as? String {
            return team
        }
        if let appID = applicationIdentifier {
            return appID.split(separator: ".").first.map(String.init)
        }
        return nil
    }

    var applicationIdentifier: String? {
        entitlements?["application-identifier"] as? String
    }

    private var entitlements: [String: Any]? {
        provisioningPlist?["Entitlements"] as? [String: Any]
    }

    private var provisioningPlist: [String: Any]? {
        if let cachedProvisioningPlist {
            return cachedProvisioningPlist
        }
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .isoLatin1),
              let start = content.range(of: "<plist"),
              let end = content.range(of: "</plist>") else {
            cachedProvisioningPlist = nil
            return nil
        }
        let plistString = String(content[start.lowerBound..<end.upperBound])
        guard let plistData = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            cachedProvisioningPlist = nil
            return nil
        }
        cachedProvisioningPlist = dict
        return dict
    }

    private var cachedProvisioningPlist: [String: Any]?
    private var presenceTimer: Timer?

    // MARK: - Party code helpers

    private func generatePartyCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var code = ""
        for _ in 0..<6 {
            if let c = chars.randomElement() {
                code.append(c)
            }
        }
        return code
    }

    private func stablePartyGroup(for code: String) -> Int {
        let upper = code.uppercased()
        var hash: UInt32 = 0
        for scalar in upper.unicodeScalars {
            hash = (hash &* 31) &+ UInt32(scalar.value)
        }
        let group = Int(hash % UInt32(Int32.max))
        return max(group, 1)
    }

    // MARK: - Debug helpers

    #if DEBUG
    private func debugLog(_ message: String) {
        print("[MM] \(message)")
    }
    #else
    private func debugLog(_ message: String) { }
    #endif

    private func matchSummary(_ match: GKTurnBasedMatch) -> String {
        let status: String
        switch match.status {
        case .matching: status = "matching"
        case .open: status = "open"
        case .ended: status = "ended"
        default: status = "unknown"
        }
        let players = match.participants.filter { $0.player != nil }.count
        return "\(shortID(match.matchID))[\(status);players=\(players)]"
    }

    private func participantsDescription(_ match: GKTurnBasedMatch) -> String {
        match.participants.enumerated().map { index, participant in
            let pid = participant.player?.gamePlayerID ?? "-"
            let name = participant.player?.displayName ?? "empty"
            let status: String
            switch participant.status {
            case .matching: status = "matching"
            case .invited: status = "invited"
            case .declined: status = "declined"
            case .active: status = "active"
            case .done: status = "done"
            default: status = "unknown"
            }
            let outcome: String
            switch participant.matchOutcome {
            case .won: outcome = "won"
            case .lost: outcome = "lost"
            case .quit: outcome = "quit"
            case .tied: outcome = "tied"
            case .timeExpired: outcome = "timeExpired"
            case .none: outcome = "none"
            default: outcome = "other"
            }
            return "#\(index) \(shortID(pid))/\(name) status=\(status) outcome=\(outcome)"
        }.joined(separator: "; ")
    }

    private func shortID(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "-" }
        if id.count <= 8 { return id }
        return "\(id.prefix(4))...\(id.suffix(4))"
    }

    private func present(_ viewController: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes
        guard let scene = scenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? scenes.first as? UIWindowScene else {
            return
        }
        let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController
        guard var presenter = root else { return }

        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(viewController, animated: true)
    }
}
