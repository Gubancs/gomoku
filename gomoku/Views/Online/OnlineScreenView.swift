internal import GameKit
import SwiftUI

/// Dedicated screen for Game Center dashboard and matchmaking.
struct OnlineScreenView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @EnvironmentObject private var offlinePlayers: OfflinePlayersStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isOfflineSetupPresented: Bool = false
    @State private var isJoinPartyPresented: Bool = false
    @State private var joinPartyCode: String = ""
    @State private var presenceCount: Int?

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header

                    OnlineDashboardView(
                        gameCenter: gameCenter,
                        onStartMatch: gameCenter.startMatchmaking,
                        onStartPartyHost: {
                            gameCenter.startPartyHostMatchmaking()
                        },
                        onStartPartyJoin: {
                            isJoinPartyPresented = true
                        },
                        onStartMatchmakerUI: {
                            gameCenter.presentMatchmakerUI()
                        },
                        onStartOfflineMatch: {
                            isOfflineSetupPresented = true
                        },
                        onSelectMatch: { match in
                            gameCenter.handleMatchSelected(match)
                        }
                    )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 24)
            }
            .refreshable {
                gameCenter.loadMatches()
                gameCenter.refreshLeaderboard()
                await refreshPresence()
            }
            .overlay {
                if gameCenter.isFindingMatch {
                    matchmakingOverlay
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(centerTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
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
        .sheet(isPresented: $isOfflineSetupPresented) {
            NavigationStack {
                OfflineMatchSetupView()
                    .environmentObject(gameCenter)
                    .environmentObject(offlinePlayers)
            }
        }
        .sheet(isPresented: $isJoinPartyPresented) {
            NavigationStack {
                VStack(spacing: 14) {
                    Text("Join by Code")
                        .font(.headline)
                    TextField("Enter code", text: $joinPartyCode)
                        .textCase(.uppercase)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if let partyError = gameCenter.partyError, !partyError.isEmpty {
                        Text(partyError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button("Join") {
                        isJoinPartyPresented = false
                        gameCenter.startPartyJoinMatchmaking(code: joinPartyCode)
                        joinPartyCode = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(joinPartyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel", role: .cancel) {
                        isJoinPartyPresented = false
                        joinPartyCode = ""
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .presentationDetents([.height(260)])
        }
        .task {
            await refreshPresence()
        }
    }

    private var centerTitle: String {
        if let presenceCount {
            return "Online: \(presenceCount)"
        }
        return "Online"
    }

    @Sendable private func refreshPresence() async {
        let count = await gameCenter.fetchOnlineCount()
        await MainActor.run {
            presenceCount = count
        }
    }

    private var header: some View {
        EmptyView()
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

    private var matchmakingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)

                Text("Finding opponent...")
                    .font(.headline)

                Text("We will start the match as soon as someone joins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

#if DEBUG
                if !matchmakingDebugLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GC env: \(gameCenter.gameCenterEnvironmentName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Team ID: \(gameCenter.teamIdentifier ?? "-")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("App ID: \(gameCenter.appIdentifierPrefix)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let code = gameCenter.partyCode {
                            Text("Party code: \(code)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(matchmakingDebugLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 6)
                }
#endif

                Button("Cancel Search") {
                    gameCenter.cancelMatchmaking()
                }
                .buttonStyle(.bordered)
                .tint(colorScheme == .dark
                    ? Color(red: 0.78, green: 0.84, blue: 0.95)
                    : .black.opacity(0.75)
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 320)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        }
    }

#if DEBUG
    private var matchmakingDebugLines: [String] {
        var lines: [String] = []
        lines.append("pending: \(shortMatchID(gameCenter.pendingAutoMatchID))")
        if let pendingMatch = gameCenter.pendingAutoMatch {
            let status = pendingMatch.status
            let playerCount = pendingMatch.participants.filter { $0.player != nil }.count
            lines.append("pending status: \(statusLabel(status)) | players: \(playerCount)")
        }
        if let code = gameCenter.partyCode {
            lines.append("party code: \(code)")
        }
        if let group = gameCenter.currentPlayerGroup {
            lines.append("party group: \(group)")
        }
        if let started = gameCenter.matchmakingStartedAt {
            lines.append("started: \(formattedTime(started))")
        }
        if let missing = gameCenter.pendingAutoMatchMissingSince {
            lines.append("missing since: \(formattedTime(missing))")
        }
        return lines
    }

    private func shortMatchID(_ matchID: String?) -> String {
        guard let matchID, !matchID.isEmpty else { return "-" }
        if matchID.count <= 8 { return matchID }
        let start = matchID.prefix(4)
        let end = matchID.suffix(4)
        return "\(start)...\(end)"
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func statusLabel(_ status: GKTurnBasedMatch.Status) -> String {
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
#endif
}

#Preview {
    OnlineScreenView()
        .environmentObject(GameCenterManager())
        .environmentObject(OfflinePlayersStore())
}
