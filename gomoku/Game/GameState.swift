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
    let currentPlayer: Player
    let winner: Player?
    let isDraw: Bool
    let lastMove: LastMove?
    let winningLine: WinningLine?
    let partyCode: String?
    let playerSymbolPreferences: [String: PlayerSymbolPreferences]

    init(
        board: [[Player?]],
        currentPlayer: Player,
        winner: Player?,
        isDraw: Bool,
        lastMove: LastMove?,
        winningLine: WinningLine?,
        partyCode: String? = nil,
        playerSymbolPreferences: [String: PlayerSymbolPreferences] = [:]
    ) {
        self.board = board
        self.currentPlayer = currentPlayer
        self.winner = winner
        self.isDraw = isDraw
        self.lastMove = lastMove
        self.winningLine = winningLine
        self.partyCode = partyCode
        self.playerSymbolPreferences = playerSymbolPreferences
    }

    private enum CodingKeys: String, CodingKey {
        case board
        case currentPlayer
        case winner
        case isDraw
        case lastMove
        case winningLine
        case partyCode
        case playerSymbolPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        board = try container.decode([[Player?]].self, forKey: .board)
        currentPlayer = try container.decode(Player.self, forKey: .currentPlayer)
        winner = try container.decodeIfPresent(Player.self, forKey: .winner)
        isDraw = try container.decode(Bool.self, forKey: .isDraw)
        lastMove = try container.decodeIfPresent(LastMove.self, forKey: .lastMove)
        winningLine = try container.decodeIfPresent(WinningLine.self, forKey: .winningLine)
        partyCode = try container.decodeIfPresent(String.self, forKey: .partyCode)
        playerSymbolPreferences = try container.decodeIfPresent([String: PlayerSymbolPreferences].self, forKey: .playerSymbolPreferences) ?? [:]
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> GameState? {
        try? JSONDecoder().decode(GameState.self, from: data)
    }
}
