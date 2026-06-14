import SwiftUI

// Portage de Theme.kt — couleurs de l'app.
enum AppColors {
    static let purple = Color(hex: "#6200EE")
    static let purpleDark = Color(hex: "#3700B3")
    static let teal = Color(hex: "#03DAC6")
    static let recordingRed = Color(hex: "#E53935")
}

// Couleurs prédéfinies pour les labels (PRESET_COLORS de LabelsScreen.kt).
let presetLabelColors = [
    "#6200EE", "#E53935", "#43A047", "#1E88E5",
    "#FB8C00", "#8E24AA", "#00ACC1", "#5D4037"
]

extension Color {
    /// Crée une Color depuis une chaîne hex "#RRGGBB" (ou "#AARRGGBB").
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r, g, b, a: Double
        if s.count == 8 {
            a = Double((rgb & 0xFF000000) >> 24) / 255
            r = Double((rgb & 0x00FF0000) >> 16) / 255
            g = Double((rgb & 0x0000FF00) >> 8) / 255
            b = Double(rgb & 0x000000FF) / 255
        } else {
            a = 1
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
