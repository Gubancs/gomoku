import SwiftUI

struct SettingsView: View {
    let symbolsLocked: Bool

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("soundEnabled") private var isSoundEnabled: Bool = true
    @AppStorage(SoundEffects.volumeStorageKey) private var soundVolume: Double = SoundEffects.defaultVolume
    @AppStorage(StoneSizeConfiguration.storageKey)
    private var stoneSizeOptionRawValue: String = StoneSizeConfiguration.defaultOption.rawValue
    @AppStorage(StoneSymbolConfiguration.blackStorageKey)
    private var blackSymbolRawValue: String = StoneSymbolConfiguration.defaultBlack.rawValue
    @AppStorage(StoneSymbolConfiguration.whiteStorageKey)
    private var whiteSymbolRawValue: String = StoneSymbolConfiguration.defaultWhite.rawValue

    init(symbolsLocked: Bool = false) {
        self.symbolsLocked = symbolsLocked
    }

    var body: some View {
        ZStack {
            background

            Form {
                Section {
                    Toggle("Game sounds", isOn: $isSoundEnabled)
                        .listRowBackground(settingsRowBackground)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Game volume")
                            Spacer()
                            Text("\(Int(soundVolume * 100))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(sectionHeaderText)
                                .monospacedDigit()
                        }

                        Slider(value: $soundVolume, in: 0...1, step: 0.05)
                            .tint(accentBlue)
                            .disabled(!isSoundEnabled)
                    }
                    .opacity(isSoundEnabled ? 1 : 0.55)
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

                Section {
                    symbolGridRow(
                        title: "X player symbol",
                        player: .black,
                        selection: $blackSymbolRawValue
                    )
                    .listRowBackground(settingsRowBackground)

                    symbolGridRow(
                        title: "O player symbol",
                        player: .white,
                        selection: $whiteSymbolRawValue
                    )
                    .listRowBackground(settingsRowBackground)
                } header: {
                    Text("Stone Symbols")
                        .foregroundStyle(sectionHeaderText)
                } footer: {
                    Text(canEditSymbols
                         ? "Pick from the fixed symbol set for each player."
                         : "Symbols are locked while an online match is in progress.")
                        .foregroundStyle(sectionHeaderText.opacity(0.88))
                }
            }
            .scrollContentBackground(.hidden)
            .background(.clear)
            .tint(accentBlue)
        }
        .navigationTitle("Settings")
        .onAppear {
            sanitizeStoredSymbolsIfNeeded()
            soundVolume = SoundEffects.clampedVolume(soundVolume)
            SoundEffects.setVolume(soundVolume)
        }
        .onChange(of: soundVolume) { newValue in
            let clamped = SoundEffects.clampedVolume(newValue)
            if clamped != newValue {
                soundVolume = clamped
            }
            SoundEffects.setVolume(clamped)
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

    private var canEditSymbols: Bool {
        !symbolsLocked
    }

    private let symbolButtonSize: CGFloat = 34

    private func symbolGridRow(
        title: String,
        player: Player,
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(sectionHeaderText)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(StoneSymbolConfiguration.selectableOptions) { option in
                        let isActive = selection.wrappedValue == option.rawValue
                        Button {
                            guard canEditSymbols else { return }
                            selection.wrappedValue = option.rawValue
                        } label: {
                            Text(option.glyph)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(StoneSymbolConfiguration.displayColor(for: player, colorScheme: colorScheme))
                                .frame(width: symbolButtonSize, height: symbolButtonSize)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(
                                            isActive
                                                ? accentBlue.opacity(colorScheme == .dark ? 0.35 : 0.20)
                                                : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.58)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(
                                            isActive
                                                ? accentBlue.opacity(0.95)
                                                : Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10),
                                            lineWidth: isActive ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEditSymbols)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func sanitizeStoredSymbolsIfNeeded() {
        let safeBlack = StoneSymbolConfiguration.validatedOption(
            rawValue: blackSymbolRawValue,
            fallback: StoneSymbolConfiguration.defaultBlack
        ).rawValue
        if blackSymbolRawValue != safeBlack {
            blackSymbolRawValue = safeBlack
        }

        let safeWhite = StoneSymbolConfiguration.validatedOption(
            rawValue: whiteSymbolRawValue,
            fallback: StoneSymbolConfiguration.defaultWhite
        ).rawValue
        if whiteSymbolRawValue != safeWhite {
            whiteSymbolRawValue = safeWhite
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
