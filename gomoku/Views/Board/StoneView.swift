import SwiftUI

enum StoneSizeOption: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        }
    }

    var scale: CGFloat {
        StoneSizeConfiguration.scales[self] ?? StoneSizeConfiguration.scales[.medium] ?? 0.8
    }
}

enum StoneSizeConfiguration {
    static let storageKey = "stoneSizeOption"
    static let defaultOption: StoneSizeOption = .medium

    /// Static, centrally managed scale factors used by board cells.
    static let scales: [StoneSizeOption: CGFloat] = [
        .small: 0.68,
        .medium: 0.80,
        .large: 0.98
    ]
}

/// Simple 2D stone rendering with minimal styling.
struct StoneView: View {
    @Environment(\.colorScheme) private var colorScheme
    let player: Player

    var body: some View {
        switch player {
        case .black:
            blackStone
        case .white:
            Image("StoneX")
                .resizable()
                .scaledToFit()
        }
    }

    @ViewBuilder
    private var blackStone: some View {
        if colorScheme == .dark {
            Image("StoneO")
                .renderingMode(Image.TemplateRenderingMode.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(red: 0.84, green: 0.87, blue: 0.92))
        } else {
            Image("StoneO")
                .resizable()
                .scaledToFit()
        }
    }
}
