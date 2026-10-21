import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applied to the window rather than with `preferredColorScheme`, so sheets
    /// that are already open (like Profile) switch immediately too.
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

enum StorageKeys {
    static let username = "username"
    static let appearance = "appearance"
    static let selectedSubjectID = "selectedSubjectID"
    static let selectedTab = "selectedTab"
    static let statsRange = "statsRange"
}
