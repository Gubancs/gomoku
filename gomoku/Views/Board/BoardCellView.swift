import SwiftUI

/// Renders a single board cell and its optional stone.
struct BoardCellView: View {
    @Environment(\.colorScheme)
    private var colorScheme

    let player: Player?
    let size: CGFloat
    let stoneScale: CGFloat
    let isLastMove: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(
                colorScheme == .dark
                    ? Color(red: 0.17, green: 0.27, blue: 0.40).opacity(0.74)
                    : Color.white
            )

            if let player {
                StoneView(player: player)
                    .frame(width: size * stoneScale, height: size * stoneScale)
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
