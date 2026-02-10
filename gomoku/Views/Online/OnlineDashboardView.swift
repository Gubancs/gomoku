internal import GameKit
import SwiftUI

/// Displays Game Center status, leaderboard info, and active matches.
struct OnlineDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var gameCenter: GameCenterManager
    let onStartMatch: () -> Void
    let onStartPartyHost: () -> Void
    let onStartPartyJoin: () -> Void
    let onStartOfflineMatch: () -> Void
    let onSelectMatch: (GKTurnBasedMatch) -> Void
    private let surfacePrimaryText = Color(red: 0.12, green: 0.13, blue: 0.16)
    private let surfaceSecondaryText = Color(red: 0.32, green: 0.34, blue: 0.38)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            profileCard
#if DEBUG
            if let errorText = gameCenter.lastError, !errorText.isEmpty {
                errorBanner(text: errorText)
            }
#endif
            actionSections
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionSections: some View {
        let singleColumn = [GridItem(.flexible(), spacing: 12)]

        return VStack(spacing: 16) {
            LazyVGrid(columns: singleColumn, spacing: 12) {
                onlineAction
                partyHostAction
                partyJoinAction
                offlineAction
            }
        }
    }

    private var onlineAction: some View {
        Button {
            if let match = primaryActiveMatch {
                onSelectMatch(match)
            } else {
                onStartMatch()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                Text(primaryActiveMatch == nil ? "Online" : "Resume Match")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(Color(red: 0.26, green: 0.50, blue: 0.88))
        .disabled(!gameCenter.isAuthenticated || gameCenter.isFindingMatch || primaryActiveMatch != nil)
    }

    private var partyHostAction: some View {
        Button {
            onStartPartyHost()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.3.sequence")
                Text("Party Host")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(Color(red: 0.26, green: 0.50, blue: 0.88))
        .disabled(!gameCenter.isAuthenticated || gameCenter.isFindingMatch || primaryActiveMatch != nil)
    }

    private var partyJoinAction: some View {
        Button {
            onStartPartyJoin()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.plus")
                Text("Join Code")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(Color(red: 0.26, green: 0.50, blue: 0.88))
        .disabled(!gameCenter.isAuthenticated || gameCenter.isFindingMatch || primaryActiveMatch != nil)
    }

    private var offlineAction: some View {
        Button {
            onStartOfflineMatch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                Text("Offline 2 players")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(Color(red: 0.26, green: 0.50, blue: 0.88))
        .disabled(primaryActiveMatch != nil)
    }

    private var sortedActiveMatches: [GKTurnBasedMatch] {
        gameCenter.sortedMatchesForDisplay(gameCenter.activeMatches)
    }

    private var primaryActiveMatch: GKTurnBasedMatch? {
        sortedActiveMatches.first
    }

    private func errorBanner(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(colorScheme == .dark ? Color(red: 1.0, green: 0.78, blue: 0.78) : Color(red: 0.55, green: 0.10, blue: 0.12))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colorScheme == .dark ? Color.red.opacity(0.18) : Color.red.opacity(0.11))
            )
    }

    private var profileCard: some View {
        let name = GKLocalPlayer.local.displayName
        let eloValue = gameCenter.playerScore ?? gameCenter.localEloRating
        let rankValue = gameCenter.playerRank.map { "#\($0)" } ?? "-"
        let matchesValue = "\(gameCenter.finishedMatches.count)"
        let record = localRecordSummary
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

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                profileAvatar
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(cardPrimaryText)
                        .lineLimit(1)
                    Text("Game Center")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(cardSecondaryText)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(eloValue)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(cardPrimaryText)
                    Text("ELO")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(cardSecondaryText)
                }
            }

            HStack(spacing: 8) {
                statPill(title: "Rank", value: rankValue, systemImage: "crown.fill")
                statPill(title: "Matches", value: matchesValue, systemImage: "flag.checkered")
                statPill(title: "Wins", value: "\(record.wins)", systemImage: "trophy.fill")
                statPill(title: "Losses", value: "\(record.losses)", systemImage: "xmark.seal.fill")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 6)
    }

    private var localRecordSummary: (wins: Int, losses: Int) {
        var wins = 0
        var losses = 0

        for match in gameCenter.finishedMatches {
            guard let participant = match.participants.first(where: { gameCenter.isLocalParticipant($0) }) else {
                continue
            }
            switch participant.matchOutcome {
            case .won:
                wins += 1
            case .lost, .quit, .timeExpired:
                losses += 1
            case .none:
                if let state = gameCenter.loadState(from: match),
                   let winner = state.winner,
                   let localColor = gameCenter.localPlayerColor(in: match) {
                    if winner == localColor {
                        wins += 1
                    } else {
                        losses += 1
                    }
                }
            default:
                break
            }
        }

        return (wins, losses)
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

    private var profileAvatar: some View {
        let avatarSize: CGFloat = 56
        let image = gameCenter.avatarImage(for: GKLocalPlayer.local)

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

    private func statPill(title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(cardSecondaryText)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(cardPrimaryText)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(cardSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
        )
    }

}

struct SwipeToDeleteMatchRow<Content: View>: View {
    private let actionWidth: CGFloat = 82
    let onTap: (() -> Void)?
    let onDelete: () -> Void
    let content: Content
    @State private var contentOffset: CGFloat = 0
    @State private var rowHeight: CGFloat = 56

    init(
        onTap: (() -> Void)? = nil,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onTap = onTap
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) {
                    contentOffset = 0
                }
                onDelete()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.88))
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: actionWidth, height: rowHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete match")

            content
                .offset(x: contentOffset)
                .contentShape(Rectangle())
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                rowHeight = max(44, proxy.size.height)
                            }
                            .onChange(of: proxy.size.height) { newValue in
                                rowHeight = max(44, newValue)
                            }
                    }
                )
                .gesture(dragGesture)
                .onTapGesture {
                    if isOpen {
                        withAnimation(.easeOut(duration: 0.2)) {
                            contentOffset = 0
                        }
                    } else {
                        onTap?()
                    }
                }

            // Transparent tap target above content for the revealed action area.
            // This avoids the shifted content intercepting taps meant for delete.
            Color.clear
                .frame(width: actionWidth, height: rowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isOpen else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        contentOffset = 0
                    }
                    onDelete()
                }
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var isOpen: Bool {
        contentOffset < -8
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let base = isOpen ? -actionWidth : 0
                let proposed = base + value.translation.width
                contentOffset = min(0, max(-actionWidth, proposed))
            }
            .onEnded { value in
                let base = isOpen ? -actionWidth : 0
                let predicted = base + value.predictedEndTranslation.width
                let shouldOpen = predicted < (-actionWidth * 0.45)
                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                    contentOffset = shouldOpen ? -actionWidth : 0
                }
            }
    }
}

#if DEBUG
private extension OnlineDashboardView {
    static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matchmaking Debug")
                .font(.caption.weight(.semibold))
                .foregroundStyle(cardPrimaryText)

            debugRow("GC env", gameCenter.gameCenterEnvironmentName)
            debugRow("Bundle ID", gameCenter.bundleIdentifier)
            debugRow("App version", gameCenter.appVersion)
            debugRow("Build", gameCenter.buildNumber)
            debugRow("Device", gameCenter.deviceDebugName)
            debugRow("App ID prefix", gameCenter.appIdentifierPrefix)
            debugRow("Team ID", gameCenter.teamIdentifier ?? "-")
            debugRow("App identifier", gameCenter.applicationIdentifier ?? "-")
            debugRow("Multiplayer restricted", gameCenter.isMultiplayerRestricted ? "yes" : "no")
            debugRow("Underage", gameCenter.isUnderage ? "yes" : "no")
            debugRow("Authenticated", gameCenter.isAuthenticated ? "yes" : "no")
            debugRow("Finding match", gameCenter.isFindingMatch ? "yes" : "no")
            debugRow("Awaiting rematch", gameCenter.isAwaitingRematch ? "yes" : "no")
            debugRow("Current match", shortMatchID(gameCenter.currentMatch?.matchID))
            debugRow("Pending match ID", shortMatchID(gameCenter.pendingAutoMatchID))
            debugRow("Pending match status", pendingMatchStatusText)
            debugRow("Matchmaking started", formattedDate(gameCenter.matchmakingStartedAt))
            debugRow("Pending missing since", formattedDate(gameCenter.pendingAutoMatchMissingSince))
            if let code = gameCenter.partyCode {
                debugRow("Party code", code)
            }
            if let group = gameCenter.currentPlayerGroup {
                debugRow("Party group", "\(group)")
            }
            debugRow("Active matches", "\(gameCenter.activeMatches.count)")

            if !gameCenter.activeMatches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(gameCenter.activeMatches, id: \.matchID) { match in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("- \(shortMatchID(match.matchID))")
                                .font(.caption2.weight(.semibold))
                            Text("status: \(statusLabel(match.status)) | players: \(playerCount(match))")
                                .font(.caption2)
                                .foregroundStyle(cardSecondaryText)

                            ForEach(Array(match.participants.enumerated()), id: \.offset) { index, participant in
                                Text("  \(participantLine(participant, index: index))")
                                    .font(.caption2)
                                    .foregroundStyle(cardSecondaryText)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    func debugRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(title):")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(cardPrimaryText)
            Text(value)
                .font(.caption2)
                .foregroundStyle(cardSecondaryText)
        }
    }

    var pendingMatchStatusText: String {
        if let match = gameCenter.pendingAutoMatch {
            return "\(statusLabel(match.status)) | players: \(playerCount(match))"
        }
        return "-"
    }

    func formattedDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        return Self.debugDateFormatter.string(from: date)
    }

    func shortMatchID(_ matchID: String?) -> String {
        guard let matchID, !matchID.isEmpty else { return "-" }
        if matchID.count <= 8 { return matchID }
        let start = matchID.prefix(4)
        let end = matchID.suffix(4)
        return "\(start)...\(end)"
    }

    func statusLabel(_ status: GKTurnBasedMatch.Status) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .open:
            return "open"
        case .matching:
            return "matching"
        case .ended:
            return "ended"
        @unknown default:
            return "unknown"
        }
    }

    func playerCount(_ match: GKTurnBasedMatch) -> Int {
        match.participants.filter { $0.player != nil }.count
    }

    func participantLine(_ participant: GKTurnBasedParticipant, index: Int) -> String {
        let name = participant.player?.displayName ?? "empty"
        let status = participantStatusLabel(participant.status)
        let outcome = participantOutcomeLabel(participant.matchOutcome)
        return "#\(index + 1) \(name) | status: \(status) | outcome: \(outcome)"
    }

    func participantStatusLabel(_ status: GKTurnBasedParticipant.Status) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .invited:
            return "invited"
        case .declined:
            return "declined"
        case .matching:
            return "matching"
        case .active:
            return "active"
        case .done:
            return "done"
        @unknown default:
            return "unknown"
        }
    }

    func participantOutcomeLabel(_ outcome: GKTurnBasedMatch.Outcome) -> String {
        switch outcome {
        case .none:
            return "none"
        case .won:
            return "won"
        case .lost:
            return "lost"
        case .quit:
            return "quit"
        case .tied:
            return "tied"
        case .timeExpired:
            return "timeExpired"
        case .first:
            return "first"
        case .second:
            return "second"
        case .third:
            return "third"
        case .fourth:
            return "fourth"
        @unknown default:
            return "unknown"
        }
    }
}
#endif
