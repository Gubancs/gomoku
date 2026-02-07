import Foundation

/// Stores and mutates the Gomoku board grid.
/// - Note: The board is expected to remain a square of `size` x `size`.
final class GomokuBoard {
    let size: Int
    private(set) var grid: [[Player?]]

    /// Creates an empty board of the requested size.
    init(size: Int) {
        self.size = size
        self.grid = Array(
            repeating: Array(repeating: nil, count: size),
            count: size
        )
    }

    /// Resets the board to an empty grid.
    func reset() {
        grid = Array(
            repeating: Array(repeating: nil, count: size),
            count: size
        )
    }

    /// Replaces the board grid with a snapshot (assumes the grid is valid).
    func replace(with grid: [[Player?]]) {
        self.grid = grid
    }

    /// Returns true when the coordinates are on the board.
    func isWithinBounds(row: Int, col: Int) -> Bool {
        row >= 0 && row < size && col >= 0 && col < size
    }

    /// Returns true when the cell is empty.
    func isEmpty(row: Int, col: Int) -> Bool {
        guard isWithinBounds(row: row, col: col) else { return false }
        return grid[row][col] == nil
    }

    /// Places a stone on the board (no validation performed).
    func place(player: Player, row: Int, col: Int) {
        guard isWithinBounds(row: row, col: col) else { return }
        grid[row][col] = player
    }

    /// Removes any stone from the given cell.
    func clear(row: Int, col: Int) {
        guard isWithinBounds(row: row, col: col) else { return }
        grid[row][col] = nil
    }

    /// Returns true when there is at least one stone already on the board.
    func hasAnyStone() -> Bool {
        grid.contains { row in
            row.contains { $0 != nil }
        }
    }

    /// Returns true when the board has no empty cells left.
    func isFull() -> Bool {
        grid.allSatisfy { row in
            row.allSatisfy { $0 != nil }
        }
    }

    /// Returns true when the candidate cell touches an existing stone in 8 directions.
    func hasAdjacentStone(row: Int, col: Int) -> Bool {
        for dRow in -1...1 {
            for dCol in -1...1 {
                if dRow == 0, dCol == 0 { continue }

                let nextRow = row + dRow
                let nextCol = col + dCol
                guard isWithinBounds(row: nextRow, col: nextCol) else {
                    continue
                }

                if grid[nextRow][nextCol] != nil {
                    return true
                }
            }
        }
        return false
    }
}
