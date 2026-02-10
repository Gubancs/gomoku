import SwiftUI

/// First-run login screen for Game Center authentication.
struct LoginScreenView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @Environment(\.colorScheme) private var colorScheme
    private let surfacePrimaryText = Color(red: 0.12, green: 0.13, blue: 0.16)
    private let surfaceSecondaryText = Color(red: 0.32, green: 0.34, blue: 0.38)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 16) {
                Text("Welcome")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(headlineTextColor)

                Text("Sign in to Game Center to start playing online.")
                    .font(.subheadline)
                    .foregroundStyle(supportingTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Button {
                    gameCenter.beginAuthentication()
                } label: {
                    Label("Sign In", systemImage: "person.crop.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.26, green: 0.50, blue: 0.88))

                if let error = gameCenter.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(supportingTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, 24)
        }
        .toolbar(.hidden, for: .tabBar)
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

    private var headlineTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.93, blue: 0.98)
            : surfacePrimaryText
    }

    private var supportingTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.74, green: 0.79, blue: 0.88)
            : surfaceSecondaryText
    }
}

#Preview {
    LoginScreenView()
        .environmentObject(GameCenterManager())
}
