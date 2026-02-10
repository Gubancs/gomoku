import SwiftUI
@preconcurrency internal import GameKit

struct ContentView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var offlinePlayers = OfflinePlayersStore()
    @State private var selectedTab: Tab = .home

    private enum Tab: Hashable {
        case home
        case match
        case leaderboards
        case settings
    }

    var body: some View {
        ZStack {
            background

            TabView(selection: $selectedTab) {
                NavigationStack {
                    if gameCenter.isAuthenticated {
                        OnlineScreenView()
                    } else {
                        LoginScreenView()
                    }
                }
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(Tab.home)

                if shouldPresentMatch {
                    NavigationStack {
                        GameScreenView()
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem {
                        Label("Match", systemImage: "gamecontroller")
                    }
                    .tag(Tab.match)
                }

                NavigationStack {
                    if gameCenter.isAuthenticated {
                        LeaderboardsView(gameCenter: gameCenter)
                    } else {
                        LoginScreenView()
                    }
                }
                .tabItem {
                    Label("Leaderboards", systemImage: "list.number")
                }
                .tag(Tab.leaderboards)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
            }
            .id(shouldPresentMatch)
            .tint(tabTintColor)
            .toolbar(gameCenter.isAuthenticated ? .visible : .hidden, for: .tabBar)
        }
        .statusBar(hidden: true)
        .persistentSystemOverlays(.hidden)
        .environmentObject(offlinePlayers)
        .onAppear {
            gameCenter.refreshAuthenticationState()
        }
        .onChange(of: shouldPresentMatch) { shouldPresent in
            if shouldPresent {
                DispatchQueue.main.async {
                    selectedTab = .match
                }
            } else if selectedTab == .match {
                selectedTab = .home
            }
        }
    }

    private var shouldPresentMatch: Bool {
        gameCenter.isDebugMatchActive
            || gameCenter.currentMatch != nil
            || gameCenter.isFindingMatch
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

    private var tabTintColor: Color {
        if selectedTab == .match {
            return Color(red: 0.20, green: 0.72, blue: 0.40)
        }
        return Color(red: 0.26, green: 0.50, blue: 0.88)
    }
}

#Preview {
    ContentView()
        .environmentObject(GameCenterManager())
}
