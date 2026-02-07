import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("soundEnabled") private var isSoundEnabled: Bool = true
    @AppStorage(StoneSizeConfiguration.storageKey)
    private var stoneSizeOptionRawValue: String = StoneSizeConfiguration.defaultOption.rawValue

    var body: some View {
        ZStack {
            background

            Form {
                Section {
                    Toggle("Game sounds", isOn: $isSoundEnabled)
                        .listRowBackground(settingsRowBackground)
                } header: {
                    Text("Sound")
                        .foregroundStyle(sectionHeaderText)
                }

                Section {
                    Picker("Stone size", selection: $stoneSizeOptionRawValue) {
                        ForEach(StoneSizeOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(settingsRowBackground)
                } header: {
                    Text("Board")
                        .foregroundStyle(sectionHeaderText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(.clear)
            .tint(accentBlue)
        }
        .navigationTitle("Settings")
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

    private var settingsRowBackground: some View {
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
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.70), lineWidth: 1)
            )
    }

    private var sectionHeaderText: Color {
        colorScheme == .dark
            ? Color(red: 0.76, green: 0.82, blue: 0.92)
            : Color(red: 0.28, green: 0.36, blue: 0.50)
    }

    private var accentBlue: Color {
        colorScheme == .dark
            ? Color(red: 0.52, green: 0.72, blue: 1.0)
            : Color(red: 0.26, green: 0.50, blue: 0.88)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
