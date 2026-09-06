#if os(iOS)
import SwiftUI
import UIKit
import PayCrossCore

extension PayCrossColor {
    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }

    var color: Color { Color(uiColor) }
}

extension UIColor {
    /// This colour packed as ARGB, or nil when it has no RGB reading at all.
    ///
    /// A pattern colour has none, so a caller asking about contrast falls back
    /// rather than guessing. Components are clamped because an extended-range
    /// colour space reports values outside 0...1.
    var payCrossColor: PayCrossColor? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }

        func byte(_ value: CGFloat) -> UInt8 { UInt8(min(max(value, 0), 1) * 255) }

        return PayCrossColor(
            red: byte(red), green: byte(green), blue: byte(blue), alpha: byte(alpha)
        )
    }
}

extension Color {
    /// Black or white, whichever reads against `background`.
    ///
    /// Dynamic rather than resolved once, because `background` is usually
    /// dynamic itself -- the app's accent colour normally is -- and a colour
    /// that needs white text in one appearance can need black in the other.
    static func onBrand(of background: Color) -> Color {
        Color(UIColor { traits in
            let resolved = UIColor(background).resolvedColor(with: traits)
            guard let packed = resolved.payCrossColor else { return .white }
            return AppearanceResolver.onBrand(for: packed).uiColor
        })
    }
}
#endif
