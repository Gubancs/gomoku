internal import GameKit
import SwiftUI
import Combine

/// Main local/online game board screen.
struct GameScreenView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @EnvironmentObject private var offlinePlayers: OfflinePlayersStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("soundEnabled") private var isSoundEnabled: Bool = true
    @StateObject private var game: GomokuGame
    @State private var zoomScale: CGFloat = 1.0
    @State private var recenterToken: Int = 0
    @State private var isResigning: Bool = false
    @State private var isConfirmingResign: Bool = false
    @State private var isEndgameOverlayVisible: Bool = false
    @State private var replayMoveIndex: Int = 0
    @State private var hasRecordedOfflineResult: Bool = false
    @State private var blackTimeRemaining: TimeInterval
    @State private var whiteTimeRemaining: TimeInterval
    @State private var shouldPlayMoveSound: Bool = false
    @State private var lastAppliedMatchSignature: String = ""
    @State private var timerTurnToken: String = ""
    @State private var wasWaitingForOpponent: Bool = false
    @State private var playedStartSoundMatchID: String?

    private let moveTimeLimit: TimeInterval

    private let defaultCellSize: CGFloat = 36
    private let minCellSize: CGFloat = 22
    private let maxCellSize: CGFloat = 64
    private let trailingControlSize: CGFloat = 36
    private let surfacePrimaryText = Color(red: 0.12, green: 0.13, blue: 0.16)
    private let surfaceSecondaryText = Color(red: 0.32, green: 0.34, blue: 0.38)

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let timerStateStoragePrefix = "gomoku.timer.state."

    private struct PersistedTimerState: Codable {
        let turnToken: String
        let blackRemaining: TimeInterval
        let whiteRemaining: TimeInterval
        let savedAt: Date
    }

    init(moveTimeLimit: TimeInterval = 50) {
        self.moveTimeLimit = moveTimeLimit
        _game = StateObject(wrappedValue: GomokuGame(moveTimeLimit: moveTimeLimit))
        _blackTimeRemaining = State(initialValue: moveTimeLimit)
        _whiteTimeRemaining = State(initialValue: moveTimeLimit)
    }

    var body: some View {
        GeometryReader { proxy in
            let reservedHeight: CGFloat = isReplayActive ? 270 : 220
            let boardHeight = max(360, proxy.size.height - reservedHeight)

            ZStack {
                background

                VStack(spacing: 12) {
                    playerCard(for: topDisplayedPlayer, isActive: game.currentPlayer == topDisplayedPlayer)

                    ZStack {
                        boardScroller(height: boardHeight)

                        if isWaitingForOpponent {
                            waitingBanner
                                .padding(.horizontal, 18)
                        }
                    }

                    if shouldShowReplayControls {
                        replayControls
                    }

                    playerCard(for: bottomDisplayedPlayer, isActive: game.currentPlayer == bottomDisplayedPlayer)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .allowsHitTesting(!isBlockingOverlay)

                if isResigning {
                    resigningOverlay
                } else if isConfirmingResign {
                    resignConfirmOverlay
                } else if gameCenter.incomingRematchMatchID != nil {
                    incomingRematchOverlay
                } else if gameCenter.isAwaitingRematch {
                    rematchOverlay
                }
            }
        }
        .onReceive(gameCenter.$currentMatch) { match in
            applyMatchUpdateIfNeeded(match)
        }
        .onAppear {
            applyMatchUpdateIfNeeded(gameCenter.currentMatch)
            shouldPlayMoveSound = true
            wasWaitingForOpponent = isWaitingForOpponent
            if isSoundEnabled {
                SoundEffects.prepare()
            }
        }
        .onReceive(timer) { _ in
            tickTimer()
        }
        .onChange(of: game.currentPlayer) { _ in
            handleTurnTransition()
        }
        .onChange(of: game.moves.count) { _ in
            if game.moves.isEmpty {
                hasRecordedOfflineResult = false
            }
        }
        .onChange(of: isGameOver) { newValue in
            isEndgameOverlayVisible = newValue
            replayMoveIndex = newValue ? replayMaxMoveIndex : 0
            if newValue {
                playGameEndSoundIfNeeded()
                recordOfflineResultIfNeeded()
            } else {
                hasRecordedOfflineResult = false
            }
        }
        .onChange(of: isSoundEnabled) { newValue in
            if newValue {
                SoundEffects.prepare()
            }
        }
        .onChange(of: game.lastMove) { newValue in
            guard shouldPlayMoveSound, let move = newValue else { return }
            playMoveSound(for: move.player)
        }
        .onChange(of: isWaitingForOpponent) { newValue in
            let didTransitionToReady = wasWaitingForOpponent && !newValue
            if didTransitionToReady {
                playMatchStartSoundIfNeeded()
            }
            wasWaitingForOpponent = newValue
        }
        .onDisappear {
            persistTimerState()
        }
        .toolbar {
            if isOnlineSession {
                ToolbarItem(placement: .topBarLeading) {
                    if isGameOver {
                        Button {
                            closeToDashboard()
                        } label: {
                            Label("Lobby", systemImage: "chevron.backward")
                        }
                    } else {
                        Button("Back") {
                            if gameCenter.isFindingMatch {
                                gameCenter.cancelMatchmaking()
                            }
                            gameCenter.currentMatch = nil
                            dismiss()
                        }
                    }
                }
            } else if isGameOver {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closeToDashboard()
                    } label: {
                        Label("Lobby", systemImage: "chevron.backward")
                    }
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    undoButton
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Moves: \(displayedMoveCount)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(chromePrimaryText)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                soundToggleButton

                NavigationLink {
                    SettingsView(symbolsLocked: !isGameOver)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .controlSize(.mini)
            }
        }
        .toolbar(.visible, for: .navigationBar)
    }

    private var soundToggleButton: some View {
        Button {
            isSoundEnabled.toggle()
        } label: {
            Image(systemName: isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
        }
        .buttonStyle(.plain)
        .controlSize(.mini)
        .accessibilityLabel(isSoundEnabled ? "Disable sounds" : "Enable sounds")
    }

    private func boardScroller(height: CGFloat) -> some View {
        let replaySnapshot = shouldShowReplayControls ? makeReplaySnapshot(upTo: currentReplayMoveIndex) : nil

        return ZoomableScrollView(
            zoomScale: $zoomScale,
            minZoomScale: minZoomScale,
            maxZoomScale: maxZoomScale,
            recenterToken: recenterToken
        ) {
            BoardView(
                game: game,
                cellSize: defaultCellSize,
                isInteractionEnabled: canInteractBoard,
                onCellTap: handleBoardTap,
                boardOverride: replaySnapshot?.board,
                lastMoveOverride: replaySnapshot?.lastMove,
                blackSymbolOverride: stoneSymbolOption(for: .black),
                whiteSymbolOverride: stoneSymbolOption(for: .white)
            )
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var waitingBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.wave.2.fill")
                .foregroundStyle(chromeSecondaryText)

            Text(waitingBannerTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(chromePrimaryText)

            if let code = waitingPartyCode {
                VStack(spacing: 4) {
                    Text("Party Code")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(chromeSecondaryText)
                    Text(code)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(chromePrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Text(waitingBannerSubtitle)
                .font(.caption)
                .foregroundStyle(chromeSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                cancelSearchingAndReturnToLobby()
            } label: {
                Text("Cancel")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.86, green: 0.18, blue: 0.16))
            .accessibilityLabel("Cancel matchmaking and return to lobby")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: 320)
        .multilineTextAlignment(.center)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func moveTimer(for player: Player) -> some View {
        let remaining = timerRemaining(for: player)
        return MoveTimerView(
            timeRemaining: remaining,
            timeLimit: moveTimeLimit,
            warningThreshold: 30,
            criticalThreshold: 10
        )
        .frame(width: trailingControlSize, height: trailingControlSize)
        .accessibilityLabel("\(player.displayName) timer")
        .accessibilityValue("\(Int(remaining)) seconds remaining")
    }

    private func resignButton(size: CGFloat) -> some View {
        Button(role: .destructive) {
            isConfirmingResign = true
        } label: {
            Image(systemName: "flag.slash")
                .font(.system(size: size * 0.45, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(0.95))
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.86, green: 0.18, blue: 0.16),
                    Color(red: 0.66, green: 0.10, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 3, x: 0, y: 2)
        .disabled(isResigning)
        .accessibilityLabel("Resign")
    }

    @ViewBuilder
    private var undoButton: some View {
        if canUndo {
            Button {
                handleUndo()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Undo")
                }
            }
            .accessibilityHint("Reverts the last move in offline games")
        }
    }

    private var replayControls: some View {
        HStack(spacing: 12) {
            Button {
                stepReplayBackward()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(!canStepReplayBackward)

            Text("Move: \(currentReplayMoveIndex)/\(replayMaxMoveIndex)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(chromeSecondaryText)
                .monospacedDigit()

            Button {
                stepReplayForward()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(!canStepReplayForward)
        }
        .frame(maxWidth: .infinity)
    }

    private var endgameControls: some View {
        VStack(spacing: 16) {
            if game.isDraw {
                Text("Draw")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                VStack(spacing: 10) {
                    endgamePlayerCard(for: .black, isWinner: false)
                    endgamePlayerCard(for: .white, isWinner: false)
                }
            } else if let winner = game.winner {
                endgamePlayerCard(for: winner, isWinner: true)
                endgamePlayerCard(for: winner.next, isWinner: false)
            }

            HStack(spacing: 12) {
                Button {
                    enterReplayMode()
                } label: {
                    Text("Close")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button {
                    startRematch()
                } label: {
                    Text("Rematch")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.23, green: 0.18, blue: 0.12))
                .disabled(gameCenter.isAwaitingRematch)
            }
        }
    }

    private func endgamePlayerCard(for player: Player, isWinner: Bool) -> some View {
        let name = playerName(for: player)
        let newScore = endgameNewRating(for: player)
        let avatarSize: CGFloat = 56
        let trophySize: CGFloat = avatarSize

        return HStack(spacing: 12) {
            endgameAvatar(for: player, size: avatarSize)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(cardPrimaryText)

                    playerSymbolBadge(for: player)
                }

                if let newScore {
                    Text(verbatim: "\(scoreCaption): \(newScore)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cardSecondaryText)
                } else {
                    Text(verbatim: "\(scoreCaption): \(playerScore(for: player))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(cardSecondaryText)
                }
            }

            Spacer(minLength: 0)

            trophyBadge(size: trophySize)
                .opacity(isWinner ? 1 : 0)
                .accessibilityHidden(!isWinner)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.12, green: 0.18, blue: 0.32).opacity(0.94),
                        Color(red: 0.24, green: 0.27, blue: 0.34).opacity(0.94)
                    ]
                    : [
                        Color.white.opacity(0.75),
                        Color.white.opacity(0.68)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.6), lineWidth: 1)
        )
    }

    private func endgameAvatar(for player: Player, size: CGFloat) -> some View {
        let image = gameCenter.avatarImage(for: playerProfile(for: player))
        let initials = playerInitials(for: player)

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.9))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private func trophyBadge(size: CGFloat) -> some View {
        ZStack {
            if colorScheme != .dark {
                Circle()
                    .fill(Color(red: 0.99, green: 0.97, blue: 0.90))
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.55), lineWidth: 1.2)
                    )
            }
            Image(systemName: "trophy.fill")
                .font(.system(size: size * 0.56, weight: .black))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.91, blue: 0.36),
                            Color(red: 0.95, green: 0.64, blue: 0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(
                    color: colorScheme == .dark
                        ? Color(red: 0.12, green: 0.20, blue: 0.34).opacity(0.45)
                        : .clear,
                    radius: colorScheme == .dark ? 6 : 0,
                    x: 0,
                    y: 2
                )
        }
        .frame(width: size, height: size)
    }

    private var endgameOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            endgameControls
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 360)
                .background(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color(red: 0.11, green: 0.18, blue: 0.33).opacity(0.96),
                                Color(red: 0.22, green: 0.27, blue: 0.36).opacity(0.96)
                            ]
                            : [
                                Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.95),
                                Color(red: 0.82, green: 0.90, blue: 1.0).opacity(0.95)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.55), lineWidth: 1)
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isGameOver)
    }

    private var resigningOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)

                Text("Finishing match…")
                    .font(.headline)

                Text("Updating Game Center and returning to the lobby.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 320)
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.11, green: 0.18, blue: 0.33).opacity(0.96),
                            Color(red: 0.22, green: 0.27, blue: 0.36).opacity(0.96)
                        ]
                        : [
                            Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.95),
                            Color(red: 0.82, green: 0.90, blue: 1.0).opacity(0.95)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        }
    }

    private var rematchOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)

                Text("Waiting for rematch…")
                    .font(.headline)

                Text("The new game will start once your opponent accepts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 320)
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.11, green: 0.18, blue: 0.33).opacity(0.96),
                            Color(red: 0.22, green: 0.27, blue: 0.36).opacity(0.96)
                        ]
                        : [
                            Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.95),
                            Color(red: 0.82, green: 0.90, blue: 1.0).opacity(0.95)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        }
    }

    private var incomingRematchOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Rematch request")
                    .font(.headline)

                Text(rematchRequesterText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        gameCenter.declineIncomingRematch()
                    } label: {
                        Text("Decline")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.76, green: 0.24, blue: 0.20))
                    .disabled(gameCenter.isHandlingIncomingRematch)

                    Button {
                        gameCenter.acceptIncomingRematch()
                    } label: {
                        Text("Accept")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(gameCenter.isHandlingIncomingRematch)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 360)
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.11, green: 0.18, blue: 0.33).opacity(0.96),
                            Color(red: 0.22, green: 0.27, blue: 0.36).opacity(0.96)
                        ]
                        : [
                            Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.95),
                            Color(red: 0.82, green: 0.90, blue: 1.0).opacity(0.95)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        }
    }

    private var resignConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Resign match?")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("This will count as a loss for you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button {
                        isConfirmingResign = false
                    } label: {
                        Text("Cancel")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        isConfirmingResign = false
                        handleResign()
                    } label: {
                        Text("Resign")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.86, green: 0.18, blue: 0.16))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 360)
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.11, green: 0.18, blue: 0.33).opacity(0.96),
                            Color(red: 0.22, green: 0.27, blue: 0.36).opacity(0.96)
                        ]
                        : [
                            Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.95),
                            Color(red: 0.82, green: 0.90, blue: 1.0).opacity(0.95)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isConfirmingResign)
    }

    private var background: some View {
        RadialGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.08, green: 0.12, blue: 0.22),
                    Color(red: 0.18, green: 0.20, blue: 0.26)
                ]
                : [
                    Color(red: 0.93, green: 0.97, blue: 1.0),
                    Color(red: 0.80, green: 0.90, blue: 0.98)
                ],
            center: .top,
            startRadius: 120,
            endRadius: 700
        )
        .ignoresSafeArea()
    }

    private var chromePrimaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.93, blue: 0.98)
            : surfacePrimaryText
    }

    private var chromeSecondaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.74, green: 0.79, blue: 0.88)
            : surfaceSecondaryText
    }

    private var cardPrimaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.89, green: 0.93, blue: 0.98)
            : surfacePrimaryText
    }

    private var cardSecondaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.72, green: 0.79, blue: 0.90)
            : surfaceSecondaryText
    }

    private func playerCard(for player: Player, isActive: Bool) -> some View {
        let name = playerName(for: player)
        let score = playerScore(for: player)
        let scoreDelta = playerScoreDelta(for: player)
        let cardGradient = LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.12, green: 0.18, blue: 0.32),
                    Color(red: 0.24, green: 0.27, blue: 0.34)
                ]
                : [
                    Color(red: 0.92, green: 0.97, blue: 1.0),
                    Color(red: 0.74, green: 0.86, blue: 0.98)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return HStack(spacing: 10) {
            playerAvatar(for: player)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(cardPrimaryText)
                        .lineLimit(1)

                    playerSymbolBadge(for: player)
                }

                HStack(spacing: 6) {
                    Text(verbatim: "\(scoreCaption): \(score)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(cardSecondaryText)

                    if let scoreDelta {
                        Text(verbatim: formattedScoreDelta(scoreDelta))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(scoreDeltaColor(scoreDelta))
                    }
                }
            }

            Spacer(minLength: 0)

            if shouldShowTimer(for: player) {
                moveTimer(for: player)
            } else if shouldShowWinnerTimerSlotTrophy(for: player) {
                winnerTimerSlotTrophy
            }

            if shouldShowResignButton(for: player) {
                resignButton(size: trailingControlSize)
            } else if shouldShowRematchButton(for: player) {
                rematchIconButton(size: trailingControlSize)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(cardGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isActive ? 0.25 : 0.16), radius: 8, x: 0, y: 6)
        .shadow(color: isActive ? Color(red: 0.35, green: 0.58, blue: 0.95).opacity(colorScheme == .dark ? 0.28 : 0.5) : .clear, radius: 14, x: 0, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isActive
                        ? Color(red: 0.35, green: 0.58, blue: 0.95).opacity(colorScheme == .dark ? 0.62 : 0.7)
                        : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)),
                    lineWidth: isActive ? 2 : 1
                )
        )
    }

    private func playerAvatar(for player: Player) -> some View {
        let avatarSize: CGFloat = 48
        let image = gameCenter.avatarImage(for: playerProfile(for: player))

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 2)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.black.opacity(0.35))
                    .padding(6)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private func playerSymbolBadge(for player: Player) -> some View {
        let glyph = stoneSymbolOption(for: player).glyph
        return Text(glyph)
            .font(.caption2.weight(.bold))
            .foregroundStyle(StoneSymbolConfiguration.displayColor(for: player, colorScheme: colorScheme))
            .frame(width: 20, height: 20)
            .background(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.62))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .accessibilityLabel("\(player.displayName) symbol \(glyph)")
    }

    private var minZoomScale: CGFloat {
        minCellSize / defaultCellSize
    }

    private var maxZoomScale: CGFloat {
        maxCellSize / defaultCellSize
    }

    private var isOnlineMatch: Bool {
        gameCenter.currentMatch != nil
    }

    private var topDisplayedPlayer: Player {
        guard let match = gameCenter.currentMatch,
              let local = gameCenter.localPlayerColor(in: match) else {
            return .black
        }
        return local
    }

    private var bottomDisplayedPlayer: Player {
        topDisplayedPlayer.next
    }

    private var isOnlineSession: Bool {
        isOnlineMatch || gameCenter.isFindingMatch
    }

    private var isWaitingForOpponent: Bool {
        guard gameCenter.isFindingMatch else { return false }
        guard let match = gameCenter.currentMatch else { return true }
        return !gameCenter.isMatchReady(match)
    }

    private var waitingPartyCode: String? {
        guard gameCenter.isPartyMode else { return nil }
        guard gameCenter.partyRole == .host else { return nil }
        guard let code = gameCenter.partyCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty else {
            return nil
        }
        return code
    }

    private var isWaitingAsPartyJoiner: Bool {
        gameCenter.isPartyMode && gameCenter.partyRole == .join
    }

    private var waitingBannerTitle: String {
        if waitingPartyCode != nil {
            return "Waiting for other player to join"
        }
        if isWaitingAsPartyJoiner {
            return "Joining party match..."
        }
        return "Searching for player..."
    }

    private var waitingBannerSubtitle: String {
        if waitingPartyCode != nil {
            return "Share this code with your friend. The match starts automatically when they join."
        }
        if isWaitingAsPartyJoiner {
            return "Connecting to host. The match starts automatically when the connection is ready."
        }
        return "The board is ready. The match starts automatically when opponent joins."
    }

    private var scoreCaption: String {
        isOnlineSession ? "ELO" : "PTS"
    }

    private var rematchRequesterText: String {
        if let name = gameCenter.incomingRematchRequesterName, !name.isEmpty {
            return "\(name) wants to play again."
        }
        return "Your opponent wants to play again."
    }

    private var displayedMoveCount: Int {
        if isOnlineSession {
            return game.board.reduce(0) { partial, row in
                partial + row.compactMap { $0 }.count
            }
        }
        return game.moves.count
    }

    private var isDebugMatch: Bool {
        gameCenter.isDebugMatchActive
    }

    private var isEndgameOverlayActive: Bool {
        false
    }

    private var isReplayActive: Bool {
        isGameOver && !isEndgameOverlayVisible
    }

    private var hasReplayHistory: Bool {
        !game.moves.isEmpty
    }

    private var shouldShowReplayControls: Bool {
        isReplayActive && hasReplayHistory
    }

    private var isBlockingOverlay: Bool {
        isResigning || isConfirmingResign || gameCenter.isAwaitingRematch || gameCenter.incomingRematchMatchID != nil || isEndgameOverlayActive
    }

    private var replayMaxMoveIndex: Int {
        game.moves.count
    }

    private var currentReplayMoveIndex: Int {
        min(max(replayMoveIndex, 0), replayMaxMoveIndex)
    }

    private var canStepReplayBackward: Bool {
        shouldShowReplayControls && currentReplayMoveIndex > 0
    }

    private var canStepReplayForward: Bool {
        shouldShowReplayControls && currentReplayMoveIndex < replayMaxMoveIndex
    }

    private var canUndo: Bool {
        !isOnlineSession && !isGameOver && !game.moves.isEmpty && !isBlockingOverlay
    }

    private var isLocalTurn: Bool {
        guard let match = gameCenter.currentMatch else { return false }
        if let localColor = gameCenter.localPlayerColor(in: match) {
            return localColor == game.currentPlayer && game.winner == nil && !game.isDraw
        }
        return gameCenter.isLocalPlayersTurn(in: match) && game.winner == nil && !game.isDraw
    }

    private var canInteractBoard: Bool {
        guard !isReplayActive else { return false }
        guard !isWaitingForOpponent else { return false }
        return isLocalTurn
    }

    private func playerName(for player: Player) -> String {
        if isOnlineSession {
            guard let match = gameCenter.currentMatch else {
                return isLocalPlayer(player) ? localOnlineDisplayName : "Waiting for player..."
            }
            let index = player == .black ? 0 : 1
            if match.participants.indices.contains(index),
               let displayName = match.participants[index].player?.displayName,
               !displayName.isEmpty {
                return displayName
            }
            return isLocalPlayer(player) ? localOnlineDisplayName : "Waiting for player..."
        }
        return offlinePlayers.displayName(for: player)
    }

    private func playerInitials(for player: Player) -> String {
        let name = playerName(for: player).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = name.split(whereSeparator: \.isWhitespace)
        let initials = parts.prefix(2).compactMap { part -> String? in
            guard let first = part.first(where: { $0.isLetter || $0.isNumber }) else { return nil }
            return String(first)
        }
        let result = initials.joined().uppercased()
        if !result.isEmpty {
            return result
        }
        return player == .black ? "B" : "W"
    }

    private func playerScore(for player: Player) -> String {
        if isOnlineSession {
            guard let match = gameCenter.currentMatch else {
                return isLocalPlayer(player) ? "\(gameCenter.localEloRating)" : "-"
            }
            let index = player == .black ? 0 : 1
            if match.participants.indices.contains(index),
               let participant = match.participants[index].player {
                return "\(gameCenter.eloRating(for: participant))"
            }
            return isLocalPlayer(player) ? "\(gameCenter.localEloRating)" : "-"
        }
        return "\(offlinePlayers.points(for: player) ?? 0)"
    }

    private func playerProfile(for player: Player) -> GKPlayer? {
        guard let match = gameCenter.currentMatch else { return nil }
        let index = player == .black ? 0 : 1
        guard match.participants.indices.contains(index) else { return nil }
        return match.participants[index].player
    }

    private func stoneSymbolOption(for player: Player) -> StoneSymbolOption {
        if isOnlineSession,
           let match = gameCenter.currentMatch {
            let index = player == .black ? 0 : 1
            if match.participants.indices.contains(index),
               let playerID = match.participants[index].player?.gamePlayerID,
               let preferences = game.symbolPreferences(for: playerID) {
                let rawValue = player == .black
                    ? preferences.blackSymbolRawValue
                    : preferences.whiteSymbolRawValue
                return StoneSymbolConfiguration.validatedOption(
                    rawValue: rawValue,
                    fallback: StoneSymbolConfiguration.option(for: player)
                )
            }
        }

        return StoneSymbolConfiguration.option(for: player)
    }

    private func handleBoardTap(row: Int, col: Int) {
        guard !isWaitingForOpponent else { return }
        let beforeCount = game.moves.count

        if let match = gameCenter.currentMatch {
            guard isLocalTurn else { return }
            game.placeStone(row: row, col: col)
            if game.moves.count != beforeCount || game.winner != nil || game.isDraw {
                gameCenter.submitTurn(game: game, match: match)
            }
        } else {
            game.placeStone(row: row, col: col)
        }
    }

    private func handleUndo() {
        guard canUndo else { return }
        game.undoLastMove()
    }

    private func enterReplayMode() {
        replayMoveIndex = replayMaxMoveIndex
        isEndgameOverlayVisible = false
    }

    private func stepReplayBackward() {
        guard canStepReplayBackward else { return }
        replayMoveIndex = currentReplayMoveIndex - 1
    }

    private func stepReplayForward() {
        guard canStepReplayForward else { return }
        replayMoveIndex = currentReplayMoveIndex + 1
    }

    private func makeReplaySnapshot(upTo moveIndex: Int) -> (board: [[Player?]], lastMove: LastMove?) {
        var replayBoard: [[Player?]] = Array(
            repeating: Array<Player?>(repeating: nil, count: GomokuGame.boardSize),
            count: GomokuGame.boardSize
        )
        let clampedMoveIndex = min(max(0, moveIndex), game.moves.count)
        guard clampedMoveIndex > 0 else {
            return (board: replayBoard, lastMove: nil)
        }

        for move in game.moves.prefix(clampedMoveIndex) {
            replayBoard[move.row][move.col] = move.player
        }

        let last = game.moves[clampedMoveIndex - 1]
        return (
            board: replayBoard,
            lastMove: LastMove(row: last.row, col: last.col, player: last.player)
        )
    }

    private func recordOfflineResultIfNeeded() {
        guard !isOnlineMatch else { return }
        guard !hasRecordedOfflineResult else { return }
        guard isGameOver else { return }
        guard let blackID = offlinePlayers.playerID(for: .black),
              let whiteID = offlinePlayers.playerID(for: .white) else {
            return
        }

        offlinePlayers.recordMatchResult(
            winner: game.winner,
            isDraw: game.isDraw,
            blackPlayerID: blackID,
            whitePlayerID: whiteID
        )
        hasRecordedOfflineResult = true
    }

    private func playMoveSound(for player: Player) {
        guard isSoundEnabled else { return }
        SoundEffects.playMove(for: player)
    }

    private func playMatchStartSoundIfNeeded() {
        guard isSoundEnabled else { return }
        guard let matchID = gameCenter.currentMatch?.matchID, !matchID.isEmpty else { return }
        guard playedStartSoundMatchID != matchID else { return }
        playedStartSoundMatchID = matchID
        SoundEffects.playMatchStart()
    }

    private func playGameEndSoundIfNeeded() {
        guard isSoundEnabled else { return }
        guard let winner = game.winner else { return }

        if isOnlineMatch {
            if isLocalPlayer(winner) {
                SoundEffects.playVictory()
            } else {
                SoundEffects.playDefeat()
            }
            return
        }

        // Offline has no dedicated local account; keep a stable point of view.
        if winner == .black {
            SoundEffects.playVictory()
        } else {
            SoundEffects.playDefeat()
        }
    }

    private func handleResign() {
        let resigningPlayer = currentResigningPlayer()
        game.resign(player: resigningPlayer)

        if isOnlineMatch {
            isResigning = true
            gameCenter.resignCurrentMatch(using: game, shouldClearCurrentMatch: false) { _ in
                isResigning = false
            }
        }
    }

    private func rematchIconButton(size: CGFloat) -> some View {
        Button {
            startRematch()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: size * 0.45, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(0.96))
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.23, green: 0.62, blue: 0.38),
                    Color(red: 0.14, green: 0.46, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 3, x: 0, y: 2)
        .disabled(gameCenter.isAwaitingRematch)
        .accessibilityLabel("Rematch")
    }

    private func resetTimerForCurrentPlayer() {
        setTimerRemaining(moveTimeLimit, for: game.currentPlayer)
    }

    private func timerRemaining(for player: Player) -> TimeInterval {
        player == .black ? blackTimeRemaining : whiteTimeRemaining
    }

    private func setTimerRemaining(_ value: TimeInterval, for player: Player) {
        let clamped = max(0, value)
        if player == .black {
            blackTimeRemaining = clamped
        } else {
            whiteTimeRemaining = clamped
        }
    }

    private func tickTimer() {
        guard !isGameOver else { return }
        guard !isWaitingForOpponent else { return }
        let activePlayer = game.currentPlayer
        let remaining = timerRemaining(for: activePlayer)
        guard remaining > 0 else { return }

        let updated = max(0, remaining - 1)
        setTimerRemaining(updated, for: activePlayer)
        persistTimerState()
        if updated <= 0 {
            guard canEnforceTimeoutForActivePlayer else { return }
            handleTimeout()
        }
    }

    private var canEnforceTimeoutForActivePlayer: Bool {
        guard isOnlineMatch else { return true }
        return isLocalTurn
    }

    private func handleTimeout() {
        guard !isGameOver else { return }
        var onlineMatch: GKTurnBasedMatch?
        var shouldSubmitTimeout = false
        if let match = gameCenter.currentMatch {
            onlineMatch = match
            // Decide authority before mutating local game state.
            shouldSubmitTimeout = gameCenter.isLocalPlayersTurn(in: match)
        }

        game.timeoutCurrentPlayer()

        if let match = onlineMatch, shouldSubmitTimeout {
            gameCenter.submitTurn(game: game, match: match)
        }
    }

    private func applyMatchUpdateIfNeeded(_ match: GKTurnBasedMatch?) {
        guard let match else {
            lastAppliedMatchSignature = ""
            return
        }

        let signature = matchUpdateSignature(match)
        guard signature != lastAppliedMatchSignature else { return }
        lastAppliedMatchSignature = signature

        let loadedState = gameCenter.loadState(from: match)
        let fallbackState = game.makeState()
        let effectiveState = resolveEndedMatchState(for: match, loadedState: loadedState, fallbackState: fallbackState)
        game.apply(state: effectiveState)
        restoreOrResetTimerState()
        replayMoveIndex = game.moves.count
    }

    private func matchUpdateSignature(_ match: GKTurnBasedMatch) -> String {
        let currentID = match.currentParticipant?.player?.gamePlayerID ?? "-"
        let statusRaw = match.status.rawValue
        let dataCount = match.matchData?.count ?? 0
        let dataHash = match.matchData?.hashValue ?? 0
        let outcomes = match.participants.map { String($0.matchOutcome.rawValue) }.joined(separator: ",")
        return "\(match.matchID)|\(statusRaw)|\(currentID)|\(dataCount)|\(dataHash)|\(outcomes)"
    }

    private func resolveEndedMatchState(
        for match: GKTurnBasedMatch,
        loadedState: GameState?,
        fallbackState: GameState
    ) -> GameState {
        let base = loadedState ?? fallbackState
        guard match.status == .ended else { return base }
        if base.winner != nil || base.isDraw { return base }

        if match.participants.contains(where: { $0.matchOutcome == .tied }) {
            return GameState(
                board: base.board,
                currentPlayer: base.currentPlayer,
                winner: nil,
                isDraw: true,
                lastMove: base.lastMove,
                winningLine: nil,
                partyCode: base.partyCode,
                playerSymbolPreferences: base.playerSymbolPreferences
            )
        }

        if let winnerIndex = match.participants.firstIndex(where: { $0.matchOutcome == .won }) {
            let winner: Player = winnerIndex == 0 ? .black : .white
            return GameState(
                board: base.board,
                currentPlayer: base.currentPlayer,
                winner: winner,
                isDraw: false,
                lastMove: base.lastMove,
                winningLine: base.winningLine,
                partyCode: base.partyCode,
                playerSymbolPreferences: base.playerSymbolPreferences
            )
        }

        if let loserIndex = match.participants.firstIndex(where: {
            $0.matchOutcome == .lost || $0.matchOutcome == .quit || $0.matchOutcome == .timeExpired
        }) {
            let winner: Player = loserIndex == 0 ? .white : .black
            return GameState(
                board: base.board,
                currentPlayer: base.currentPlayer,
                winner: winner,
                isDraw: false,
                lastMove: base.lastMove,
                winningLine: base.winningLine,
                partyCode: base.partyCode,
                playerSymbolPreferences: base.playerSymbolPreferences
            )
        }

        return base
    }

    private var isGameOver: Bool {
        game.winner != nil || game.isDraw
    }

    private var resultText: String {
        if let winner = game.winner {
            return "Winner: \(playerName(for: winner))"
        }
        return "Draw"
    }

    private func closeToDashboard() {
        if isOnlineSession {
            if gameCenter.isFindingMatch {
                gameCenter.cancelMatchmaking()
            }
            gameCenter.currentMatch = nil
        } else if isDebugMatch {
            gameCenter.isDebugMatchActive = false
        }
        dismiss()
    }

    private func cancelSearchingAndReturnToLobby() {
        if gameCenter.isFindingMatch {
            gameCenter.cancelMatchmaking()
        }
        gameCenter.currentMatch = nil
        dismiss()
    }

    private func startRematch() {
        if isOnlineMatch, let match = gameCenter.currentMatch {
            gameCenter.requestRematch(for: match)
        } else {
            game.reset()
            resetTimerForCurrentPlayer()
            persistTimerState()
            hasRecordedOfflineResult = false
        }
    }

    private func handleTurnTransition() {
        let token = currentTurnToken
        if token == timerTurnToken {
            return
        }
        timerTurnToken = token
        resetTimerForCurrentPlayer()
        persistTimerState()
    }

    private func restoreOrResetTimerState() {
        let token = currentTurnToken
        if let restored = loadPersistedTimerState(), restored.turnToken == token {
            var black = restored.blackRemaining
            var white = restored.whiteRemaining
            let elapsed = max(0, Date().timeIntervalSince(restored.savedAt))
            if !isGameOver {
                if game.currentPlayer == .black {
                    black = max(0, black - elapsed)
                } else {
                    white = max(0, white - elapsed)
                }
            }
            blackTimeRemaining = black
            whiteTimeRemaining = white
            timerTurnToken = token
            persistTimerState()
            return
        }

        timerTurnToken = token
        resetTimerForCurrentPlayer()
        persistTimerState()
    }

    private var currentTurnToken: String {
        if let match = gameCenter.currentMatch {
            return matchUpdateSignature(match)
        }
        let moveCount = game.moves.count
        let current = game.currentPlayer.rawValue
        let last = game.lastMove
        let row = last?.row ?? -1
        let col = last?.col ?? -1
        return "offline|\(current)|\(moveCount)|\(row)|\(col)"
    }

    private var timerStateStorageKey: String {
        if let matchID = gameCenter.currentMatch?.matchID, !matchID.isEmpty {
            return "\(timerStateStoragePrefix)\(matchID)"
        }
        return "\(timerStateStoragePrefix)offline"
    }

    private func persistTimerState() {
        guard !timerTurnToken.isEmpty else { return }
        let payload = PersistedTimerState(
            turnToken: timerTurnToken,
            blackRemaining: blackTimeRemaining,
            whiteRemaining: whiteTimeRemaining,
            savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: timerStateStorageKey)
    }

    private func loadPersistedTimerState() -> PersistedTimerState? {
        guard let data = UserDefaults.standard.data(forKey: timerStateStorageKey) else { return nil }
        return try? JSONDecoder().decode(PersistedTimerState.self, from: data)
    }

    private func shouldShowResignButton(for player: Player) -> Bool {
        guard !isGameOver else { return false }
        guard !isWaitingForOpponent else { return false }
        if isOnlineMatch {
            return isLocalPlayer(player)
        }
        return player == game.currentPlayer
    }

    private func shouldShowRematchButton(for player: Player) -> Bool {
        guard isGameOver else { return false }
        guard !isWaitingForOpponent else { return false }
        if isOnlineMatch {
            return isLocalPlayer(player)
        }
        return player == game.currentPlayer
    }

    private func shouldShowTimer(for player: Player) -> Bool {
        guard !isGameOver else { return false }
        guard !isWaitingForOpponent else { return false }
        return player == game.currentPlayer
    }

    private var winnerTrophyControlSize: CGFloat {
        trailingControlSize + 8
    }

    private var winnerTimerSlotTrophy: some View {
        trophyBadge(size: winnerTrophyControlSize)
            .frame(width: winnerTrophyControlSize, height: winnerTrophyControlSize)
            .accessibilityLabel("Winner")
    }

    private func shouldShowWinnerTimerSlotTrophy(for player: Player) -> Bool {
        guard isGameOver else { return false }
        return game.winner == player
    }

    private func isLocalPlayer(_ player: Player) -> Bool {
        guard let match = gameCenter.currentMatch else { return player == .black }
        return gameCenter.localPlayerColor(in: match) == player
    }

    private func currentResigningPlayer() -> Player {
        guard let match = gameCenter.currentMatch else { return game.currentPlayer }
        return gameCenter.localPlayerColor(in: match) ?? game.currentPlayer
    }

    private var localOnlineDisplayName: String {
        let name = GKLocalPlayer.local.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        return "You"
    }

    private func endgameNewRating(for player: Player) -> Int? {
        guard isOnlineMatch else { return nil }
        guard let match = gameCenter.currentMatch else { return nil }
        guard let change = gameCenter.projectedEloChange(for: match, winner: game.winner, isDraw: game.isDraw) else {
            return nil
        }
        if isLocalPlayer(player) {
            return change.localRating + change.localDelta
        }
        return change.opponentRating + change.opponentDelta
    }

    private func playerScoreDelta(for player: Player) -> Int? {
        guard isOnlineMatch else { return nil }
        guard let match = gameCenter.currentMatch else { return nil }
        guard let change = gameCenter.projectedEloChange(for: match, winner: game.winner, isDraw: game.isDraw) else {
            return nil
        }
        return isLocalPlayer(player) ? change.localDelta : change.opponentDelta
    }

    private func formattedScoreDelta(_ delta: Int) -> String {
        if delta > 0 {
            return "+\(delta)"
        }
        return "\(delta)"
    }

    private func scoreDeltaColor(_ delta: Int) -> Color {
        if delta > 0 {
            return Color(red: 0.16, green: 0.68, blue: 0.30)
        }
        if delta < 0 {
            return Color(red: 0.86, green: 0.20, blue: 0.24)
        }
        return cardSecondaryText
    }
}

#Preview {
    GameScreenView()
        .environmentObject(GameCenterManager())
        .environmentObject(OfflinePlayersStore())
}
