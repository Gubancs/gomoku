import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var offlinePlayers = OfflinePlayersStore()

    var body: some View {
        ZStack {
            background

            if gameCenter.isAuthenticated {
                NavigationStack {
                    OnlineScreenView()
                }
            } else {
                LoginScreenView()
            }
        }
        .environmentObject(offlinePlayers)
        .onAppear {
            gameCenter.refreshAuthenticationState()
        }
        .fullScreenCover(isPresented: matchPresentationBinding) {
            NavigationStack {
                GameScreenView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(gameCenter)
            .environmentObject(offlinePlayers)
        }
    }

    private var matchPresentationBinding: Binding<Bool> {
        Binding(
            get: {
                gameCenter.isDebugMatchActive
                    || gameCenter.currentMatch != nil
                    || gameCenter.isFindingMatch
            },
            set: { isPresented in
                if !isPresented {
                    if gameCenter.isFindingMatch {
                        gameCenter.cancelMatchmaking()
                    }
                    gameCenter.currentMatch = nil
                    gameCenter.isDebugMatchActive = false
                }
            }
        )
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
}

#Preview {
    ContentView()
        .environmentObject(GameCenterManager())
}
