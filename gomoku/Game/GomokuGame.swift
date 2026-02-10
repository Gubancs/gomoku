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

    var symbol: String {
        StoneSymbolConfiguration.option(for: self).glyph
    }
}

/// A single placed stone with its coordinates and owner.
struct Move: Identifiable, Equatable, Codable {
    let id: UUID
    let row: Int
    let col: Int
    let player: Player

    init(row: Int, col: Int, player: Player, id: UUID = UUID()) {
        self.id = id
        self.row = row
        self.col = col
        self.player = player
    }

    private enum CodingKeys: String, CodingKey {
        case row
        case col
        case player
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        row = try container.decode(Int.self, forKey: .row)
        col = try container.decode(Int.self, forKey: .col)
        player = try container.decode(Player.self, forKey: .player)
        id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(row, forKey: .row)
        try container.encode(col, forKey: .col)
        try container.encode(player, forKey: .player)
    }
}

/// Coordinates the Gomoku board state and applies the rules engine.
final class GomokuGame: ObservableObject {
    static let boardSize = 30
    static let winLength = 5

    let moveTimeLimit: TimeInterval

    private let boardModel: GomokuBoard
    private let rules: GomokuRules

    @Published private(set) var board: [[Player?]]
    @Published private(set) var moves: [Move]
    @Published private(set) var currentPlayer: Player
    @Published private(set) var winner: Player?
    @Published private(set) var isDraw: Bool
    @Published private(set) var lastMove: LastMove?
    @Published private(set) var winningLine: WinningLine?
    private var partyCode: String?
    private var playerSymbolPreferences: [String: PlayerSymbolPreferences]

    /// Creates a fresh game with an empty board.
    init(moveTimeLimit: TimeInterval = 60) {
        self.boardModel = GomokuBoard(size: Self.boardSize)
        self.rules = GomokuRules(winLength: Self.winLength)
        self.moveTimeLimit = moveTimeLimit
        self.board = boardModel.grid
        self.moves = []
        self.currentPlayer = .black
        self.winner = nil
        self.isDraw = false
        self.lastMove = nil
        self.winningLine = nil
        self.partyCode = nil
        self.playerSymbolPreferences = [:]
    }

    /// Clears the board and resets turn and outcome state.
    func reset() {
        boardModel.reset()
        syncBoardFromModel()
        moves = []
        currentPlayer = .black
        winner = nil
        isDraw = false
        lastMove = nil
        winningLine = nil
        partyCode = nil
        playerSymbolPreferences = [:]
    }

    /// Removes the last move and restores the previous player.
    func undoLastMove() {
        guard let last = moves.last else { return }
        boardModel.clear(row: last.row, col: last.col)
        syncBoardFromModel()
        moves.removeLast()
        winner = nil
        isDraw = false
        winningLine = nil
        currentPlayer = last.player
        lastMove = moves.last.map { LastMove(row: $0.row, col: $0.col, player: $0.player) }
    }

    /// Places a stone for the current player if the move is valid.
    func placeStone(row: Int, col: Int) {
        guard winner == nil, !isDraw else { return }
        guard rules.isValidMove(on: boardModel, row: row, col: col) else { return }

        boardModel.place(player: currentPlayer, row: row, col: col)
        syncBoardFromModel()
        moves.append(Move(row: row, col: col, player: currentPlayer))
        lastMove = LastMove(row: row, col: col, player: currentPlayer)

        if rules.isWinningMove(on: boardModel, row: row, col: col, player: currentPlayer) {
            winner = currentPlayer
            winningLine = rules.detectWinningLine(on: boardModel, row: row, col: col, player: currentPlayer)
            return
        }

        if boardModel.isFull() {
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
            moves: moves,
            currentPlayer: currentPlayer,
            winner: winner,
            isDraw: isDraw,
            lastMove: lastMove,
            winningLine: winningLine,
            partyCode: partyCode,
            playerSymbolPreferences: playerSymbolPreferences
        )
    }

    /// Applies a turn-based snapshot to the local game.
    func apply(state: GameState) {
        boardModel.replace(with: state.board)
        syncBoardFromModel()
        currentPlayer = state.currentPlayer
        winner = state.winner
        isDraw = state.isDraw
        lastMove = state.lastMove
        winningLine = state.winningLine
        partyCode = state.partyCode
        playerSymbolPreferences = state.playerSymbolPreferences
        moves = state.moves
    }

    func symbolPreferences(for playerID: String) -> PlayerSymbolPreferences? {
        playerSymbolPreferences[playerID]
    }

    /// Keeps the published board in sync with the board model.
    private func syncBoardFromModel() {
        board = boardModel.grid
    }
}
