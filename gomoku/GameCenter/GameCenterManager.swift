import Foundation
@preconcurrency internal import GameKit
import CloudKit
import UIKit
import Combine

struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

enum PartyMatchRole {
    case none
    case host
    case join
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
    @Published var cancelCooldownUntil: Date?
    @Published var partyCode: String?
    @Published var isPartyMode: Bool = false
    @Published var partyError: String?
    @Published var partyRole: PartyMatchRole = .none
    @Published var incomingRematchMatchID: String?
    @Published var incomingRematchRequesterName: String?
    @Published var isHandlingIncomingRematch: Bool = false

    let leaderboardID: String

    let eventListener = GameCenterEventListener()
    let eloStorageKey = "gomoku.elo.local"
    let processedMatchesKey = "gomoku.elo.processedMatches"
    let processedHeadToHeadMatchesKey = "gomoku.h2h.processedMatches"
    let defaultEloRating = 1500
    let eloKFactor = 32
    let defaultMoveTimeLimit: TimeInterval = 60
    let headToHeadStore = HeadToHeadCloudKitStore()
    let presenceStore = PresenceCloudKitStore()
    let rematchStore = RematchCloudKitStore()
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
    var bootstrapPendingMatchIDs: Set<String> = []
    var rejectedPartyMatchIDs: Set<String> = []
    var rematchStartAttemptedMatchIDs: Set<String> = []
    var rematchDeclineNotifiedMatchIDs: Set<String> = []
    var rematchSyncTask: Task<Void, Never>?
    var lastLocalEloUpdateAt: Date?
    var lastSubmittedEloRating: Int?
    var localEloSyncGraceInterval: TimeInterval = 120
    var matchStatusPollTimer: Timer?
    let matchStatusPollInterval: TimeInterval = 5.0
    // Minimal automatch flow: do not churn fresh pending matches.
    let pendingMatchStallTimeout: TimeInterval = 90
    let pendingMatchMissingTimeout: TimeInterval = 90
    let matchAdoptionWindow: TimeInterval = 180
    let partyHandshakeGraceInterval: TimeInterval = 45
    var inboxPollTimer: Timer?
    let inboxPollInterval: TimeInterval = 8.0
    let presenceHeartbeatInterval: TimeInterval = 10.0

    struct EloChange {
        let localDelta: Int
        let opponentDelta: Int
        let localRating: Int
        let opponentRating: Int
    }

    struct TurnTimerSnapshot {
        let blackRemaining: TimeInterval
        let whiteRemaining: TimeInterval
        let turnStartedAt: Date
    }

    init(leaderboardID: String = "gomoku.points") {
        self.leaderboardID = leaderboardID
        super.init()
        eventListener.delegate = self
        registerLifecycleObservers()
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
                    self.rematchSyncTask?.cancel()
                    self.rematchSyncTask = nil
                    self.incomingRematchMatchID = nil
                    self.incomingRematchRequesterName = nil
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
                self.refreshObservedMatchDates(with: allMatches)
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
                    // Keep player ratings and head-to-head in sync when participant assignment
                    // or match metadata changes after the screen is already open.
                    self.refreshRatings(for: updated)
                    self.refreshHeadToHead(for: updated)
                }
                // Auto-accept any incoming invites so we converge to a single shared match.
                self.autoAcceptInvitedMatches(from: allMatches)
                self.processFinishedMatches(allMatches)
                self.updateAutoMatchStatus(with: allMatches)
                self.updateRematchStatus(with: allMatches)
                self.syncIncomingRematchRequestState(with: allMatches)
                _ = self.adoptReadyMatchIfSearching(from: allMatches)
            }
        }
    }

    func startMatchmaking() {
        startMatchmaking(partyGroup: nil, partyCode: nil, partyRole: .none)
    }

    func presentMatchmaking() {
        guard isAuthenticated else { return }
        if isMultiplayerRestricted {
            lastError = "Game Center multiplayer is restricted for this account."
            return
        }
        if currentMatch == nil,
           let existing = sortedMatchesForDisplay(activeMatches).first {
            currentMatch = existing
            isFindingMatch = false
            return
        }
        isFindingMatch = true
        DispatchQueue.main.async { [weak self] in
            self?.startMatchmaking()
        }
    }

    func startPartyHostMatchmaking() {
        let code = generatePartyCode()
        guard let group = stablePartyGroup(for: code) else {
            partyError = "Failed to generate a valid party code."
            return
        }
        startMatchmaking(partyGroup: group, partyCode: code.uppercased(), partyRole: .host)
    }

    func startPartyJoinMatchmaking(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            partyError = "Party code cannot be empty."
            return
        }
        guard trimmed.count == 4,
              trimmed.range(
                of: "^[A-HJ-NP-Z2-9]{4}$",
                options: [.regularExpression, .caseInsensitive]
              ) != nil else {
            partyError = "Invalid party code format."
            return
        }
        let normalized = trimmed.uppercased()
        guard let group = stablePartyGroup(for: normalized) else {
            partyError = "Invalid party code."
            return
        }
        startMatchmaking(partyGroup: group, partyCode: normalized, partyRole: .join)
    }

    private func startMatchmaking(partyGroup: Int?, partyCode: String?, partyRole: PartyMatchRole) {
        guard isAuthenticated else { return }
        if isMultiplayerRestricted {
            lastError = "Game Center multiplayer is restricted for this account."
            return
        }
        if currentMatch == nil,
           let existing = sortedMatchesForDisplay(activeMatches).first {
            currentMatch = existing
            isFindingMatch = false
            return
        }
        debugLog("startMatchmaking env=\(gameCenterEnvironmentName) bundle=\(bundleIdentifier) version=\(appVersion) build=\(buildNumber) device=\(deviceDebugName)")
        lastError = nil
        cancelPendingAutoMatchRetry()
        bootstrapPendingMatchIDs.removeAll()
        rejectedPartyMatchIDs.removeAll()
        isFindingMatch = true
        let now = Date()
        if let existing = cancelCooldownUntil, existing > now {
            // Keep existing cooldown.
        } else {
            cancelCooldownUntil = now.addingTimeInterval(5)
        }
        isPartyMode = partyGroup != nil
        self.partyCode = partyCode
        self.partyRole = partyRole
        partyError = nil
        currentPlayerGroup = partyGroup
        pendingAutoMatchID = nil
        pendingAutoMatch = nil
        pendingAutoMatchMissingSince = nil
        matchmakingStartedAt = Date()
        incomingRematchMatchID = nil
        incomingRematchRequesterName = nil
        isHandlingIncomingRematch = false
        rematchStartAttemptedMatchIDs.removeAll()
        startMatchStatusPolling()
        cleanUpDanglingMatchmakingSessions { [weak self] in
            guard self?.isFindingMatch == true else { return }
            self?.resumeExistingMatchOrBeginSearch()
        }
    }

    func cancelMatchmaking() {
        guard isFindingMatch else { return }
        cancelPendingAutoMatchRetry()
        bootstrapPendingMatchIDs.removeAll()
        rejectedPartyMatchIDs.removeAll()
        isFindingMatch = false
        cancelCooldownUntil = nil
        matchmakingStartedAt = nil
        pendingAutoMatchMissingSince = nil
        isPartyMode = false
        self.partyCode = nil
        self.partyRole = .none
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
        let matchPartyCode = loadState(from: match)?.partyCode?.uppercased()
        if matchPartyCode == nil {
            if partyCode == nil {
                isPartyMode = false
                partyRole = .none
                currentPlayerGroup = nil
            }
        } else if !isPartyMode {
            isPartyMode = true
            partyCode = matchPartyCode
            partyRole = .none
            currentPlayerGroup = matchPartyCode.flatMap { stablePartyGroup(for: $0) }
        }

        switch validatePartyMatch(match) {
        case .valid:
            break
        case .pending:
            partyError = "Waiting for party authorization handshake..."
            if isPartyMode {
                bootstrapPendingMatchIfNeeded(match, source: "resume", force: true)
            }
        case let .invalid(reason):
            if !isPartyMode {
                break
            }
            rejectPartyMatch(match, reason: reason)
            return
        }

        if isLocalParticipantInvited(in: match) {
            acceptInviteIfNeeded(for: match)
            return
        }

        currentMatch = match
        isFindingMatch = false
        cancelCooldownUntil = nil
        isAwaitingRematch = false
        matchmakingStartedAt = nil
        pendingAutoMatchMissingSince = nil
        pendingAutoMatchID = nil
        pendingAutoMatch = nil
        cancelPendingAutoMatchRetry()
        pendingRematchID = nil
        incomingRematchMatchID = nil
        incomingRematchRequesterName = nil
        isHandlingIncomingRematch = false
        rematchStartAttemptedMatchIDs.removeAll()
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
        if let current = match.currentParticipant?.player?.gamePlayerID {
            return isLocalPlayerID(current)
        }
        if let currentTeam = match.currentParticipant?.player?.teamPlayerID {
            return isLocalPlayerID(currentTeam)
        }

        // Some freshly created automatch games can transiently report nil currentParticipant.
        // If only the local player is assigned so far, allow opening move submission.
        let assignedParticipants = match.participants.filter { $0.player != nil }
        guard assignedParticipants.count == 1 else { return false }
        return isLocalParticipant(assignedParticipants.first)
    }

    var isCurrentMatchReady: Bool {
        guard let match = currentMatch else { return false }
        // Keep the board visible after match end so players can review
        // the final state and trigger rematch.
        return isMatchReady(match) || match.status == .ended
    }

    func submitTurn(game: GomokuGame, match: GKTurnBasedMatch, timerSnapshot: TurnTimerSnapshot? = nil) {
        guard let data = encodedStateForSubmission(from: game, timerSnapshot: timerSnapshot) else { return }

        if let winner = game.winner {
            finishMatch(match, data: data, winner: winner)
            return
        }

        if game.isDraw {
            finishMatch(match, data: data, winner: nil)
            return
        }

        guard let nextParticipant = nextActiveParticipant(after: match.currentParticipant, in: match) else { return }
        let submittedMatchSummary = matchSummary(match)
        let nextStatus: String
        switch nextParticipant.status {
        case .matching: nextStatus = "matching"
        case .invited: nextStatus = "invited"
        case .active: nextStatus = "active"
        case .declined: nextStatus = "declined"
        case .done: nextStatus = "done"
        default: nextStatus = "unknown"
        }
        debugLog("submitTurn \(submittedMatchSummary) -> next=\(shortID(nextParticipant.player?.gamePlayerID)) status=\(nextStatus)")

        match.endTurn(
            withNextParticipants: [nextParticipant],
            turnTimeout: GKTurnTimeoutDefault,
            match: data,
            completionHandler: { [weak self] (error: Error?) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.lastError = error.localizedDescription
                        self.debugLog("submitTurn error: \(error.localizedDescription)")
                        return
                    }
                    self.debugLog("submitTurn success \(submittedMatchSummary)")
                    self.loadMatches()
                }
            }
        )
    }

    func resignCurrentMatch(using game: GomokuGame, timerSnapshot: TurnTimerSnapshot? = nil, shouldClearCurrentMatch: Bool = true, completion: ((Bool) -> Void)? = nil) {
        guard let match = currentMatch else { return }
        let data = encodedStateForSubmission(from: game, timerSnapshot: timerSnapshot) ?? Data()

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
        incomingRematchMatchID = nil
        incomingRematchRequesterName = nil
        isHandlingIncomingRematch = false
        startMatchStatusPolling()

        let localPlayerID = GKLocalPlayer.local.gamePlayerID
        guard !localPlayerID.isEmpty else {
            createRematchMatch(from: match)
            return
        }

        let matchID = match.matchID
        rematchDeclineNotifiedMatchIDs.remove(matchID)
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.rematchStore.requestRematch(matchID: matchID, localPlayerID: localPlayerID)
                await MainActor.run {
                    switch result {
                    case .pending:
                        self.debugLog("rematch request pending for \(self.shortID(matchID))")
                        self.isAwaitingRematch = true
                        self.startMatchStatusPolling()
                    case .accepted:
                        self.debugLog("rematch request accepted for \(self.shortID(matchID)); creating rematch")
                        self.createRematchMatchIfNeeded(from: match, source: "requestRematch")
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isAwaitingRematch = false
                    self.stopMatchStatusPollingIfIdle()
                }
            }
        }
    }

    func acceptIncomingRematch() {
        guard let matchID = incomingRematchMatchID else { return }
        guard let match = matchByID(matchID) else {
            incomingRematchMatchID = nil
            incomingRematchRequesterName = nil
            return
        }

        let localPlayerID = GKLocalPlayer.local.gamePlayerID
        guard !localPlayerID.isEmpty else { return }

        incomingRematchMatchID = nil
        incomingRematchRequesterName = nil
        isHandlingIncomingRematch = true
        isAwaitingRematch = true
        pendingRematchID = nil
        startMatchStatusPolling()

        Task { [weak self] in
            guard let self else { return }
            do {
                let accepted = try await self.rematchStore.acceptRematch(matchID: matchID, localPlayerID: localPlayerID)
                await MainActor.run {
                    self.isHandlingIncomingRematch = false
                    if accepted {
                        self.createRematchMatchIfNeeded(from: match, source: "acceptIncomingRematch")
                    } else {
                        self.isAwaitingRematch = false
                        self.stopMatchStatusPollingIfIdle()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isHandlingIncomingRematch = false
                    self.isAwaitingRematch = false
                    self.lastError = error.localizedDescription
                    self.stopMatchStatusPollingIfIdle()
                }
            }
        }
    }

    func declineIncomingRematch() {
        guard let matchID = incomingRematchMatchID else { return }
        let localPlayerID = GKLocalPlayer.local.gamePlayerID
        guard !localPlayerID.isEmpty else { return }

        incomingRematchMatchID = nil
        incomingRematchRequesterName = nil
        isHandlingIncomingRematch = true
        isAwaitingRematch = false
        pendingRematchID = nil
        stopMatchStatusPollingIfIdle()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.rematchStore.declineRematch(matchID: matchID, localPlayerID: localPlayerID)
                await MainActor.run {
                    self.isHandlingIncomingRematch = false
                    self.debugLog("rematch declined for \(self.shortID(matchID))")
                }
            } catch {
                await MainActor.run {
                    self.isHandlingIncomingRematch = false
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func createRematchMatchIfNeeded(from endedMatch: GKTurnBasedMatch, source: String) {
        let matchID = endedMatch.matchID
        guard !matchID.isEmpty else {
            createRematchMatch(from: endedMatch)
            return
        }
        guard !rematchStartAttemptedMatchIDs.contains(matchID) else {
            debugLog("rematch create skip \(shortID(matchID)) source=\(source): already attempted")
            return
        }
        rematchStartAttemptedMatchIDs.insert(matchID)
        createRematchMatch(from: endedMatch)
    }

    private func createRematchMatch(from endedMatch: GKTurnBasedMatch) {
        let endedMatchID = endedMatch.matchID
        endedMatch.rematch { [weak self] newMatch, error in
            let boxedMatch = UncheckedSendable(value: newMatch)
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let errorDescription {
                    self.lastError = errorDescription
                    self.isAwaitingRematch = false
                    self.rematchStartAttemptedMatchIDs.remove(endedMatchID)
                    self.stopMatchStatusPollingIfIdle()
                    return
                }

                guard let newMatch = boxedMatch.value else {
                    self.isAwaitingRematch = false
                    self.rematchStartAttemptedMatchIDs.remove(endedMatchID)
                    self.stopMatchStatusPollingIfIdle()
                    return
                }

                if self.isMatchReady(newMatch) {
                    self.currentMatch = newMatch
                    self.isAwaitingRematch = false
                    self.pendingRematchID = nil
                    self.incomingRematchMatchID = nil
                    self.incomingRematchRequesterName = nil
                    self.rematchStartAttemptedMatchIDs.removeAll()
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
        debugLog("removeMatch requested \(matchSummary(match))")
        performMatchRemoval(
            match,
            onError: { [weak self] (error: Error) in
                self?.lastError = error.localizedDescription
                self?.debugLog("removeMatch error \(self?.shortID(match.matchID) ?? "-"): \(error.localizedDescription)")
            },
            onSuccess: { [weak self] in
                guard let self else { return }
                self.debugLog("removeMatch success \(self.shortID(match.matchID))")
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

    func finalizeMatchIfPossible(_ match: GKTurnBasedMatch, using state: GameState) {
        guard match.status != .ended else { return }
        guard isLocalPlayersTurn(in: match) else { return }
        guard state.winner != nil || state.isDraw else { return }
        guard let data = state.encoded() else { return }
        finishMatch(match, data: data, winner: state.winner)
    }

    private func encodedStateForSubmission(from game: GomokuGame, timerSnapshot: TurnTimerSnapshot? = nil) -> Data? {
        let state = game.makeState()
        var mergedSymbolPreferences = state.playerSymbolPreferences
        let localPlayerID = GKLocalPlayer.local.gamePlayerID
        if !localPlayerID.isEmpty {
            mergedSymbolPreferences[localPlayerID] = localPlayerSymbolPreferences()
        }
        let blackRemaining = timerSnapshot?.blackRemaining ?? state.blackTimeRemaining
        let whiteRemaining = timerSnapshot?.whiteRemaining ?? state.whiteTimeRemaining
        let startedAt = timerSnapshot?.turnStartedAt.timeIntervalSince1970 ?? state.turnStartedAt

        guard isPartyMode, let code = partyCode?.uppercased(), !code.isEmpty else {
            let syncedState = GameState(
                board: state.board,
                moves: state.moves,
                currentPlayer: state.currentPlayer,
                winner: state.winner,
                isDraw: state.isDraw,
                lastMove: state.lastMove,
                winningLine: state.winningLine,
                partyCode: state.partyCode,
                playerSymbolPreferences: mergedSymbolPreferences,
                blackTimeRemaining: blackRemaining,
                whiteTimeRemaining: whiteRemaining,
                turnStartedAt: startedAt
            )
            return syncedState.encoded()
        }
        if state.partyCode?.uppercased() == code {
            let syncedState = GameState(
                board: state.board,
                moves: state.moves,
                currentPlayer: state.currentPlayer,
                winner: state.winner,
                isDraw: state.isDraw,
                lastMove: state.lastMove,
                winningLine: state.winningLine,
                partyCode: state.partyCode,
                playerSymbolPreferences: mergedSymbolPreferences,
                blackTimeRemaining: blackRemaining,
                whiteTimeRemaining: whiteRemaining,
                turnStartedAt: startedAt
            )
            return syncedState.encoded()
        }
        let securedState = GameState(
            board: state.board,
            moves: state.moves,
            currentPlayer: state.currentPlayer,
            winner: state.winner,
            isDraw: state.isDraw,
            lastMove: state.lastMove,
            winningLine: state.winningLine,
            partyCode: code,
            playerSymbolPreferences: mergedSymbolPreferences,
            blackTimeRemaining: blackRemaining,
            whiteTimeRemaining: whiteRemaining,
            turnStartedAt: startedAt
        )
        return securedState.encoded()
    }

    func isLocalParticipantInvited(in match: GKTurnBasedMatch) -> Bool {
        guard let localParticipant = match.participants.first(where: { isLocalParticipant($0) }) else {
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
            isLocalParticipant(participant)
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
            // .matching allows sending the first turn to an unassigned automatch seat.
            if participant.status == .active || participant.status == .invited || participant.status == .matching {
                return participant
            }
        }

        return nil
    }

    func handleAutoMatchResult(_ match: GKTurnBasedMatch) {
        debugLog("handleAutoMatchResult \(matchSummary(match))")
        switch validatePartyMatch(match) {
        case .valid:
            break
        case .pending:
            break
        case let .invalid(reason):
            rejectPartyMatch(match, reason: reason)
            return
        }
        if isMatchReady(match) {
            bootstrapPendingMatchIDs.remove(match.matchID)
            currentMatch = match
            pendingAutoMatchID = nil
            cancelPendingAutoMatchRetry()
            isFindingMatch = false
            cancelCooldownUntil = nil
            matchmakingStartedAt = nil
            pendingAutoMatchMissingSince = nil
            stopMatchStatusPollingIfIdle()
            refreshRatings(for: match)
            refreshHeadToHead(for: match)
            loadMatches()
        } else {
            // Keep the board open while waiting for opponent assignment.
            if currentMatch?.matchID != match.matchID {
                currentMatch = match
            }
            bootstrapPendingMatchIfNeeded(match, source: "handleAutoMatchResult")
            isFindingMatch = true
            startMatchStatusPolling()
            loadMatches()
        }
    }

    private func beginAutoMatchSearch() {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.defaultNumberOfPlayers = 2
        request.playerGroup = currentPlayerGroup ?? 0

        debugLog("beginAutoMatchSearch() group=\(request.playerGroup) partyCode=\(partyCode ?? "-") version=\(appVersion)(\(buildNumber))")
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
                self.bootstrapPendingMatchIfNeeded(match, source: "find callback")
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

                self.refreshObservedMatchDates(with: boxedMatches.value ?? [])

                let staleCutoff = Date().addingTimeInterval(-15 * 60)
                let staleMatches = (boxedMatches.value ?? []).filter { match in
                    guard self.observedDate(for: match) < staleCutoff else { return false }
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
        if adoptReadyMatchIfSearching(from: matches) {
            debugLog("updateAutoMatchStatus adopted ready match while searching")
            return
        }

        guard let pendingID = pendingAutoMatchID else { return }
        if rejectedPartyMatchIDs.contains(pendingID) {
            debugLog("updateAutoMatchStatus ignoring rejected pending match \(shortID(pendingID))")
            pendingAutoMatchID = nil
            pendingAutoMatch = nil
            if isFindingMatch {
                beginAutoMatchSearch()
            }
            return
        }
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
            bootstrapPendingMatchIDs.remove(pendingMatch.matchID)
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
            if currentMatch?.matchID != pendingMatch.matchID {
                currentMatch = pendingMatch
            }
            bootstrapPendingMatchIfNeeded(pendingMatch, source: "updateAutoMatchStatus")
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

    private func syncIncomingRematchRequestState(with matches: [GKTurnBasedMatch]) {
        guard isAuthenticated else { return }
        guard let localPlayerID = localPlayerGameID(), !localPlayerID.isEmpty else { return }

        guard let targetMatch = rematchSyncTargetMatch(from: matches) else {
            incomingRematchMatchID = nil
            incomingRematchRequesterName = nil
            return
        }

        let targetID = targetMatch.matchID
        guard !targetID.isEmpty else { return }
        let boxedTargetMatch = UncheckedSendable(value: targetMatch)
        rematchSyncTask?.cancel()
        rematchSyncTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await self.rematchStore.fetchStatus(matchID: targetID, localPlayerID: localPlayerID)
                await MainActor.run {
                    self.applyRematchRequestStatus(status, for: boxedTargetMatch.value)
                }
            } catch {
                await MainActor.run {
                    self.debugLog("rematch sync error \(self.shortID(targetID)): \(error.localizedDescription)")
                }
            }
        }
    }

    private func rematchSyncTargetMatch(from matches: [GKTurnBasedMatch]) -> GKTurnBasedMatch? {
        if let currentID = currentMatch?.matchID,
           let current = matches.first(where: { $0.matchID == currentID }),
           current.status == .ended {
            return current
        }
        return matches
            .filter { $0.status == .ended }
            .sorted { observedDate(for: $0) > observedDate(for: $1) }
            .first
    }

    private func applyRematchRequestStatus(_ status: RematchRequestStatus, for match: GKTurnBasedMatch) {
        let matchID = match.matchID

        switch status {
        case .none:
            if incomingRematchMatchID == matchID {
                incomingRematchMatchID = nil
                incomingRematchRequesterName = nil
            }
        case .incoming(let requesterID):
            incomingRematchMatchID = matchID
            incomingRematchRequesterName = displayName(for: requesterID, in: match)
            isAwaitingRematch = false
            stopMatchStatusPollingIfIdle()
        case .outgoingPending:
            incomingRematchMatchID = nil
            incomingRematchRequesterName = nil
            isAwaitingRematch = true
            startMatchStatusPolling()
        case .accepted:
            incomingRematchMatchID = nil
            incomingRematchRequesterName = nil
            isAwaitingRematch = true
            startMatchStatusPolling()
            createRematchMatchIfNeeded(from: match, source: "syncRematchAccepted")
        case .declinedByOpponent:
            incomingRematchMatchID = nil
            incomingRematchRequesterName = nil
            isAwaitingRematch = false
            stopMatchStatusPollingIfIdle()
            if !rematchDeclineNotifiedMatchIDs.contains(matchID) {
                rematchDeclineNotifiedMatchIDs.insert(matchID)
                lastError = "Rematch request declined."
            }
        }
    }

    private func localPlayerGameID() -> String? {
        let playerID = GKLocalPlayer.local.gamePlayerID
        return playerID.isEmpty ? nil : playerID
    }

    private func matchByID(_ matchID: String) -> GKTurnBasedMatch? {
        if let currentMatch, currentMatch.matchID == matchID {
            return currentMatch
        }
        if let active = activeMatches.first(where: { $0.matchID == matchID }) {
            return active
        }
        return finishedMatches.first(where: { $0.matchID == matchID })
    }

    private func displayName(for gamePlayerID: String, in match: GKTurnBasedMatch) -> String {
        guard !gamePlayerID.isEmpty else { return "Opponent" }
        if let participant = match.participants.first(where: { $0.player?.gamePlayerID == gamePlayerID }),
           let name = participant.player?.displayName,
           !name.isEmpty {
            return name
        }
        return "Opponent"
    }

    func isMatchReady(_ match: GKTurnBasedMatch) -> Bool {
        if match.status == .matching || match.status == .ended || match.status == .unknown {
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
            .filter { !rejectedPartyMatchIDs.contains($0.matchID) }
            .filter(predicate)
            .sorted {
                observedDate(for: $0) > observedDate(for: $1)
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
        let readyMatches = matches.filter { match in
            guard !rejectedPartyMatchIDs.contains(match.matchID) else { return false }
            guard match.status != .ended else { return false }
            guard isMatchReady(match) else { return false }
            return localParticipantIndex(in: match) != nil
        }
        guard !readyMatches.isEmpty else { return false }

        let lowerBound = matchmakingStartedAt?.addingTimeInterval(-matchAdoptionWindow) ?? Date().addingTimeInterval(-24 * 60 * 60)
        let recentReady = readyMatches.filter { match in
            return observedDate(for: match) >= lowerBound
        }
        let candidatePool = recentReady.isEmpty ? readyMatches : recentReady
        let candidate = candidatePool.sorted {
            observedDate(for: $0) > observedDate(for: $1)
        }.first

        guard let candidate else { return false }
        switch validatePartyMatch(candidate) {
        case .valid:
            break
        case .pending:
            return false
        case let .invalid(reason):
            rejectPartyMatch(candidate, reason: reason)
            return false
        }
        debugLog("adoptReadyMatchIfSearching candidate \(matchSummary(candidate))")
        currentMatch = candidate
        pendingAutoMatchID = nil
        pendingAutoMatch = nil
        bootstrapPendingMatchIDs.remove(candidate.matchID)
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
        if isPresenceDisabled {
            return nil
        }
        let lookback: TimeInterval = 45 // seconds
        do {
            return try await presenceStore.onlineCount(within: lookback)
        } catch {
            if shouldDisablePresence(for: error) {
                await MainActor.run {
                    self.isPresenceDisabled = true
                }
                return nil
            }
            debugLog("presence count error: \(error.localizedDescription)")
            return nil
        }
    }

    private func shouldDisablePresence(for error: Error) -> Bool {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .unknownItem, .zoneNotFound, .badContainer, .notAuthenticated, .permissionFailure, .invalidArguments:
                let message = ckError.localizedDescription.lowercased()
                if message.contains("record type") && message.contains("presence") {
                    return true
                }
                if message.contains("did not find record type") {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private func startPresenceHeartbeat() {
        if isPresenceDisabled {
            return
        }
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
                    if self.shouldDisablePresence(for: error) {
                        await MainActor.run {
                            self.isPresenceDisabled = true
                            self.stopPresenceHeartbeat()
                        }
                        return
                    }
                    self.debugLog("presence heartbeat error: \(error.localizedDescription)")
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

                self.refreshObservedMatchDates(with: boxedMatches.value ?? [])

                let cutoff = Date().addingTimeInterval(-5 * 60)
                let pending = (boxedMatches.value ?? []).filter { match in
                    if self.observedDate(for: match) >= cutoff { return false }
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

    var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "-"
    }

    var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "-"
    }

    var deviceDebugName: String {
        "\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)"
    }

    var isMultiplayerRestricted: Bool {
        GKLocalPlayer.local.isMultiplayerGamingRestricted
    }

    var isUnderage: Bool {
        GKLocalPlayer.local.isUnderage
    }

    private func localPlayerSymbolPreferences() -> PlayerSymbolPreferences {
        let blackRaw = StoneSymbolConfiguration.validatedOption(
            rawValue: UserDefaults.standard.string(forKey: StoneSymbolConfiguration.blackStorageKey),
            fallback: StoneSymbolConfiguration.defaultBlack
        ).rawValue
        let whiteRaw = StoneSymbolConfiguration.validatedOption(
            rawValue: UserDefaults.standard.string(forKey: StoneSymbolConfiguration.whiteStorageKey),
            fallback: StoneSymbolConfiguration.defaultWhite
        ).rawValue
        return PlayerSymbolPreferences(
            blackSymbolRawValue: blackRaw,
            whiteSymbolRawValue: whiteRaw
        )
    }

    private func localPlayerSymbolPreferenceMap() -> [String: PlayerSymbolPreferences] {
        let localPlayerID = GKLocalPlayer.local.gamePlayerID
        guard !localPlayerID.isEmpty else { return [:] }
        return [localPlayerID: localPlayerSymbolPreferences()]
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
    private var isPresenceDisabled: Bool = false
    private var notificationObservers: [NSObjectProtocol] = []
    private var observedMatchDates: [String: Date] = [:]

    // MARK: - Party code helpers

    private static let partyCodeAlphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    private func generatePartyCode() -> String {
        var code = ""
        for _ in 0..<4 {
            if let c = Self.partyCodeAlphabet.randomElement() {
                code.append(c)
            }
        }
        return code
    }

    private func stablePartyGroup(for code: String) -> Int? {
        let upper = code.uppercased()
        guard upper.count == 4 else { return nil }

        var value = 0
        for char in upper {
            guard let digit = Self.partyCodeAlphabet.firstIndex(of: char) else {
                return nil
            }
            value = (value * 32) + digit
        }
        // Non-colliding mapping for 4-char base32 codes; +1 keeps group non-zero.
        return value + 1
    }

    private enum PartyMatchValidation {
        case valid
        case pending
        case invalid(String)
    }

    private func validatePartyMatch(_ match: GKTurnBasedMatch) -> PartyMatchValidation {
        if match.status == .ended {
            return .valid
        }
        guard isPartyMode else { return .valid }
        guard let expectedCode = partyCode, !expectedCode.isEmpty else {
            return .invalid("Party mode is missing a valid code.")
        }
        guard !rejectedPartyMatchIDs.contains(match.matchID) else {
            return .invalid("Rejected match for different party code.")
        }

        if let state = loadState(from: match),
           let embeddedCode = state.partyCode,
           !embeddedCode.isEmpty {
            if embeddedCode.caseInsensitiveCompare(expectedCode) == .orderedSame {
                return .valid
            }
            return .invalid("Unauthorized player/code detected. Match code does not match.")
        }

        if isMatchPending(match) {
            return .pending
        }

        // Allow a short grace window for the bootstrap/handshake to land on ready matches.
        let firstSeen = observedDate(for: match)
        if Date().timeIntervalSince(firstSeen) < partyHandshakeGraceInterval {
            return .pending
        }

        return .invalid("Match is missing party authorization data.")
    }

    private func rejectPartyMatch(_ match: GKTurnBasedMatch, reason: String) {
        let matchID = match.matchID
        if !matchID.isEmpty {
            rejectedPartyMatchIDs.insert(matchID)
        }
        partyError = reason
        debugLog("rejectPartyMatch \(matchSummary(match)) reason=\(reason)")

        if pendingAutoMatchID == matchID {
            pendingAutoMatchID = nil
            pendingAutoMatch = nil
        }
        if currentMatch?.matchID == matchID {
            currentMatch = nil
        }

        // Best effort: leave unauthorized match locally and continue secure search.
        match.participantQuitOutOfTurn(with: .quit) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isFindingMatch {
                    self.beginAutoMatchSearch()
                } else {
                    self.loadMatches()
                }
            }
        }
    }

    // MARK: - Debug helpers

    #if DEBUG
    func debugLog(_ message: String) {
        print("[MM] \(message)")
    }
    #else
    func debugLog(_ message: String) { }
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

    private func isLocalPlayerID(_ id: String?) -> Bool {
        guard let id, !id.isEmpty else { return false }
        return localPlayerIDSet.contains(id)
    }

    func isLocalParticipant(_ participant: GKTurnBasedParticipant?) -> Bool {
        guard let participant, let player = participant.player else { return false }
        if isLocalPlayerID(player.gamePlayerID) { return true }
        let teamID = player.teamPlayerID
        if !teamID.isEmpty, isLocalPlayerID(teamID) { return true }
        return false
    }

    private var localPlayerIDSet: Set<String> {
        let local = GKLocalPlayer.local
        var ids = Set<String>()
        let gameID = local.gamePlayerID
        if !gameID.isEmpty {
            ids.insert(gameID)
        }
        let teamID = local.teamPlayerID
        if !teamID.isEmpty {
            ids.insert(teamID)
        }
        return ids
    }

    private func refreshObservedMatchDates(with matches: [GKTurnBasedMatch]) {
        let now = Date()
        var activeIDs = Set<String>()

        for match in matches {
            let matchID = match.matchID
            guard !matchID.isEmpty else { continue }
            activeIDs.insert(matchID)
            if observedMatchDates[matchID] == nil {
                observedMatchDates[matchID] = now
            }
        }

        observedMatchDates = observedMatchDates.filter { activeIDs.contains($0.key) }
    }

    private func observedDate(for match: GKTurnBasedMatch) -> Date {
        let matchID = match.matchID
        guard !matchID.isEmpty else { return .distantPast }
        if let existing = observedMatchDates[matchID] {
            return existing
        }
        let now = Date()
        observedMatchDates[matchID] = now
        return now
    }

    func sortedMatchesForDisplay(_ matches: [GKTurnBasedMatch]) -> [GKTurnBasedMatch] {
        refreshObservedMatchDates(with: matches)
        return matches.sorted { observedDate(for: $0) > observedDate(for: $1) }
    }

    private func bootstrapPendingMatchIfNeeded(_ match: GKTurnBasedMatch, source: String, force: Bool = false) {
        guard force || isFindingMatch else {
            debugLog("bootstrap skip \(shortID(match.matchID)) source=\(source): not finding")
            return
        }
        guard isMatchPending(match) else {
            debugLog("bootstrap skip \(shortID(match.matchID)) source=\(source): not pending (\(matchSummary(match)))")
            return
        }
        let assignedParticipants = match.participants.filter { $0.player != nil }
        guard assignedParticipants.count == 1 else {
            debugLog("bootstrap skip \(shortID(match.matchID)) source=\(source): assignedParticipants=\(assignedParticipants.count)")
            return
        }
        if match.currentParticipant != nil {
            guard isLocalPlayersTurn(in: match) else {
                debugLog("bootstrap skip \(shortID(match.matchID)) source=\(source): local is not current participant")
                return
            }
        }

        let matchID = match.matchID
        guard !matchID.isEmpty else {
            debugLog("bootstrap skip - source=\(source): empty matchID")
            return
        }
        guard !bootstrapPendingMatchIDs.contains(matchID) else {
            debugLog("bootstrap skip \(shortID(matchID)) source=\(source): already bootstrapped")
            return
        }

        guard let nextParticipant = nextActiveParticipant(after: match.currentParticipant, in: match),
              let nextIndex = match.participants.firstIndex(where: { $0 === nextParticipant }) else {
            debugLog("bootstrap skip \(shortID(matchID)) source=\(source): no next participant")
            return
        }

        let nextColor: Player = nextIndex == 0 ? .black : .white
        let bootstrapState = GameState(
            board: Array(
                repeating: Array<Player?>(repeating: nil, count: GomokuGame.boardSize),
                count: GomokuGame.boardSize
            ),
            moves: [],
            currentPlayer: nextColor,
            winner: nil,
            isDraw: false,
            lastMove: nil,
            winningLine: nil,
            partyCode: isPartyMode ? partyCode?.uppercased() : nil,
            playerSymbolPreferences: localPlayerSymbolPreferenceMap(),
            blackTimeRemaining: defaultMoveTimeLimit,
            whiteTimeRemaining: defaultMoveTimeLimit,
            turnStartedAt: Date().timeIntervalSince1970
        )
        guard let data = bootstrapState.encoded() else { return }

        let summary = matchSummary(match)
        let nextID = shortID(nextParticipant.player?.gamePlayerID)
        bootstrapPendingMatchIDs.insert(matchID)
        debugLog("bootstrap pending \(summary) source=\(source) -> nextIndex=\(nextIndex) next=\(nextID) nextColor=\(nextColor.rawValue)")

        match.endTurn(
            withNextParticipants: [nextParticipant],
            turnTimeout: GKTurnTimeoutDefault,
            match: data
        ) { [weak self] (error: Error?) in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    self.bootstrapPendingMatchIDs.remove(matchID)
                    self.debugLog("bootstrap error \(self.shortID(matchID)): \(error.localizedDescription)")
                    return
                }
                self.debugLog("bootstrap success \(self.shortID(matchID))")
                self.loadMatches()
            }
        }
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

    // MARK: - Lifecycle observers

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default

        // Refresh state and matches when the app becomes active
        let didBecomeActive = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshAuthenticationState()
            self.loadMatches()
        }

        // Ensure auth state is up-to-date on foreground entry
        let willEnterForeground = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshAuthenticationState()
        }

        // Pause background work when app goes to background
        let didEnterBackground = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.stopMatchStatusPolling()
                self.stopInboxPolling()
                self.stopPresenceHeartbeat()
            }
            Task {
                let playerID = GKLocalPlayer.local.gamePlayerID
                await self.presenceStore.deletePresence(playerID: playerID)
            }
        }

        let willTerminate = center.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                let playerID = GKLocalPlayer.local.gamePlayerID
                await self.presenceStore.deletePresence(playerID: playerID)
            }
        }

        notificationObservers.append(contentsOf: [didBecomeActive, willEnterForeground, didEnterBackground, willTerminate])
    }

    deinit {
        let center = NotificationCenter.default
        for token in notificationObservers {
            center.removeObserver(token)
        }
        notificationObservers.removeAll()
        Task { @MainActor in
            // Ensure timers are invalidated
            stopMatchStatusPolling()
            stopInboxPolling()
            stopPresenceHeartbeat()
        }
    }
}
