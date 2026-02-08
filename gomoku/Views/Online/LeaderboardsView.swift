internal import GameKit
import SwiftUI

struct LeaderboardsView: View {
    @ObservedObject var gameCenter: GameCenterManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var audience: LeaderboardAudienceScope = .global
    @State private var timeRange: LeaderboardTimeRange = .allTime
    @State private var rows: [LeaderboardPlayerRow] = []
    @State private var isLoading: Bool = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    filterCard

                    if let errorText, !errorText.isEmpty {
                        errorBanner(errorText)
                    } else if isLoading {
                        loadingCard
                    } else if rows.isEmpty {
                        emptyCard
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(rows) { row in
                                rowCard(row)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .refreshable {
                await reload()
            }
        }
        .navigationTitle("Leaderboards")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
        }
        .onChange(of: audience) { _ in
            Task { await reload() }
        }
        .onChange(of: timeRange) { _ in
            Task { await reload() }
        }
    }

    private var filterCard: some View {
        VStack(spacing: 10) {
            Picker("Audience", selection: $audience) {
                ForEach(LeaderboardAudienceScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Picker("Time", selection: $timeRange) {
                ForEach(LeaderboardTimeRange.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var loadingCard: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading leaderboard...")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.number")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(secondaryText)
            Text("No entries for this filter.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.red.opacity(colorScheme == .dark ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func rowCard(_ row: LeaderboardPlayerRow) -> some View {
        HStack(spacing: 12) {
            rankBadge(row.rank)

            avatar(for: row)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)

                    if row.isLocal {
                        Text("YOU")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.26, green: 0.50, blue: 0.88), in: Capsule())
                    }
                }

                Text("Rank #\(row.rank)")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(row.score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(primaryText)
                Text("ELO")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.12, green: 0.18, blue: 0.32),
                        Color(red: 0.24, green: 0.27, blue: 0.34)
                    ]
                    : [
                        Color(red: 0.92, green: 0.97, blue: 1.0),
                        Color(red: 0.74, green: 0.86, blue: 0.98)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.55), lineWidth: 1)
        )
    }

    private func rankBadge(_ rank: Int) -> some View {
        Text("#\(rank)")
            .font(.caption.weight(.bold))
            .foregroundStyle(primaryText)
            .frame(width: 40, height: 28)
            .background(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }

    private func avatar(for row: LeaderboardPlayerRow) -> some View {
        let image = gameCenter.avatarImage(for: row.player)
        let initials = initials(for: row.displayName)

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.9))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private func initials(for name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        let chars = parts.prefix(2).compactMap { $0.first }
        let value = String(chars).uppercased()
        return value.isEmpty ? "?" : value
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

    private var primaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.89, green: 0.93, blue: 0.98)
            : Color(red: 0.12, green: 0.13, blue: 0.16)
    }

    private var secondaryText: Color {
        colorScheme == .dark
            ? Color(red: 0.72, green: 0.79, blue: 0.90)
            : Color(red: 0.32, green: 0.34, blue: 0.38)
    }

    @MainActor
    private func reload() async {
        isLoading = true
        errorText = nil
        do {
            rows = try await gameCenter.loadLeaderboardRows(audience: audience, timeRange: timeRange, limit: 100)
        } catch {
            errorText = error.localizedDescription
            rows = []
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        LeaderboardsView(gameCenter: GameCenterManager())
    }
}
