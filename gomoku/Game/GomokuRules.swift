import Foundation

/// Encapsulates the rules for validating moves and detecting wins.
final class GomokuRules {
    private let winLength: Int

    /// Creates a rules engine configured with the required win length.
    init(winLength: Int) {
        self.winLength = winLength
    }

    /// Returns true when a move is legal on the provided board.
    func isValidMove(on board: GomokuBoard, row: Int, col: Int) -> Bool {
        guard board.isWithinBounds(row: row, col: col) else { return false }
        guard board.isEmpty(row: row, col: col) else { return false }
        guard !board.hasAnyStone() || board.hasAdjacentStone(row: row, col: col) else { return false }
        return true
    }

    /// Returns true when the move completes a winning line.
    func isWinningMove(on board: GomokuBoard, row: Int, col: Int, player: Player) -> Bool {
        let directions = [
            (1, 0),   // vertical
            (0, 1),   // horizontal
            (1, 1),   // diagonal down-right
            (1, -1)   // diagonal down-left
        ]

        for direction in directions {
            let count = 1
                + countDirection(on: board, row: row, col: col, player: player, dRow: direction.0, dCol: direction.1)
                + countDirection(on: board, row: row, col: col, player: player, dRow: -direction.0, dCol: -direction.1)
            if count >= winLength {
                return true
            }
        }
        return false
    }

    /// Counts consecutive stones in a given direction.
    private func countDirection(on board: GomokuBoard, row: Int, col: Int, player: Player, dRow: Int, dCol: Int) -> Int {
        var r = row + dRow
        var c = col + dCol
        var count = 0

        while r >= 0, r < board.size, c >= 0, c < board.size {
            if board.grid[r][c] == player {
                count += 1
                r += dRow
                c += dCol
            } else {
                break
            }
        }

        return count
    }
}
