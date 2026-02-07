import SwiftUI

struct OfflinePlayersView: View {
    @EnvironmentObject private var offlinePlayers: OfflinePlayersStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var newPlayerName: String = ""
    @FocusState private var isNewPlayerFieldFocused: Bool

    var body: some View {
        ZStack {
            background

            List {
                Section {
                    HStack(spacing: 8) {
                        TextField("Player name", text: $newPlayerName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($isNewPlayerFieldFocused)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isNewPlayerFieldFocused = true
                            }
                            .submitLabel(.done)
                            .onSubmit {
                                addPlayer()
                            }

                        Button("Add") {
                            addPlayer()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("New player")
                        .foregroundStyle(sectionHeaderText)
                }
                .listRowBackground(rowBackground)

                Section {
                    if offlinePlayers.sortedPlayers.isEmpty {
                        Text("No offline players yet.")
                            .foregroundStyle(secondaryText)
                    } else {
                        ForEach(offlinePlayers.sortedPlayers) { player in
                            playerRow(for: player)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deletePlayer(player)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } header: {
                    Text("Players")
                        .foregroundStyle(sectionHeaderText)
                }
                .listRowBackground(rowBackground)
            }
            .scrollContentBackground(.hidden)
            .background(.clear)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Players")
    }

    private func playerRow(for player: OfflinePlayer) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)

                Text("W-L-D: \(player.wins)-\(player.losses)-\(player.draws)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .monospacedDigit()
            }

            Spacer(minLength: 12)

            Text("PTS \(player.points)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(primaryText)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func addPlayer() {
        if offlinePlayers.addPlayer(named: newPlayerName) {
            newPlayerName = ""
            isNewPlayerFieldFocused = false
        }
    }

    private func deletePlayer(_ player: OfflinePlayer) {
        _ = offlinePlayers.deletePlayer(id: player.id)
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

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.12, green: 0.18, blue: 0.32).opacity(0.94),
                            Color(red: 0.24, green: 0.27, blue: 0.34).opacity(0.94)
                        ]
                        : [
                            Color(red: 0.88, green: 0.94, blue: 1.0),
                            Color(red: 0.80, green: 0.90, blue: 1.0)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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

    private var sectionHeaderText: Color {
        colorScheme == .dark
            ? Color(red: 0.76, green: 0.82, blue: 0.92)
            : Color(red: 0.28, green: 0.36, blue: 0.50)
    }
}

#Preview {
    NavigationStack {
        OfflinePlayersView()
            .environmentObject(OfflinePlayersStore())
    }
}
