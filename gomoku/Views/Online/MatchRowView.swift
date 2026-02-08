internal import GameKit
import SwiftUI

/// Summary row for a turn-based match.
struct MatchRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let match: GKTurnBasedMatch
    private let surfacePrimaryText = Color(red: 0.12, green: 0.13, blue: 0.16)
    private let surfaceSecondaryText = Color(red: 0.32, green: 0.34, blue: 0.38)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(matchTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
#if DEBUG
                Text("ID: \(match.matchID)")
                    .font(.caption2)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
#endif
            }

            Spacer()

            if isMyTurn {
                Text("Your turn")
                    .font(.caption)
                    .foregroundStyle(primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(turnBadgeBackground, in: Capsule())
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(rowBorder, lineWidth: 1)
        )
    }

    private var matchTitle: String {
        let names = match.participants.compactMap { $0.player?.displayName }
        if let opponent = names.first(where: { $0 != GKLocalPlayer.local.displayName }) {
            return "vs \(opponent)"
        }
        return "Turn-based Match"
    }

    private var statusText: String {
        switch match.status {
        case .ended:
            return "Finished"
        case .matching:
            return "Finding players"
        default:
            if let name = match.currentParticipant?.player?.displayName {
                return "Waiting for \(name)"
            }
            return "In progress"
        }
    }

    private var isMyTurn: Bool {
        match.currentParticipant?.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
    }

    private var statusColor: Color {
        if isMyTurn {
            return Color.green.opacity(0.7)
        }
        switch match.status {
        case .ended:
            return Color.gray.opacity(0.6)
        case .matching:
            return Color.orange.opacity(0.8)
        default:
            return Color.blue.opacity(0.7)
        }
    }

    private var primaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.93, blue: 0.98)
            : surfacePrimaryText
    }

    private var secondaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.72, green: 0.79, blue: 0.90)
            : surfaceSecondaryText
    }

    private var rowBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.23, blue: 0.30)
            : Color(red: 0.96, green: 0.98, blue: 1.0)
    }

    private var rowBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var turnBadgeBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }
}
