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
    @State private var timeRemaining: TimeInterval
    @State private var shouldPlayMoveSound: Bool = false

    private let moveTimeLimit: TimeInterval

    private let defaultCellSize: CGFloat = 36
    private let minCellSize: CGFloat = 22
    private let maxCellSize: CGFloat = 64
    private let trailingControlSize: CGFloat = 36
    private let surfacePrimaryText = Color(red: 0.12, green: 0.13, blue: 0.16)
    private let surfaceSecondaryText = Color(red: 0.32, green: 0.34, blue: 0.38)

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(moveTimeLimit: TimeInterval = 50) {
        self.moveTimeLimit = moveTimeLimit
        _game = StateObject(wrappedValue: GomokuGame(moveTimeLimit: moveTimeLimit))
        _timeRemaining = State(initialValue: moveTimeLimit)
    }

    var body: some View {
        GeometryReader { proxy in
            let reservedHeight: CGFloat = isReplayActive ? 270 : 220
            let boardHeight = max(360, proxy.size.height - reservedHeight)

            ZStack {
                background

                VStack(spacing: 12) {
                    playerCard(for: .black, isActive: game.currentPlayer == .black)

                    boardScroller(height: boardHeight)

                    if shouldShowReplayControls {
                        replayControls
                    }

                    if let headToHeadText {
                        Text(verbatim: headToHeadText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(chromeSecondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55))
                            )
                    }

                    playerCard(for: .white, isActive: game.currentPlayer == .white)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .allowsHitTesting(!isBlockingOverlay)

                if isResigning {
                    resigningOverlay
                } else if isConfirmingResign {
                    resignConfirmOverlay
                } else if gameCenter.isAwaitingRematch {
                    rematchOverlay
                } else if isGameOver && isEndgameOverlayVisible {
                    endgameOverlay
                }
            }
        }
        .onChange(of: gameCenter.currentMatch?.matchID) { _ in
            guard let match = gameCenter.currentMatch else { return }
            if let state = gameCenter.loadState(from: match) {
                game.apply(state: state)
            } else {
                game.reset()
            }
            resetTimer()
            replayMoveIndex = game.moves.count
        }
        .onAppear {
            resetTimer()
            shouldPlayMoveSound = true
            if isSoundEnabled {
                SoundEffects.prepare()
            }
        }
        .onReceive(timer) { _ in
            tickTimer()
        }
        .onChange(of: game.currentPlayer) { _ in
            resetTimer()
        }
        .onChange(of: game.moves.count) { _ in
            resetTimer()
            if game.moves.isEmpty {
                hasRecordedOfflineResult = false
            }
        }
        .onChange(of: isLocalTurn) { newValue in
            if newValue {
                resetTimer()
            }
        }
        .onChange(of: isGameOver) { newValue in
            isEndgameOverlayVisible = newValue
            replayMoveIndex = newValue ? replayMaxMoveIndex : 0
            if newValue {
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
        .toolbar {
            if isOnlineMatch {
                ToolbarItem(placement: .topBarLeading) {
                    if isGameOver {
                        Button {
                            closeToDashboard()
                        } label: {
                            Label("Lobby", systemImage: "chevron.backward")
                        }
                    } else {
                        Button("Back") {
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
                Text("Moves: \(game.moves.count)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(chromePrimaryText)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                soundToggleButton

                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .controlSize(.mini)
            }
        }
        .toolbar(isEndgameOverlayActive ? .hidden : .visible, for: .navigationBar)
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
                isInteractionEnabled: isLocalTurn && !isReplayActive,
                onCellTap: handleBoardTap,
                boardOverride: replaySnapshot?.board,
                lastMoveOverride: replaySnapshot?.lastMove
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

    private var moveTimer: some View {
        MoveTimerView(
            timeRemaining: timeRemaining,
            timeLimit: moveTimeLimit,
            warningThreshold: 30,
            criticalThreshold: 10
        )
        .frame(width: trailingControlSize, height: trailingControlSize)
        .accessibilityLabel("Move timer")
        .accessibilityValue("\(Int(timeRemaining)) seconds remaining")
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
                Text(name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(cardPrimaryText)

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
                Text(name)
                    .font(.headline)
                    .foregroundStyle(cardPrimaryText)
                    .lineLimit(1)

                Text(verbatim: "\(scoreCaption): \(score)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cardSecondaryText)
            }

            Spacer(minLength: 0)

            if isActive && !isGameOver {
                moveTimer
            }

            if shouldShowResignButton(for: player) {
                resignButton(size: trailingControlSize)
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

    private var minZoomScale: CGFloat {
        minCellSize / defaultCellSize
    }

    private var maxZoomScale: CGFloat {
        maxCellSize / defaultCellSize
    }

    private var isOnlineMatch: Bool {
        gameCenter.currentMatch != nil
    }

    private var scoreCaption: String {
        isOnlineMatch ? "ELO" : "PTS"
    }

    private var headToHeadText: String? {
        guard isOnlineMatch, let summary = gameCenter.headToHeadSummary else {
            return nil
        }
        return "Head-to-head: \(summary.formattedScore)"
    }

    private var isDebugMatch: Bool {
        gameCenter.isDebugMatchActive
    }

    private var isEndgameOverlayActive: Bool {
        isGameOver && isEndgameOverlayVisible
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
        isResigning || isConfirmingResign || gameCenter.isAwaitingRematch || isEndgameOverlayActive
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
        !isOnlineMatch && !isGameOver && !game.moves.isEmpty && !isBlockingOverlay
    }

    private var isLocalTurn: Bool {
        guard let match = gameCenter.currentMatch else { return true }
        if let localColor = gameCenter.localPlayerColor(in: match) {
            return localColor == game.currentPlayer && game.winner == nil && !game.isDraw
        }
        return gameCenter.isLocalPlayersTurn(in: match) && game.winner == nil && !game.isDraw
    }

    private func playerName(for player: Player) -> String {
        guard let match = gameCenter.currentMatch else {
            return offlinePlayers.displayName(for: player)
        }
        let index = player == .black ? 0 : 1
        if match.participants.indices.contains(index) {
            return match.participants[index].player?.displayName ?? "Player \(index + 1)"
        }
        return player.displayName
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
        if !isOnlineMatch {
            return "\(offlinePlayers.points(for: player) ?? 0)"
        }
        guard let match = gameCenter.currentMatch else {
            return "\(gameCenter.localEloRating)"
        }
        let index = player == .black ? 0 : 1
        if match.participants.indices.contains(index) {
            let participant = match.participants[index].player
            return "\(gameCenter.eloRating(for: participant))"
        }
        return "\(gameCenter.localEloRating)"
    }

    private func playerProfile(for player: Player) -> GKPlayer? {
        guard let match = gameCenter.currentMatch else { return nil }
        let index = player == .black ? 0 : 1
        guard match.participants.indices.contains(index) else { return nil }
        return match.participants[index].player
    }

    private func handleBoardTap(row: Int, col: Int) {
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

    private func resetTimer() {
        timeRemaining = moveTimeLimit
    }

    private func tickTimer() {
        guard !isGameOver else { return }
        guard isLocalTurn else { return }
        guard timeRemaining > 0 else { return }

        timeRemaining -= 1
        if timeRemaining <= 0 {
            timeRemaining = 0
            handleTimeout()
        }
    }

    private func handleTimeout() {
        guard !isGameOver else { return }
        game.timeoutCurrentPlayer()

        if let match = gameCenter.currentMatch, isLocalTurn {
            gameCenter.submitTurn(game: game, match: match)
        }
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
        if isOnlineMatch {
            gameCenter.currentMatch = nil
        } else if isDebugMatch {
            gameCenter.isDebugMatchActive = false
        }
        dismiss()
    }

    private func startRematch() {
        if isOnlineMatch, let match = gameCenter.currentMatch {
            gameCenter.requestRematch(for: match)
        } else {
            game.reset()
            resetTimer()
            hasRecordedOfflineResult = false
        }
    }

    private func shouldShowResignButton(for player: Player) -> Bool {
        guard !isGameOver else { return false }
        if isOnlineMatch {
            return isLocalPlayer(player)
        }
        return player == game.currentPlayer
    }

    private func isLocalPlayer(_ player: Player) -> Bool {
        guard let match = gameCenter.currentMatch else { return player == .black }
        return gameCenter.localPlayerColor(in: match) == player
    }

    private func currentResigningPlayer() -> Player {
        guard let match = gameCenter.currentMatch else { return game.currentPlayer }
        return gameCenter.localPlayerColor(in: match) ?? game.currentPlayer
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
}

#Preview {
    GameScreenView()
        .environmentObject(GameCenterManager())
        .environmentObject(OfflinePlayersStore())
}
