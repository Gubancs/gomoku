import SwiftUI

/// Circular countdown timer with warning and critical states.
struct MoveTimerView: View {
    let timeRemaining: TimeInterval
    let timeLimit: TimeInterval
    let warningThreshold: TimeInterval
    let criticalThreshold: TimeInterval

    private var clampedRemaining: TimeInterval {
        max(0, timeRemaining)
    }

    private var progress: CGFloat {
        guard timeLimit > 0 else { return 0 }
        return CGFloat(clampedRemaining / timeLimit)
    }

    private var isCritical: Bool {
        clampedRemaining <= criticalThreshold
    }

    private var ringColor: Color {
        if clampedRemaining <= criticalThreshold {
            return Color.red
        }
        if clampedRemaining <= warningThreshold {
            return Color.orange
        }
        return Color.blue
    }

    private var timeString: String {
        let totalSeconds = Int(clampedRemaining.rounded(.up))
        return "\(totalSeconds)"
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let lineWidth = max(3, size * 0.08)

            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(isCritical ? 0.5 : 0.2), radius: isCritical ? 6 : 3)

                Text(timeString)
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .foregroundStyle(ringColor)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview {
    VStack(spacing: 24) {
        MoveTimerView(timeRemaining: 48, timeLimit: 50, warningThreshold: 30, criticalThreshold: 10)
            .frame(width: 90, height: 90)
        MoveTimerView(timeRemaining: 24, timeLimit: 50, warningThreshold: 30, criticalThreshold: 10)
            .frame(width: 90, height: 90)
        MoveTimerView(timeRemaining: 8, timeLimit: 50, warningThreshold: 30, criticalThreshold: 10)
            .frame(width: 90, height: 90)
    }
    .padding()
}
