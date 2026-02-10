import Foundation

/// Lightweight representation of the most recent move.
struct LastMove: Codable, Equatable {
    let row: Int
    let col: Int
    let player: Player
}

/// Per-player symbol preferences synced through online match state.
struct PlayerSymbolPreferences: Codable, Equatable {
    let blackSymbolRawValue: String
    let whiteSymbolRawValue: String

    init(blackSymbolRawValue: String, whiteSymbolRawValue: String) {
        self.blackSymbolRawValue = blackSymbolRawValue
        self.whiteSymbolRawValue = whiteSymbolRawValue
    }
}

/// Serializable snapshot of the game used for turn-based sync.
struct GameState: Codable {
    let board: [[Player?]]
    let moves: [Move]
    let currentPlayer: Player
    let winner: Player?
    let isDraw: Bool
    let lastMove: LastMove?
    let winningLine: WinningLine?
    let partyCode: String?
    let playerSymbolPreferences: [String: PlayerSymbolPreferences]
    let blackTimeRemaining: TimeInterval?
    let whiteTimeRemaining: TimeInterval?
    let turnStartedAt: TimeInterval?

    init(
        board: [[Player?]],
        moves: [Move] = [],
        currentPlayer: Player,
        winner: Player?,
        isDraw: Bool,
        lastMove: LastMove?,
        winningLine: WinningLine?,
        partyCode: String? = nil,
        playerSymbolPreferences: [String: PlayerSymbolPreferences] = [:],
        blackTimeRemaining: TimeInterval? = nil,
        whiteTimeRemaining: TimeInterval? = nil,
        turnStartedAt: TimeInterval? = nil
    ) {
        self.board = board
        self.moves = moves
        self.currentPlayer = currentPlayer
        self.winner = winner
        self.isDraw = isDraw
        self.lastMove = lastMove
        self.winningLine = winningLine
        self.partyCode = partyCode
        self.playerSymbolPreferences = playerSymbolPreferences
        self.blackTimeRemaining = blackTimeRemaining
        self.whiteTimeRemaining = whiteTimeRemaining
        self.turnStartedAt = turnStartedAt
    }

    private enum CodingKeys: String, CodingKey {
        case board
        case moves
        case currentPlayer
        case winner
        case isDraw
        case lastMove
        case winningLine
        case partyCode
        case playerSymbolPreferences
        case blackTimeRemaining
        case whiteTimeRemaining
        case turnStartedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        board = try container.decode([[Player?]].self, forKey: .board)
        moves = try container.decodeIfPresent([Move].self, forKey: .moves) ?? []
        currentPlayer = try container.decode(Player.self, forKey: .currentPlayer)
        winner = try container.decodeIfPresent(Player.self, forKey: .winner)
        isDraw = try container.decode(Bool.self, forKey: .isDraw)
        lastMove = try container.decodeIfPresent(LastMove.self, forKey: .lastMove)
        winningLine = try container.decodeIfPresent(WinningLine.self, forKey: .winningLine)
        partyCode = try container.decodeIfPresent(String.self, forKey: .partyCode)
        playerSymbolPreferences = try container.decodeIfPresent([String: PlayerSymbolPreferences].self, forKey: .playerSymbolPreferences) ?? [:]
        blackTimeRemaining = try container.decodeIfPresent(TimeInterval.self, forKey: .blackTimeRemaining)
        whiteTimeRemaining = try container.decodeIfPresent(TimeInterval.self, forKey: .whiteTimeRemaining)
        turnStartedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .turnStartedAt)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> GameState? {
        try? JSONDecoder().decode(GameState.self, from: data)
    }
}
