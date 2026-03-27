import SwiftUI

public enum ColorTheme: String, CaseIterable, Identifiable {
    case green, blue, purple, orange, teal

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .green:  return .green
        case .blue:   return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .teal:   return .teal
        }
    }

    public var displayName: String { rawValue.capitalized }

    /// Current user-selected theme from UserDefaults.
    public static var current: ColorTheme {
        let name = UserDefaults.standard.string(forKey: "accentColorName") ?? "green"
        return ColorTheme(rawValue: name) ?? .green
    }
}
