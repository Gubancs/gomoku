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
        .large: 0.95
    ]
}

enum StoneSymbolOption: String, CaseIterable, Identifiable {
    case x
    case o
    case heart
    case star
    case diamond
    case triangle
    case square
    case plus
    case spark
    case sun
    case spade
    case club
    case pentagon
    case hexagon
    case ring
    case sparkles
    case circle
    case diamondOutline
    case triangleOutline
    case squareOutline
    case star6
    case cross

    var id: String { rawValue }

    var glyph: String {
        switch self {
        case .x:
            return "X"
        case .o:
            return "O"
        case .heart:
            return "❤"
        case .star:
            return "★"
        case .diamond:
            return "◆"
        case .triangle:
            return "▲"
        case .square:
            return "■"
        case .plus:
            return "+"
        case .spark:
            return "✦"
        case .sun:
            return "☀"
        case .spade:
            return "♠"
        case .club:
            return "♣"
        case .pentagon:
            return "⬟"
        case .hexagon:
            return "⬢"
        case .ring:
            return "◍"
        case .sparkles:
            return "✧"
        case .circle:
            return "●"
        case .diamondOutline:
            return "◇"
        case .triangleOutline:
            return "△"
        case .squareOutline:
            return "□"
        case .star6:
            return "✶"
        case .cross:
            return "✚"
        }
    }

    var title: String {
        switch self {
        case .x:
            return "X"
        case .o:
            return "O"
        case .heart:
            return "Heart"
        case .star:
            return "Star"
        case .diamond:
            return "Diamond"
        case .triangle:
            return "Triangle"
        case .square:
            return "Square"
        case .plus:
            return "Plus"
        case .spark:
            return "Spark"
        case .sun:
            return "Sun"
        case .spade:
            return "Spade"
        case .club:
            return "Club"
        case .pentagon:
            return "Pentagon"
        case .hexagon:
            return "Hexagon"
        case .ring:
            return "Ring"
        case .sparkles:
            return "Sparkles"
        case .circle:
            return "Circle"
        case .diamondOutline:
            return "Diamond Outline"
        case .triangleOutline:
            return "Triangle Outline"
        case .squareOutline:
            return "Square Outline"
        case .star6:
            return "Six-Point Star"
        case .cross:
            return "Cross"
        }
    }

    var supportsThemeTint: Bool {
        switch self {
        case .heart, .sun:
            return false
        default:
            return true
        }
    }
}

enum StoneSymbolConfiguration {
    static let blackStorageKey = "stoneSymbol.black"
    static let whiteStorageKey = "stoneSymbol.white"
    static let defaultBlack: StoneSymbolOption = .x
    static let defaultWhite: StoneSymbolOption = .o
    static let selectableOptions: [StoneSymbolOption] = StoneSymbolOption.allCases.filter(\.supportsThemeTint)

    static func option(for player: Player, defaults: UserDefaults = .standard) -> StoneSymbolOption {
        let key = player == .black ? blackStorageKey : whiteStorageKey
        let fallback = player == .black ? defaultBlack : defaultWhite
        return validatedOption(rawValue: defaults.string(forKey: key), fallback: fallback)
    }

    static func validatedOption(rawValue: String?, fallback: StoneSymbolOption) -> StoneSymbolOption {
        guard let rawValue,
              let option = StoneSymbolOption(rawValue: rawValue),
              option.supportsThemeTint else {
            return fallback
        }
        return option
    }

    static func displayColor(for player: Player, colorScheme: ColorScheme) -> Color {
        if player == .black {
            return Color(red: 0.90, green: 0.22, blue: 0.25)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.96)
            : Color.black.opacity(0.92)
    }
}

/// Simple 2D stone rendering with minimal styling.
struct StoneView: View {
    @Environment(\.colorScheme) private var colorScheme
    let player: Player
    let blackSymbol: StoneSymbolOption
    let whiteSymbol: StoneSymbolOption

    init(
        player: Player,
        blackSymbol: StoneSymbolOption = StoneSymbolConfiguration.defaultBlack,
        whiteSymbol: StoneSymbolOption = StoneSymbolConfiguration.defaultWhite
    ) {
        self.player = player
        self.blackSymbol = blackSymbol
        self.whiteSymbol = whiteSymbol
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            Text(selectedSymbol.glyph)
                .font(.system(size: size * 0.78, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .foregroundStyle(symbolColor)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: size * 0.04, x: 0, y: size * 0.02)
                .frame(width: size, height: size, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var selectedSymbol: StoneSymbolOption {
        player == .black ? blackSymbol : whiteSymbol
    }

    private var symbolColor: Color {
        StoneSymbolConfiguration.displayColor(for: player, colorScheme: colorScheme)
    }
}
