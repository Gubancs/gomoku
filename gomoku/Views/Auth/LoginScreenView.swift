import SwiftUI

/// First-run login screen for Game Center authentication.
struct LoginScreenView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager

    var body: some View {
        ZStack {
            background

            VStack(spacing: 16) {
                Text("Welcome")
                    .font(.system(size: 34, weight: .semibold, design: .serif))

                Text("Sign in to Game Center to start playing online.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Button {
                    gameCenter.beginAuthentication()
                } label: {
                    Label("Sign In", systemImage: "person.crop.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.26, green: 0.50, blue: 0.88))

#if DEBUG
                Button {
                    gameCenter.isDebugMatchActive = true
                } label: {
                    Label("Debug Local Board", systemImage: "hammer")
                }
                .buttonStyle(.bordered)
#endif

                if let error = gameCenter.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 24)
        }
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
}

#Preview {
    LoginScreenView()
        .environmentObject(GameCenterManager())
}
