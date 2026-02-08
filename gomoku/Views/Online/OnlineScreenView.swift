internal import GameKit
import SwiftUI
import UIKit

/// Dedicated screen for Game Center dashboard and matchmaking.
struct OnlineScreenView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @EnvironmentObject private var offlinePlayers: OfflinePlayersStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isOfflineSetupPresented: Bool = false
    @State private var isJoinPartyPresented: Bool = false
    @State private var isLeaderboardsPresented: Bool = false
    @State private var joinPartyCode: String = ""
    @State private var presenceCount: Int?
    @FocusState private var isJoinCodeFieldFocused: Bool

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    partyCodeBanner

                    OnlineDashboardView(
                        gameCenter: gameCenter,
                        onStartMatch: gameCenter.startMatchmaking,
                        onOpenLeaderboards: {
                            isLeaderboardsPresented = true
                        },
                        onStartPartyHost: {
                            gameCenter.startPartyHostMatchmaking()
                        },
                        onStartPartyJoin: {
                            isJoinPartyPresented = true
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
                joinByCodeSheet
            }
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.visible)
            .onAppear {
                isJoinCodeFieldFocused = true
            }
        }
        .navigationDestination(isPresented: $isLeaderboardsPresented) {
            LeaderboardsView(gameCenter: gameCenter)
        }
        .task {
            await refreshPresence()
            startPresenceAutoRefresh()
        }
    }

    private var centerTitle: String {
        if let presenceCount {
            return "Online: \(presenceCount)"
        }
        return "Online"
    }

    private func startPresenceAutoRefresh() {
        // Poll every 20 seconds while view is alive.
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { await refreshPresence() }
        }
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

    private var joinByCodeSheet: some View {
        ZStack {
            RadialGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.10, green: 0.16, blue: 0.30),
                        Color(red: 0.16, green: 0.20, blue: 0.30)
                    ]
                    : [
                        Color(red: 0.93, green: 0.97, blue: 1.0),
                        Color(red: 0.84, green: 0.92, blue: 1.0)
                    ],
                center: .top,
                startRadius: 80,
                endRadius: 560
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.26, green: 0.50, blue: 0.88),
                                    Color(red: 0.20, green: 0.40, blue: 0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 6)

                Text("Join by Party Code")
                    .font(.title3.weight(.bold))

                Text("Ask your friend for their 4-character code and paste it below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                VStack(spacing: 10) {
                    TextField("AB12", text: $joinPartyCode)
                        .focused($isJoinCodeFieldFocused)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .multilineTextAlignment(.center)
                        .onChange(of: joinPartyCode) { newValue in
                            joinPartyCode = normalizedJoinCode(newValue)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )

                    if let partyError = gameCenter.partyError, !partyError.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(partyError)
                                .multilineTextAlignment(.leading)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(colorScheme == .dark ? 0.15 : 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                HStack(spacing: 10) {
                    Button("Cancel", role: .cancel) {
                        isJoinPartyPresented = false
                        joinPartyCode = ""
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Join") {
                        isJoinPartyPresented = false
                        gameCenter.startPartyJoinMatchmaking(code: joinPartyCode)
                        joinPartyCode = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.26, green: 0.50, blue: 0.88))
                    .disabled(joinPartyCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 4)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private var partyCodeBanner: some View {
        if let code = gameCenter.partyCode, !code.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Party Code")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Text(code)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    Button {
                        UIPasteboard.general.string = code
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
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

                if let code = gameCenter.partyCode, !code.isEmpty {
                    VStack(spacing: 6) {
                        Text("Share this party code:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .tracking(3)
                    }
                    .padding(.top, 2)
                }

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
                        Text("Restricted: \(gameCenter.isMultiplayerRestricted ? "yes" : "no") / Underage: \(gameCenter.isUnderage ? "yes" : "no")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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

    private func normalizedJoinCode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let upper = value.uppercased()
        let filteredScalars = upper.unicodeScalars.filter { allowed.contains($0) }
        let filtered = String(String.UnicodeScalarView(filteredScalars))
        return String(filtered.prefix(4))
    }
}

#Preview {
    OnlineScreenView()
        .environmentObject(GameCenterManager())
        .environmentObject(OfflinePlayersStore())
}
