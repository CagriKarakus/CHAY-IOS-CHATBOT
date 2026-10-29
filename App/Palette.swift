import SwiftUI
import UIKit

/// Renk paleti: koyu modda Atom One Dark, açık modda Atom One Light.
/// Renkler dinamik; görünüm sistemden veya Ayarlar'daki seçimden gelir.
enum Palette {
    static let background = Color(light: 0xFAFAFA, dark: 0x282C34)
    /// Giriş alanı ve ayar satırları.
    static let surface = Color(light: 0xF0F0F1, dark: 0x21252B)
    /// Kullanıcı mesaj balonu.
    static let elevated = Color(light: 0xE5E5E6, dark: 0x3E4451)
    static let border = Color(light: 0xD4D4D6, dark: 0x3B4048)

    static let text = Color(light: 0x383A42, dark: 0xABB2BF)
    static let textBright = Color(light: 0x1F2024, dark: 0xD7DAE0)
    static let textMuted = Color(light: 0x696C77, dark: 0x7F848E)

    static let blue = Color(light: 0x4078F2, dark: 0x61AFEF)
    static let green = Color(light: 0x50A14F, dark: 0x98C379)
    static let red = Color(light: 0xE45649, dark: 0xE06C75)
    static let yellow = Color(light: 0xC18401, dark: 0xE5C07B)
    static let purple = Color(light: 0xA626A4, dark: 0xC678DD)
    static let cyan = Color(light: 0x0184BC, dark: 0x56B6C2)
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// Açık ve koyu moda göre değişen renk.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Görünüm tercihi.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    static let storageKey = "app.appearance"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: L("System", "Sistem")
        case .light: L("Light", "Açık")
        case .dark: L("Dark", "Koyu")
        }
    }
}
