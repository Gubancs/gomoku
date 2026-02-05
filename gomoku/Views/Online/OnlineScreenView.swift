import SwiftUI

/// Dedicated screen for Game Center dashboard and matchmaking.
struct OnlineScreenView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header

                    OnlineDashboardView(
                        gameCenter: gameCenter,
                        onStartMatch: gameCenter.startMatchmaking,
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
            }
            .overlay {
                if gameCenter.isFindingMatch {
                    matchmakingOverlay
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
    }

    private var header: some View {
        EmptyView()
    }

    private var background: some View {
        RadialGradient(
            colors: [
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

                Button("Cancel Search") {
                    gameCenter.cancelMatchmaking()
                }
                .buttonStyle(.bordered)
                .tint(.black.opacity(0.75))
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
}

#Preview {
    OnlineScreenView()
        .environmentObject(GameCenterManager())
}
