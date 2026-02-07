import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @StateObject private var offlinePlayers = OfflinePlayersStore()

    var body: some View {
        ZStack {
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
            get: { gameCenter.isCurrentMatchReady || gameCenter.isDebugMatchActive },
            set: { isPresented in
                if !isPresented {
                    gameCenter.currentMatch = nil
                    gameCenter.isDebugMatchActive = false
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(GameCenterManager())
}
