import Foundation

package enum AppearanceResolver {

    /// Black or white, whichever reads against `background`.
    ///
    /// The 0.179 crossover is the WCAG point where black and white contrast equally; a midpoint of 0.5 keeps white text on colours where black reads better.
    package static func onBrand(for background: PayCrossColor) -> PayCrossColor {
        relativeLuminance(of: background) > 0.179 ? .black : .white
    }

    package static let mutedFraction = 0.12

    package static func muted(_ color: PayCrossColor) -> PayCrossColor {
        let target: Double = relativeLuminance(of: color) > 0.179 ? 0 : 255

        func mix(_ component: UInt8) -> UInt8 {
            let value = Double(component)
            return UInt8((value + (target - value) * mutedFraction).rounded())
        }

        return PayCrossColor(
            red: mix(color.red),
            green: mix(color.green),
            blue: mix(color.blue),
            alpha: color.alpha
        )
    }

    /// The WCAG relative luminance. Alpha is ignored.
    package static func relativeLuminance(of color: PayCrossColor) -> Double {
        0.2126 * linearised(color.red)
            + 0.7152 * linearised(color.green)
            + 0.0722 * linearised(color.blue)
    }

    private static func linearised(_ component: UInt8) -> Double {
        let channel = Double(component) / 255
        return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}

extension PayCrossColor {

    /// Parses `#RGB` or `#RRGGBB` and returns nil for anything else.
    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }

        let digits = trimmed.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
            return nil
        }

        switch digits.count {
        case 3:
            let red = (value >> 8) & 0xF
            let green = (value >> 4) & 0xF
            let blue = value & 0xF
            self.init(argb: 0xFF00_0000 | red << 20 | red << 16
                | green << 12 | green << 8 | blue << 4 | blue)
        case 6:
            self.init(argb: 0xFF00_0000 | value)
        default:
            return nil
        }
    }
}

/// One appearance's colours after the fallbacks. A nil role keeps the system colour.
package struct ResolvedPalette: Sendable, Hashable {
    package let brand: PayCrossColor?
    package let onBrand: PayCrossColor?
    package let surface: PayCrossColor?
    package let component: PayCrossColor?
    package let componentBorder: PayCrossColor?
    package let text: PayCrossColor?
    package let textSecondary: PayCrossColor?
    package let placeholder: PayCrossColor?
    package let icon: PayCrossColor?
    package let error: PayCrossColor?

    package let buttonBackground: PayCrossColor?
    package let buttonLabel: PayCrossColor?
    package let buttonDisabledBackground: PayCrossColor?
    package let buttonDisabledLabel: PayCrossColor?
}

/// Everything the sheet needs, for both appearances at once.
package struct ResolvedAppearance: Sendable, Hashable {
    package let light: ResolvedPalette
    package let dark: ResolvedPalette
    package let themeMode: PayCrossThemeMode
    package let cornerRadius: Double?
    package let buttonCornerRadius: Double?
    package let borderWidth: Double?
    package let buttonHeight: Double?
    package let sizeScaleFactor: Double

    package static let unstyled = AppearanceResolver.resolve(appearance: nil)
}

extension AppearanceResolver {

    package static let scaleRange: ClosedRange<Double> = 0.8...1.3

    /// Merges the app's appearance, the server's brand colour and the platform defaults, per role.
    package static func resolve(
        appearance: PayCrossAppearance?,
        serverBrandColor: String? = nil
    ) -> ResolvedAppearance {
        let appearance = appearance ?? PayCrossAppearance()
        // The server's brand colour applies to both appearances: the branding record has no light and dark variants.
        let serverBrand = serverBrandColor.flatMap(PayCrossColor.init(hex:))

        return ResolvedAppearance(
            light: palette(appearance.light, appearance.primaryButton, serverBrand),
            dark: palette(appearance.dark, appearance.primaryButton, serverBrand),
            themeMode: appearance.themeMode,
            cornerRadius: dimension(appearance.shapes.cornerRadius),
            // Each fallback is checked on its own, so an invalid value falls through.
            buttonCornerRadius: dimension(appearance.primaryButton.cornerRadius)
                ?? dimension(appearance.shapes.buttonCornerRadius)
                ?? dimension(appearance.shapes.cornerRadius),
            borderWidth: dimension(appearance.shapes.borderWidth),
            buttonHeight: dimension(appearance.primaryButton.height),
            sizeScaleFactor: clamped(appearance.typography.sizeScaleFactor)
        )
    }

    private static func palette(
        _ colors: PayCrossColors,
        _ button: PayCrossPrimaryButton,
        _ serverBrand: PayCrossColor?
    ) -> ResolvedPalette {
        let brand = colors.brand ?? serverBrand
        let onBrand = colors.onBrand ?? brand.map(onBrand(for:))
        let buttonBackground = button.background ?? brand
        let buttonLabel = button.textColor
            ?? button.background.map(onBrand(for:))
            ?? onBrand

        return ResolvedPalette(
            brand: brand,
            onBrand: onBrand,
            surface: colors.surface,
            component: colors.component,
            componentBorder: colors.componentBorder,
            text: colors.text,
            textSecondary: colors.textSecondary,
            placeholder: colors.placeholder,
            icon: colors.icon,
            error: colors.error,
            buttonBackground: buttonBackground,
            buttonLabel: buttonLabel,
            buttonDisabledBackground: button.disabledBackground,
            buttonDisabledLabel: button.disabledTextColor
                ?? button.disabledBackground.map(onBrand(for:))
        )
    }

    /// Clamps the factor to `scaleRange`. A NaN or infinite factor is read as 1.
    package static func clamped(_ sizeScaleFactor: Double?) -> Double {
        guard let factor = finite(sizeScaleFactor) else { return 1 }
        return min(max(factor, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// Returns the length, or nil when it is NaN, infinite or negative.
    package static func dimension(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Returns a warning for each colour pair under the WCAG 4.5:1 ratio for body text. Colours are not changed.
    package static func contrastWarnings(for resolved: ResolvedAppearance) -> [String] {
        var seen: Set<UInt64> = []
        var warnings: [String] = []

        for (mode, palette) in [("light", resolved.light), ("dark", resolved.dark)] {
            for (role, pair) in [
                ("brand", (palette.brand, palette.onBrand)),
                ("primaryButton", (palette.buttonBackground, palette.buttonLabel)),
                // Checked only when both colours are set: a derived text colour is chosen to pass.
                ("surface", (palette.surface, palette.text))
            ] {
                guard let background = pair.0, let foreground = pair.1 else { continue }
                let pairKey = UInt64(background.argb) << 32 | UInt64(foreground.argb)
                guard seen.insert(pairKey).inserted else { continue }

                let ratio = contrastRatio(background, foreground)
                guard ratio < 4.5 else { continue }
                warnings.append(
                    "\(mode).\(role) contrast is \(String(format: "%.2f", ratio)):1, under the 4.5:1 minimum"
                )
            }
        }

        return warnings
    }

    package static func contrastRatio(
        _ one: PayCrossColor, _ other: PayCrossColor
    ) -> Double {
        let first = relativeLuminance(of: one)
        let second = relativeLuminance(of: other)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
