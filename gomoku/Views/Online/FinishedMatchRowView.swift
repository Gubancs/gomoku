internal import GameKit
import SwiftUI

struct FinishedMatchRowView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @Environment(\.colorScheme) private var colorScheme
    let match: GKTurnBasedMatch
    private let surfacePrimaryText = Color(red: 0.12, green: 0.13, blue: 0.16)
    private let surfaceSecondaryText = Color(red: 0.32, green: 0.34, blue: 0.38)

    var body: some View {
        let scores = resolvedScores

        HStack(alignment: .center, spacing: 12) {
            playerBlock(
                participant: participant(at: 0),
                fallbackName: "Player 1"
            )

            Spacer(minLength: 6)

            VStack(spacing: 6) {
                Text("\(scores.left) - \(scores.right)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)

                Text(summaryLine)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 6)

            playerBlock(
                participant: participant(at: 1),
                fallbackName: "Player 2"
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(rowBorder, lineWidth: 1)
        )
    }

    private func playerBlock(
        participant: GKTurnBasedParticipant?,
        fallbackName: String
    ) -> some View {
        let avatarSize: CGFloat = 44
        let name = participant?.player?.displayName ?? fallbackName
        let image = gameCenter.avatarImage(for: participant?.player)

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 2)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(initials(for: name))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )

            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .frame(width: 88)
        }
    }

    private func initials(for name: String) -> String {
        let upper = name.uppercased()
        for scalar in upper.unicodeScalars {
            if scalar.value >= 65 && scalar.value <= 90 {
                return String(Character(scalar))
            }
        }
        return "?"
    }

    private func participant(at index: Int) -> GKTurnBasedParticipant? {
        guard match.participants.indices.contains(index) else { return nil }
        return match.participants[index]
    }

    private var resolvedScores: (left: String, right: String) {
        let participants = match.participants
        if participants.contains(where: { $0.matchOutcome == .tied }) {
            return ("0", "0")
        }
        if let winnerIndex = participants.firstIndex(where: { $0.matchOutcome == .won }) {
            return winnerIndex == 0 ? ("1", "0") : ("0", "1")
        }
        if let loserIndex = participants.firstIndex(where: {
            $0.matchOutcome == .lost || $0.matchOutcome == .quit || $0.matchOutcome == .timeExpired
        }) {
            return loserIndex == 0 ? ("0", "1") : ("1", "0")
        }

        if let state = decodedState, let winner = state.winner {
            return winner == .black ? ("1", "0") : ("0", "1")
        }
        if let state = decodedState, state.isDraw {
            return ("0", "0")
        }
        return ("0", "0")
    }

    private var summaryLine: String {
        let dateText = formattedDate(endDate ?? match.creationDate)
        let movesText = movesCountText
        if movesText == "-" {
            return "Ended \(dateText)"
        }
        return "Ended \(dateText) • Moves \(movesText)"
    }

    private var movesCountText: String {
        guard let state = decodedState else { return "-" }
        let boardCount = state.board.flatMap { $0 }.filter { $0 != nil }.count
        let count = max(state.moves.count, boardCount)
        return count > 0 ? "\(count)" : "-"
    }

    private var decodedState: GameState? {
        guard let data = match.matchData else { return nil }
        return GameState.decoded(from: data)
    }

    private var endDate: Date? {
        if let lastTurnDate = match.value(forKey: "lastTurnDate") as? Date {
            return lastTurnDate
        }
        return match.creationDate
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

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
