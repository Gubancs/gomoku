import SwiftUI

/// Draws the interior grid lines for the board.
struct BoardGridView: View {
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
        .stroke(Color.gray.opacity(0.35), lineWidth: 1)
    }
}
