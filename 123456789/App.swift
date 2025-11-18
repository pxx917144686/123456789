//
//  App.swift
//
//  Created by pxx917144686 on 2025/11/17.
//

import SwiftUI
import Combine

@main
struct SBXEscapeApp: App {
    @StateObject private var themeManager = ThemeManager()
    
    var body: some Scene {
        WindowGroup("") {
            ContentView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 600)
    }
}
