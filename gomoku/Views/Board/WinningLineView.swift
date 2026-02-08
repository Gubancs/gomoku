import SwiftUI

/// Draws a colored line through the winning five-in-a-row stones.
struct WinningLineView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let winningLine: WinningLine
    let cellSize: CGFloat
    let boardSize: Int
    
    var body: some View {
        let lineColor = colorForPlayer(winningLine.player)
        
        GeometryReader { _ in
            Path { path in
                // Calculate the center positions of start and end cells
                let startX = CGFloat(winningLine.startCol) * cellSize + cellSize / 2
                let startY = CGFloat(winningLine.startRow) * cellSize + cellSize / 2
                let endX = CGFloat(winningLine.endCol) * cellSize + cellSize / 2
                let endY = CGFloat(winningLine.endRow) * cellSize + cellSize / 2
                
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: cellSize * 0.15, lineCap: .round))
            .shadow(color: lineColor.opacity(0.5), radius: cellSize * 0.2)
        }
    }
    
    /// Returns the appropriate color for the player's winning line.
    private func colorForPlayer(_ player: Player) -> Color {
        switch player {
        case .black:
            // Black stone - use light color in dark mode, dark in light mode
            return colorScheme == .dark
                ? Color(red: 0.84, green: 0.87, blue: 0.92)
                : Color.black
        case .white:
            // White stone - use red/pink color to ensure visibility
            return Color(red: 0.93, green: 0.26, blue: 0.26)
        }
    }
}
