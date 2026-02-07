import Foundation

/// Represents a winning line of stones.
struct WinningLine: Codable, Equatable {
    let startRow: Int
    let startCol: Int
    let endRow: Int
    let endCol: Int
    let player: Player
}

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
    
    /// Detects and returns the winning line coordinates when a move completes a winning sequence.
    /// Returns nil if the move does not result in a win.
    func detectWinningLine(on board: GomokuBoard, row: Int, col: Int, player: Player) -> WinningLine? {
        let directions = [
            (1, 0),   // vertical
            (0, 1),   // horizontal
            (1, 1),   // diagonal down-right
            (1, -1)   // diagonal down-left
        ]

        for direction in directions {
            let forwardCount = countDirection(on: board, row: row, col: col, player: player, dRow: direction.0, dCol: direction.1)
            let backwardCount = countDirection(on: board, row: row, col: col, player: player, dRow: -direction.0, dCol: -direction.1)
            let totalCount = 1 + forwardCount + backwardCount
            
            if totalCount >= winLength {
                // Find the start and end positions of the winning line
                let startRow = row - backwardCount * direction.0
                let startCol = col - backwardCount * direction.1
                let endRow = row + forwardCount * direction.0
                let endCol = col + forwardCount * direction.1
                
                return WinningLine(
                    startRow: startRow,
                    startCol: startCol,
                    endRow: endRow,
                    endCol: endCol,
                    player: player
                )
            }
        }
        return nil
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
