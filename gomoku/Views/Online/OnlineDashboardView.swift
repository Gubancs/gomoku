internal import GameKit
import SwiftUI

/// Displays Game Center status, leaderboard info, and active matches.
struct OnlineDashboardView: View {
    @ObservedObject var gameCenter: GameCenterManager
    let onStartMatch: () -> Void
    let onSelectMatch: (GKTurnBasedMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            profileCard
            actionGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            onlineAction
            offlineAction
            singlePlayerAction
        }
    }

    private var onlineAction: some View {
        Button {
            onStartMatch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                Text("Online")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(Color(red: 0.26, green: 0.50, blue: 0.88))
        .disabled(!gameCenter.isAuthenticated || gameCenter.isFindingMatch)
    }

    private var offlineAction: some View {
        Button {
            gameCenter.isDebugMatchActive = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                Text("2 players")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(Color(red: 0.26, green: 0.50, blue: 0.88))
    }

    private var singlePlayerAction: some View {
        Button {
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                Text("1 player")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .tint(Color(red: 0.26, green: 0.50, blue: 0.88))
        .disabled(true)
    }

    private var profileCard: some View {
        let name = GKLocalPlayer.local.displayName
        let eloValue = gameCenter.playerScore ?? gameCenter.localEloRating
        let rankValue = gameCenter.playerRank.map { "#\($0)" } ?? "-"
        let matchesValue = "\(gameCenter.activeMatches.count)"
        let cardGradient = LinearGradient(
            colors: [
                Color(red: 0.92, green: 0.97, blue: 1.0),
                Color(red: 0.74, green: 0.86, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return HStack(spacing: 12) {
            profileAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Text("ELO: \(eloValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Rank: \(rankValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Matches: \(matchesValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(cardGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
    }

    private var profileAvatar: some View {
        let avatarSize: CGFloat = 48
        let image = gameCenter.avatarImage(for: GKLocalPlayer.local)

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 2)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.black.opacity(0.35))
                    .padding(6)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }

}
