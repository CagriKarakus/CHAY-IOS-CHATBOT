import SwiftUI

/// Atom One Dark renk paleti.
enum Theme {
    static let background = Color(hex: 0x282C34)
    /// Giriş alanı ve ayar satırları.
    static let surface = Color(hex: 0x21252B)
    /// Kullanıcı mesaj balonu.
    static let elevated = Color(hex: 0x3E4451)
    static let border = Color(hex: 0x3B4048)

    static let text = Color(hex: 0xABB2BF)
    static let textBright = Color(hex: 0xD7DAE0)
    static let textMuted = Color(hex: 0x7F848E)

    static let blue = Color(hex: 0x61AFEF)
    static let green = Color(hex: 0x98C379)
    static let red = Color(hex: 0xE06C75)
    static let yellow = Color(hex: 0xE5C07B)
    static let purple = Color(hex: 0xC678DD)
    static let cyan = Color(hex: 0x56B6C2)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
