import SwiftUI

struct SettingsView: View {
    @AppStorage("soundEnabled") private var isSoundEnabled: Bool = true

    var body: some View {
        Form {
            Section("Sound") {
                Toggle("Game sounds", isOn: $isSoundEnabled)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
