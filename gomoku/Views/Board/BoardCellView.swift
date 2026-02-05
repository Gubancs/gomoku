import SwiftUI

/// Renders a single board cell and its optional stone.
struct BoardCellView: View {
    let player: Player?
    let size: CGFloat
    let isLastMove: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white)

            if let player {
                StoneView(player: player)
                    .frame(width: size * 0.8, height: size * 0.8)
            }

            if isLastMove {
                Rectangle()
                    .stroke(Color.blue.opacity(0.85), lineWidth: max(2, size * 0.07))
                    .shadow(color: Color.blue.opacity(0.6), radius: size * 0.16)
                    .clipShape(Rectangle())
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
