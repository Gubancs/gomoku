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
    @State private var isFinishedMatchesPresented: Bool = false
    @State private var joinPartyCode: String = ""
    @State private var presenceCount: Int?
    @FocusState private var isJoinCodeFieldFocused: Bool

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header

                    OnlineDashboardView(
                        gameCenter: gameCenter,
                        onStartMatch: gameCenter.presentMatchmaking,
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
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable {
                gameCenter.loadMatches()
                gameCenter.refreshLeaderboard()
                await refreshPresence()
            }

            if let match = primaryActiveMatch {
                VStack {
                    Spacer()
                    activeMatchOverlay(match: match)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(centerTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    isFinishedMatchesPresented = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
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
        .navigationDestination(isPresented: $isFinishedMatchesPresented) {
            FinishedMatchesListView { match in
                gameCenter.handleMatchSelected(match)
            }
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

    private var sortedActiveMatches: [GKTurnBasedMatch] {
        gameCenter.sortedMatchesForDisplay(gameCenter.activeMatches)
    }

    private var primaryActiveMatch: GKTurnBasedMatch? {
        sortedActiveMatches.first
    }

    private func activeMatchOverlay(match: GKTurnBasedMatch) -> some View {
        Button {
            gameCenter.handleMatchSelected(match)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Active Match")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Tap to open")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                MatchRowView(match: match)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.70))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 1)
                    )
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                    .buttonStyle(.plain)

                    Button("Join") {
                        isJoinPartyPresented = false
                        gameCenter.startPartyJoinMatchmaking(code: joinPartyCode)
                        joinPartyCode = ""
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.26, green: 0.50, blue: 0.88),
                                Color(red: 0.20, green: 0.40, blue: 0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 6)
                    .disabled(joinPartyCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 4)
                    .opacity(joinPartyCode.trimmingCharacters(in: .whitespacesAndNewlines).count == 4 ? 1 : 0.6)
                    .buttonStyle(.plain)
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
