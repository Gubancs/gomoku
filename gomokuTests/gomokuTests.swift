//
//  gomokuTests.swift
//  gomokuTests
//
//  Created by Gabor Kokeny on 03/02/2026.
//

import Testing
@testable import gomoku

struct gomokuTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func testHorizontalWinningLineDetection() {
        let board = GomokuBoard(size: 15)
        let rules = GomokuRules(winLength: 5)
        let player = Player.black
        
        // Place 5 stones horizontally
        for col in 0..<5 {
            board.place(player: player, row: 7, col: col)
        }
        
        // Test the winning move detection
        let winningLine = rules.detectWinningLine(on: board, row: 7, col: 2, player: player)
        
        #expect(winningLine != nil)
        #expect(winningLine?.startRow == 7)
        #expect(winningLine?.startCol == 0)
        #expect(winningLine?.endRow == 7)
        #expect(winningLine?.endCol == 4)
        #expect(winningLine?.player == player)
    }
    
    @Test func testVerticalWinningLineDetection() {
        let board = GomokuBoard(size: 15)
        let rules = GomokuRules(winLength: 5)
        let player = Player.white
        
        // Place 5 stones vertically
        for row in 3..<8 {
            board.place(player: player, row: row, col: 5)
        }
        
        // Test the winning move detection
        let winningLine = rules.detectWinningLine(on: board, row: 5, col: 5, player: player)
        
        #expect(winningLine != nil)
        #expect(winningLine?.startRow == 3)
        #expect(winningLine?.startCol == 5)
        #expect(winningLine?.endRow == 7)
        #expect(winningLine?.endCol == 5)
        #expect(winningLine?.player == player)
    }
    
    @Test func testDiagonalDownRightWinningLineDetection() {
        let board = GomokuBoard(size: 15)
        let rules = GomokuRules(winLength: 5)
        let player = Player.black
        
        // Place 5 stones diagonally
        for i in 0..<5 {
            board.place(player: player, row: i, col: i)
        }
        
        // Test the winning move detection
        let winningLine = rules.detectWinningLine(on: board, row: 2, col: 2, player: player)
        
        #expect(winningLine != nil)
        #expect(winningLine?.startRow == 0)
        #expect(winningLine?.startCol == 0)
        #expect(winningLine?.endRow == 4)
        #expect(winningLine?.endCol == 4)
        #expect(winningLine?.player == player)
    }
    
    @Test func testDiagonalDownLeftWinningLineDetection() {
        let board = GomokuBoard(size: 15)
        let rules = GomokuRules(winLength: 5)
        let player = Player.white
        
        // Place 5 stones diagonally down-left
        for i in 0..<5 {
            board.place(player: player, row: i, col: 10 - i)
        }
        
        // Test the winning move detection
        let winningLine = rules.detectWinningLine(on: board, row: 2, col: 8, player: player)
        
        #expect(winningLine != nil)
        #expect(winningLine?.startRow == 0)
        #expect(winningLine?.startCol == 10)
        #expect(winningLine?.endRow == 4)
        #expect(winningLine?.endCol == 6)
        #expect(winningLine?.player == player)
    }
    
    @Test func testNoWinningLineWhenNotEnoughStones() {
        let board = GomokuBoard(size: 15)
        let rules = GomokuRules(winLength: 5)
        let player = Player.black
        
        // Place only 4 stones horizontally
        for col in 0..<4 {
            board.place(player: player, row: 7, col: col)
        }
        
        // Test that no winning line is detected
        let winningLine = rules.detectWinningLine(on: board, row: 7, col: 2, player: player)
        
        #expect(winningLine == nil)
    }
    
    @Test func testGameStoresWinningLine() {
        let game = GomokuGame()
        
        // Place stones to create a horizontal winning line
        // Black's turn
        game.placeStone(row: 7, col: 0)
        // White's turn
        game.placeStone(row: 8, col: 0)
        // Black's turn
        game.placeStone(row: 7, col: 1)
        // White's turn
        game.placeStone(row: 8, col: 1)
        // Black's turn
        game.placeStone(row: 7, col: 2)
        // White's turn
        game.placeStone(row: 8, col: 2)
        // Black's turn
        game.placeStone(row: 7, col: 3)
        // White's turn
        game.placeStone(row: 8, col: 3)
        // Black's winning move
        game.placeStone(row: 7, col: 4)
        
        #expect(game.winner == Player.black)
        #expect(game.winningLine != nil)
        #expect(game.winningLine?.startRow == 7)
        #expect(game.winningLine?.startCol == 0)
        #expect(game.winningLine?.endRow == 7)
        #expect(game.winningLine?.endCol == 4)
        #expect(game.winningLine?.player == Player.black)
    }
    
    @Test func testWinningLinePersistedInGameState() {
        let game = GomokuGame()
        
        // Create a winning scenario
        for col in 0..<5 {
            game.placeStone(row: 5, col: col)
            if col < 4 {
                game.placeStone(row: 6, col: col)
            }
        }
        
        // Capture state
        let state = game.makeState()
        
        #expect(state.winner == Player.black)
        #expect(state.winningLine != nil)
        #expect(state.winningLine?.startRow == 5)
        #expect(state.winningLine?.startCol == 0)
        #expect(state.winningLine?.endRow == 5)
        #expect(state.winningLine?.endCol == 4)
        
        // Apply state to a new game
        let newGame = GomokuGame()
        newGame.apply(state: state)
        
        #expect(newGame.winner == Player.black)
        #expect(newGame.winningLine != nil)
        #expect(newGame.winningLine?.startRow == 5)
        #expect(newGame.winningLine?.startCol == 0)
        #expect(newGame.winningLine?.endRow == 5)
        #expect(newGame.winningLine?.endCol == 4)
        #expect(newGame.winningLine?.player == Player.black)
    }

}

