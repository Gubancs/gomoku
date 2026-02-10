import SwiftUI

struct OfflineMatchSetupView: View {
    @EnvironmentObject private var gameCenter: GameCenterManager
    @EnvironmentObject private var offlinePlayers: OfflinePlayersStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedBlackID: UUID?
    @State private var selectedWhiteID: UUID?

    var body: some View {
        Form {
            selectionSection
            managePlayersSection

            Section {
                Button {
                    startGame()
                } label: {
                    Text("Start Offline Match")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(background)
        .navigationTitle("Offline Match")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .onAppear {
            applySuggestedSelection()
        }
    }

    private var selectionSection: some View {
        Section {
            if offlinePlayers.players.count < 2 {
                Text("Open Players List and add at least 2 players to start an offline match.")
                    .foregroundStyle(secondaryText)
            }

            Picker("Black", selection: $selectedBlackID) {
                Text("Select").tag(Optional<UUID>.none)
                ForEach(offlinePlayers.sortedPlayers) { player in
                    Text(player.name).tag(Optional(player.id))
                }
            }

            Picker("White", selection: $selectedWhiteID) {
                Text("Select").tag(Optional<UUID>.none)
                ForEach(offlinePlayers.sortedPlayers) { player in
                    Text(player.name).tag(Optional(player.id))
                }
            }

            if !canStart, offlinePlayers.players.count >= 2 {
                Text("Choose 2 different players.")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
        } header: {
            Text("Players")
                .foregroundStyle(sectionHeaderText)
        }
        .listRowBackground(rowBackground)
    }

    private var managePlayersSection: some View {
        Section {
            NavigationLink {
                OfflinePlayersView()
                    .environmentObject(offlinePlayers)
            } label: {
                Label("Open Players List", systemImage: "person.3.fill")
            }
        } header: {
            Text("Manage")
                .foregroundStyle(sectionHeaderText)
        }
        .listRowBackground(rowBackground)
    }

    private var canStart: Bool {
        guard let selectedBlackID, let selectedWhiteID else { return false }
        return selectedBlackID != selectedWhiteID
    }

    private func applySuggestedSelection() {
        guard let selection = offlinePlayers.suggestedSelection() else { return }
        if selectedBlackID == nil {
            selectedBlackID = selection.blackID
        }
        if selectedWhiteID == nil {
            selectedWhiteID = selection.whiteID
        }
    }

    private func startGame() {
        guard let selectedBlackID, let selectedWhiteID, selectedBlackID != selectedWhiteID else { return }
        offlinePlayers.selectPlayers(blackID: selectedBlackID, whiteID: selectedWhiteID)
        dismiss()
        DispatchQueue.main.async {
            gameCenter.isDebugMatchActive = true
        }
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
        OfflineMatchSetupView()
            .environmentObject(GameCenterManager())
            .environmentObject(OfflinePlayersStore())
    }
}
