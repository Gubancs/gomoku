//
//  FancyLoaderOverlay.swift
//  gomoku
//
//  Created by Gabor Kokeny on 09/02/2026.
//

import SwiftUI

struct FancyLoaderOverlay: View {
    var tint: Color = .blue
    var title: String? = nil

    @State private var spin = false
    @State private var pulse = false
    @State private var shimmer = false

    var body: some View {
        ZStack {
            // Glass card
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                        .blendMode(.overlay)
                )
                .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 10)

            VStack(spacing: 12) {
                ZStack {
                    // Outer soft glow
                    Circle()
                        .fill(tint.opacity(0.12))
                        .blur(radius: 10)
                        .scaleEffect(pulse ? 1.18 : 0.92)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)

                    // Neon ring
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    tint.opacity(0.0),
                                    tint.opacity(0.95),
                                    tint.opacity(0.15),
                                    tint.opacity(0.95),
                                    tint.opacity(0.0)
                                ],
                                center: .center
                            ),
                            lineWidth: 6
                        )
                        .blur(radius: 0.6)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)

                    // Inner ring
                    Circle()
                        .stroke(tint.opacity(0.18), lineWidth: 1)

                    // Orbiting dots
                    ZStack {
                        ForEach(0..<6, id: \.self) { i in
                            Circle()
                                .fill(tint.opacity(0.9))
                                .frame(width: 6, height: 6)
                                .offset(y: -22)
                                .rotationEffect(.degrees(Double(i) * 60))
                                .opacity(pulse ? 0.95 : 0.35)
                        }
                    }
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.6).repeatForever(autoreverses: false), value: spin)

                    // Center core
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.85),
                                    tint.opacity(0.25),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 1,
                                endRadius: 26
                            )
                        )
                        .frame(width: 22, height: 22)
                        .blur(radius: 0.2)

                    // Accessibility-friendly real progress indicator (hidden visually)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.clear)
                        .scaleEffect(0.01)
                        .accessibilityLabel(Text("Loading"))
                }
                .frame(width: 56, height: 56)

                if let title {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 180, height: title == nil ? 130 : 150)
        .onAppear {
            spin = true
            pulse = true
            shimmer = true
        }
        .onDisappear {
            spin = false
            pulse = false
            shimmer = false
        }
    }
}
