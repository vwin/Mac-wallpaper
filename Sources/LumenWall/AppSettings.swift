import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese, english
    var id: String { rawValue }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }
    @Published var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appAppearance") }
    }

    init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .chinese
        appearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appAppearance") ?? "") ?? .system
    }

    func text(_ chinese: String, _ english: String) -> String {
        language == .chinese ? chinese : english
    }
}

extension WallpaperKind {
    func displayName(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.all, .english): "All"
        case (.staticImage, .english): "Static"
        default: rawValue
        }
    }
}

extension WallpaperSource {
    func displayName(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.all, .english): "All sources"
        case (.bingChina, .english): "Bing China (Daily)"
        case (.wallpaper360, .english): "360 Wallpaper (4K)"
        case (.wikimedia, .english): "Wikimedia Commons"
        default: rawValue
        }
    }
}
