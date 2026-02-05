internal import GameKit
import SwiftUI

/// Summary row for a turn-based match.
struct MatchRowView: View {
    let match: GKTurnBasedMatch

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(matchTitle)
                    .font(.subheadline.weight(.semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isMyTurn {
                Text("Your turn")
                    .font(.caption)
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
            if let name = match.currentParticipant?.player?.displayName as? String {
                return "Waiting for \(name)"
            }
            if let names = match.currentParticipant?.player?.displayName as? [String], let first = names.first {
                return "Waiting for \(first)"
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
