import Foundation
import Combine

/// A player in the Gomoku game.
enum Player: String, Codable {
    case black
    case white

    var next: Player {
        self == .black ? .white : .black
    }

    var displayName: String {
        self == .black ? "Black" : "White"
    }
}

/// A single placed stone with its coordinates and owner.
struct Move: Identifiable, Equatable {
    let id = UUID()
    let row: Int
    let col: Int
    let player: Player
}

/// Core game logic and board state for Gomoku.
final class GomokuGame: ObservableObject {
    static let boardSize = 30
    static let winLength = 5

    let moveTimeLimit: TimeInterval

    @Published private(set) var board: [[Player?]]
    @Published private(set) var moves: [Move]
    @Published private(set) var currentPlayer: Player
    @Published private(set) var winner: Player?
    @Published private(set) var isDraw: Bool
    @Published private(set) var lastMove: LastMove?

    /// Creates a fresh game with an empty board.
    init(moveTimeLimit: TimeInterval = 50) {
        self.moveTimeLimit = moveTimeLimit
        self.board = Array(
            repeating: Array(repeating: nil, count: Self.boardSize),
            count: Self.boardSize
        )
        self.moves = []
        self.currentPlayer = .black
        self.winner = nil
        self.isDraw = false
        self.lastMove = nil
    }

    /// Clears the board and resets turn and outcome state.
    func reset() {
        board = Array(
            repeating: Array(repeating: nil, count: Self.boardSize),
            count: Self.boardSize
        )
        moves = []
        currentPlayer = .black
        winner = nil
        isDraw = false
        lastMove = nil
    }

    /// Removes the last move and restores the previous player.
    func undoLastMove() {
        guard let last = moves.last else { return }
        board[last.row][last.col] = nil
        moves.removeLast()
        winner = nil
        isDraw = false
        currentPlayer = last.player
        lastMove = moves.last.map { LastMove(row: $0.row, col: $0.col, player: $0.player) }
    }

    /// Places a stone for the current player if the move is valid.
    func placeStone(row: Int, col: Int) {
        guard winner == nil, !isDraw else { return }
        guard board.indices.contains(row), board[row].indices.contains(col) else { return }
        guard board[row][col] == nil else { return }
        guard !hasAnyStone() || hasAdjacentStone(row: row, col: col) else { return }

        board[row][col] = currentPlayer
        moves.append(Move(row: row, col: col, player: currentPlayer))
        lastMove = LastMove(row: row, col: col, player: currentPlayer)

        if checkWin(fromRow: row, col: col, player: currentPlayer) {
            winner = currentPlayer
            return
        }

        if isBoardFull() {
            isDraw = true
            return
        }

        currentPlayer = currentPlayer.next
    }

    /// Marks the current player as the loser due to running out of time.
    func timeoutCurrentPlayer() {
        guard winner == nil, !isDraw else { return }
        winner = currentPlayer.next
    }

    /// Marks the provided player as resigned and sets the winner accordingly.
    func resign(player: Player) {
        guard winner == nil, !isDraw else { return }
        winner = player.next
    }

    /// Captures a lightweight snapshot for turn-based sync.
    func makeState() -> GameState {
        GameState(
            board: board,
            currentPlayer: currentPlayer,
            winner: winner,
            isDraw: isDraw,
            lastMove: lastMove
        )
    }

    /// Applies a turn-based snapshot to the local game.
    func apply(state: GameState) {
        board = state.board
        currentPlayer = state.currentPlayer
        winner = state.winner
        isDraw = state.isDraw
        lastMove = state.lastMove
        moves = []
    }

    /// Checks whether the most recent move created a win.
    private func checkWin(fromRow row: Int, col: Int, player: Player) -> Bool {
        let directions = [
            (1, 0),   // vertical
            (0, 1),   // horizontal
            (1, 1),   // diagonal down-right
            (1, -1)   // diagonal down-left
        ]

        for direction in directions {
            let count = 1
                + countDirection(row: row, col: col, player: player, dRow: direction.0, dCol: direction.1)
                + countDirection(row: row, col: col, player: player, dRow: -direction.0, dCol: -direction.1)
            if count >= Self.winLength {
                return true
            }
        }
        return false
    }

    /// Counts consecutive stones in a given direction.
    private func countDirection(row: Int, col: Int, player: Player, dRow: Int, dCol: Int) -> Int {
        var r = row + dRow
        var c = col + dCol
        var count = 0

        while r >= 0, r < Self.boardSize, c >= 0, c < Self.boardSize {
            if board[r][c] == player {
                count += 1
                r += dRow
                c += dCol
            } else {
                break
            }
        }

        return count
    }

    private func isBoardFull() -> Bool {
        board.allSatisfy { row in
            row.allSatisfy { $0 != nil }
        }
    }

    /// Returns true when there is at least one stone already on the board.
    private func hasAnyStone() -> Bool {
        board.contains { row in
            row.contains { $0 != nil }
        }
    }

    /// Returns true when the candidate cell touches an existing stone in 8 directions.
    private func hasAdjacentStone(row: Int, col: Int) -> Bool {
        for dRow in -1...1 {
            for dCol in -1...1 {
                if dRow == 0, dCol == 0 { continue }

                let nextRow = row + dRow
                let nextCol = col + dCol
                guard board.indices.contains(nextRow),
                      board[nextRow].indices.contains(nextCol) else {
                    continue
                }

                if board[nextRow][nextCol] != nil {
                    return true
                }
            }
        }
        return false
    }
}
