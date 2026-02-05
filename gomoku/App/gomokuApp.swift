//
//  gomokuApp.swift
//  gomoku
//
//  Created by Gabor Kokeny on 03/02/2026.
//

import SwiftUI

@main
struct gomokuApp: App {
    @StateObject private var gameCenter = GameCenterManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameCenter)
        }
    }
}
