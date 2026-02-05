import SwiftUI

/// Renders the full Gomoku board with tappable cells and a simple grid overlay.
struct BoardView: View {
    @ObservedObject var game: GomokuGame
    let cellSize: CGFloat
    var isInteractionEnabled: Bool = true
    var onCellTap: ((Int, Int) -> Void)? = nil

    var body: some View {
        let boardSize = GomokuGame.boardSize
        let size = cellSize * CGFloat(boardSize)
        let tapHandler = onCellTap ?? { row, col in
            game.placeStone(row: row, col: col)
        }

        ZStack {
            Color.white

            BoardCellsView(
                board: game.board,
                cellSize: cellSize,
                lastMove: game.lastMove,
                onTap: tapHandler
            )
            .allowsHitTesting(isInteractionEnabled)

            BoardGridView(boardSize: boardSize, cellSize: cellSize)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    BoardView(game: GomokuGame(), cellSize: 40)
        .padding()
}
