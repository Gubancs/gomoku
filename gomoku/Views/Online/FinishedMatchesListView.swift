internal import GameKit
import SwiftUI

struct FinishedMatchesListView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @Environment(\.colorScheme) private var colorScheme
    let onSelectMatch: (GKTurnBasedMatch) -> Void
    @State private var pageSize: Int = 20

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if sortedFinishedMatches.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleMatches, id: \.matchID) { match in
                        Button {
                            onSelectMatch(match)
                        } label: {
                            FinishedMatchRowView(match: match)
                        }
                        .buttonStyle(.plain)
                    }

                    if visibleMatches.count < sortedFinishedMatches.count {
                        Button("Load Older") {
                            pageSize = min(pageSize + 20, sortedFinishedMatches.count)
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(buttonBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                        .foregroundStyle(primaryText)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .navigationTitle("Matches")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sortedFinishedMatches: [GKTurnBasedMatch] {
        gameCenter.sortedMatchesForDisplay(gameCenter.finishedMatches)
    }

    private var visibleMatches: [GKTurnBasedMatch] {
        Array(sortedFinishedMatches.prefix(pageSize))
    }

    private var emptyState: some View {
        Text("No finished matches yet.")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(primaryText)
            .padding(.horizontal, 6)
    }

    private var primaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.93, blue: 0.98)
            : Color(red: 0.12, green: 0.13, blue: 0.16)
    }

    private var buttonBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }
}
