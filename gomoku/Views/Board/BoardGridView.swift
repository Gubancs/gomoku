import SwiftUI

/// Draws the interior grid lines for the board.
struct BoardGridView: View {
    @Environment(\.colorScheme)
    private var colorScheme

    let boardSize: Int
    let cellSize: CGFloat

    var body: some View {
        Path { path in
            let size = cellSize * CGFloat(boardSize)
            for i in 1..<boardSize {
                let offset = CGFloat(i) * cellSize

                path.move(to: CGPoint(x: 0, y: offset))
                path.addLine(to: CGPoint(x: size, y: offset))

                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset, y: size))
            }
        }
        .stroke(
            colorScheme == .dark
                ? Color(red: 0.74, green: 0.84, blue: 0.96).opacity(0.34)
                : Color.gray.opacity(0.35),
            lineWidth: 1
        )
    }
}
