import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager

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
        .onAppear {
            gameCenter.refreshAuthenticationState()
        }
        .fullScreenCover(isPresented: matchPresentationBinding) {
            NavigationStack {
                GameScreenView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(gameCenter)
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
