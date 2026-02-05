import SwiftUI

/// Simple 2D stone rendering with minimal styling.
struct StoneView: View {
    let player: Player

    var body: some View {
        Image(player == .black ? "StoneO" : "StoneX")
            .resizable()
            .scaledToFit()
    }
}
