import SwiftUI

struct OnlinePresenceBadge: View {
    let count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var label: String {
        if let count {
            return "Online: \(count)"
        }
        return "Online: —"
    }
}

#Preview {
    VStack(spacing: 12) {
        OnlinePresenceBadge(count: 12)
        OnlinePresenceBadge(count: nil)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
