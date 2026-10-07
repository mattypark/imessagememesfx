import SwiftUI
import UIKit

/// Design tokens. The deck is warm paper by day and near-black at night; the pads keep
/// their colors in both, like the rubber keys on a sampler.
enum Palette {
    static let deck = Color(light: 0xF3EFE6, dark: 0x0E0E10)
    static let ink = Color(light: 0x18181B, dark: 0xF6F3EC)
    static let inkSoft = Color(light: 0x6B6760, dark: 0x9C988F)
    static let rule = Color(light: 0xDDD7CB, dark: 0x26262B)
    /// The send button: inverted from the deck so it reads as the one action on screen.
    static let action = Color(light: 0x18181B, dark: 0xF6F3EC)
    static let onAction = Color(light: 0xF3EFE6, dark: 0x0E0E10)
}

/// A pad's colors: the face, the darker lip under it, and the label ink that reads on it.
struct PadTint: Hashable {
    let face: Color
    let lip: Color
    let label: Color

    static let tomato = PadTint(face: Color(hex: 0xFF5A36), lip: Color(hex: 0xC23A1C), label: Color(hex: 0x1A0E0A))
    static let sun = PadTint(face: Color(hex: 0xFFC21A), lip: Color(hex: 0xC48F00), label: Color(hex: 0x1F1600))
    static let sky = PadTint(face: Color(hex: 0x3FA9FF), lip: Color(hex: 0x1F72C4), label: Color(hex: 0x06182A))
    static let grape = PadTint(face: Color(hex: 0x8B5CFF), lip: Color(hex: 0x5A2FD1), label: Color(hex: 0xFFFFFF))
    static let mint = PadTint(face: Color(hex: 0x2ED69A), lip: Color(hex: 0x15A06F), label: Color(hex: 0x04231A))
    static let bubblegum = PadTint(face: Color(hex: 0xFF6FB5), lip: Color(hex: 0xCC3F86), label: Color(hex: 0x2A0716))
    static let lime = PadTint(face: Color(hex: 0xB6E62E), lip: Color(hex: 0x84AC0F), label: Color(hex: 0x172103))
    static let night = PadTint(face: Color(hex: 0x2A2A33), lip: Color(hex: 0x111116), label: Color(hex: 0xF1EEE6))
}

enum Metrics {
    static let padRadius: CGFloat = 16
    static let padLip: CGFloat = 5
    static let gutter: CGFloat = 16
    static let gap: CGFloat = 10
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
