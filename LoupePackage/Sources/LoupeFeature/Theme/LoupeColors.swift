import SwiftUI

// MARK: - Brand Color Definitions

extension Color {
    // Accent
    static let loupeAccent = Color(hex: "#f59e0b")
    static let loupeAccentHover = Color(hex: "#d97706")
    static let loupeAccentDim = Color(hex: "#f59e0b").opacity(0.2)

    // Semantic aliases
    static let loupeHighlight = Color.loupeAccent
    static let loupeBadge = Color.loupeAccent
    static let loupeSuccess = Color.loupeAccent
    static let loupeActiveIcon = Color.loupeAccent
    static let loupeDelete = Color.red
}

// MARK: - Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
