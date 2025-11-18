//
//  ThemeManager.swift
//
//  Created by pxx917144686 on 2025/11/17.
//

import SwiftUI
import Combine

class ThemeManager: ObservableObject {
    enum ThemeMode: String, CaseIterable {
        case system = "系统"
        case light = "浅色"
        case dark = "深色"
    }
    
    @Published var themeMode: ThemeMode = .system {
        didSet {
            updateTheme()
        }
    }
    
    var colorScheme: ColorScheme? {
        switch themeMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
    
    init() {
        if let savedMode = UserDefaults.standard.string(forKey: "themeMode") {
            themeMode = ThemeMode(rawValue: savedMode) ?? .system
        }
    }
    
    private func updateTheme() {
        UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode")
    }
}