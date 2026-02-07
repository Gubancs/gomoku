internal import GameKit
import SwiftUI

/// Summary row for a turn-based match.
struct MatchRowView: View {
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
                    .foregroundStyle(surfacePrimaryText)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(surfaceSecondaryText)
#if DEBUG
                Text("ID: \(match.matchID)")
                    .font(.caption2)
                    .foregroundStyle(surfaceSecondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
#endif
            }

            Spacer()

            if isMyTurn {
                Text("Your turn")
                    .font(.caption)
                    .foregroundStyle(surfacePrimaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.08), in: Capsule())
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
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
}
