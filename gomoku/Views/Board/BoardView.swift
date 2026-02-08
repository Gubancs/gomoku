import SwiftUI

/// Renders the full Gomoku board with tappable cells and a simple grid overlay.
struct BoardView: View {
    @Environment(\.colorScheme)
    private var colorScheme

    @AppStorage(StoneSizeConfiguration.storageKey)
    private var stoneSizeOptionRawValue: String = StoneSizeConfiguration.defaultOption.rawValue
    @AppStorage(StoneSymbolConfiguration.blackStorageKey)
    private var blackSymbolRawValue: String = StoneSymbolConfiguration.defaultBlack.rawValue
    @AppStorage(StoneSymbolConfiguration.whiteStorageKey)
    private var whiteSymbolRawValue: String = StoneSymbolConfiguration.defaultWhite.rawValue

    @ObservedObject var game: GomokuGame
    let cellSize: CGFloat
    var isInteractionEnabled: Bool = true
    var onCellTap: ((Int, Int) -> Void)? = nil
    var boardOverride: [[Player?]]? = nil
    var lastMoveOverride: LastMove? = nil
    var blackSymbolOverride: StoneSymbolOption? = nil
    var whiteSymbolOverride: StoneSymbolOption? = nil

    var body: some View {
        let board = boardOverride ?? game.board
        let boardSize = board.count
        let size = cellSize * CGFloat(boardSize)
        let lastMove = lastMoveOverride ?? game.lastMove
        let tapHandler = onCellTap ?? { row, col in
            game.placeStone(row: row, col: col)
        }
        let stoneScale = StoneSizeOption(rawValue: stoneSizeOptionRawValue)?.scale
            ?? StoneSizeConfiguration.defaultOption.scale
        let blackSymbol = blackSymbolOverride
            ?? StoneSymbolConfiguration.validatedOption(
                rawValue: blackSymbolRawValue,
                fallback: StoneSymbolConfiguration.defaultBlack
            )
        let whiteSymbol = whiteSymbolOverride
            ?? StoneSymbolConfiguration.validatedOption(
                rawValue: whiteSymbolRawValue,
                fallback: StoneSymbolConfiguration.defaultWhite
            )

        ZStack {
            (colorScheme == .dark
                ? Color(red: 0.10, green: 0.18, blue: 0.28).opacity(0.46)
                : Color.white)

            BoardCellsView(
                board: board,
                cellSize: cellSize,
                stoneScale: stoneScale,
                blackSymbol: blackSymbol,
                whiteSymbol: whiteSymbol,
                lastMove: lastMove,
                onTap: tapHandler
            )
            .allowsHitTesting(isInteractionEnabled)

            BoardGridView(boardSize: boardSize, cellSize: cellSize)
                .allowsHitTesting(false)
            
            // Draw winning line overlay
            if let winningLine = game.winningLine {
                WinningLineView(
                    winningLine: winningLine,
                    cellSize: cellSize,
                    boardSize: boardSize
                )
                .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    BoardView(game: GomokuGame(), cellSize: 40)
        .padding()
}
