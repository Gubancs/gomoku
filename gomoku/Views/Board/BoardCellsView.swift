import SwiftUI

/// Builds the grid of tappable cells using the game board state.
struct BoardCellsView: View {
    let board: [[Player?]]
    let cellSize: CGFloat
    let stoneScale: CGFloat
    let blackSymbol: StoneSymbolOption
    let whiteSymbol: StoneSymbolOption
    let lastMove: LastMove?
    let onTap: (Int, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(board.indices, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(board[row].indices, id: \.self) { col in
                        let isLastMove = lastMove?.row == row && lastMove?.col == col
                        BoardCellView(
                            player: board[row][col],
                            size: cellSize,
                            stoneScale: stoneScale,
                            blackSymbol: blackSymbol,
                            whiteSymbol: whiteSymbol,
                            isLastMove: isLastMove,
                            onTap: { onTap(row, col) }
                        )
                    }
                }
            }
        }
    }
}
