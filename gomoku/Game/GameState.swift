import Foundation

/// Lightweight representation of the most recent move.
struct LastMove: Codable, Equatable {
    let row: Int
    let col: Int
    let player: Player
}

/// Serializable snapshot of the game used for turn-based sync.
struct GameState: Codable {
    let board: [[Player?]]
    let currentPlayer: Player
    let winner: Player?
    let isDraw: Bool
    let lastMove: LastMove?
    let winningLine: WinningLine?

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> GameState? {
        try? JSONDecoder().decode(GameState.self, from: data)
    }
}
