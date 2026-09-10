import Foundation

/// Decides what the sheet actually draws with.
///
/// Platform-free on purpose: everything here is arithmetic over `PayCrossColor`,
/// so the rules are asserted on the Linux job rather than on a simulator.
package enum AppearanceResolver {

    /// Black or white, whichever reads against `background`.
    ///
    /// A port of Android's `onBrandColor`, crossover and all, so one brand
    /// colour gets the same label colour on both platforms. 0.179 is the WCAG
    /// crossover, where black and white contrast equally against a background;
    /// a midpoint of 0.5 would keep white text well past the point where black
    /// reads better.
    package static func onBrand(for background: PayCrossColor) -> PayCrossColor {
        relativeLuminance(of: background) > 0.179 ? .black : .white
    }

    /// How far toward black or white a muted colour travels.
    ///
    /// Enough that a locked box reads as a different box beside an editable one
    /// at a glance, and not so far that a merchant's component colour stops
    /// looking like their component colour.
    package static let mutedFraction = 0.12

    /// A muted reading of a component colour, for a box the shopper may not
    /// type in.
    ///
    /// Moves the colour toward whichever of black and white it is further from,
    /// so a near-white field recedes into a grey and a near-black one lifts
    /// instead of disappearing into the sheet behind it. The direction is
    /// decided off the same luminance crossover `onBrand` uses, which is what
    /// lets one rule serve a light palette and a dark one. Alpha is carried
    /// across untouched: how muted a box is and how far through it you can see
    /// are separate questions.
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

    /// WCAG relative luminance, which is what Compose's `Color.luminance()`
    /// computes on the Android side. Alpha is ignored: what a translucent fill
    /// composites over is not knowable here.
    package static func relativeLuminance(of color: PayCrossColor) -> Double {
        0.2126 * linearised(color.red)
            + 0.7152 * linearised(color.green)
            + 0.0722 * linearised(color.blue)
    }

    /// The sRGB electro-optical transfer function, matching the transfer
    /// parameters Compose's sRGB colour space carries.
    private static func linearised(_ component: UInt8) -> Double {
        let channel = Double(component) / 255
        return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}

extension PayCrossColor {

    /// Parses `#RGB` and `#RRGGBB`, in either case. Anything else is nil.
    ///
    /// Exactly the grammar the core's own colour normaliser accepts, and the
    /// one Android matches, so a colour a merchant can type into the back
    /// office means the same thing on every surface that reads it. The hash is
    /// required and an alpha channel is not accepted: a brand colour the
    /// shopper can partly see through is a mistake, not a request.
    ///
    /// Never throws and never guesses. A value this cannot read costs the
    /// colour, never the sheet.
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

/// One appearance's worth of colours, after every fallback has been applied.
///
/// Still nullable throughout: null means the sheet keeps the system colour it
/// draws today, which is how an appearance that sets one role leaves the rest
/// of the sheet exactly as it was.
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

    /// The Pay button, flattened into the palette so the view layer reads every
    /// colour the same way. Derived from the roles above unless overridden.
    package let buttonBackground: PayCrossColor?
    package let buttonLabel: PayCrossColor?
    package let buttonDisabledBackground: PayCrossColor?
    package let buttonDisabledLabel: PayCrossColor?
}

/// Everything the sheet needs, for both appearances at once.
///
/// Both palettes rather than the one the device is in: the sheet builds dynamic
/// colours from this, so a shopper who changes appearance mid-payment sees the
/// merchant's other palette without the sheet being rebuilt.
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

    /// The range a size scale factor is held to, on both platforms.
    package static let scaleRange: ClosedRange<Double> = 0.8...1.3

    /// Merges what the merchant's code asked for, what the merchant's back
    /// office published, and what the platform already does.
    ///
    /// Pure, and called on every session update, so it reports nothing and logs
    /// nothing. `contrastWarnings(for:)` is the separate question, asked once by
    /// whoever owns the sheet.
    ///
    /// Per role: code wins, then the server's brand colour, then the platform
    /// default. The server publishes one brand colour and it applies to both
    /// appearances, because the branding record holds no light/dark variants.
    package static func resolve(
        appearance: PayCrossAppearance?,
        serverBrandColor: String? = nil
    ) -> ResolvedAppearance {
        let appearance = appearance ?? PayCrossAppearance()
        let serverBrand = serverBrandColor.flatMap(PayCrossColor.init(hex:))

        return ResolvedAppearance(
            light: palette(appearance.light, appearance.primaryButton, serverBrand),
            dark: palette(appearance.dark, appearance.primaryButton, serverBrand),
            themeMode: appearance.themeMode,
            cornerRadius: dimension(appearance.shapes.cornerRadius),
            // Each step of the fallback is checked on its own, so a nonsense
            // button radius falls through to the general one rather than taking
            // both down with it.
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
        // A merchant who overrode the fill and not the label gets the rule
        // applied to the fill they chose, not to the brand they did not use.
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

    /// Out-of-range factors are clamped rather than rejected: the Flutter
    /// wrapper refuses one before it crosses the channel, and a native caller
    /// who passes 4 wants big text, not a broken sheet.
    ///
    /// A factor that is not a number at all is a different thing from one that
    /// is too large, and is read as unset before the clamp gets to it: clamping
    /// a NaN would hand the sheet a NaN back.
    package static func clamped(_ sizeScaleFactor: Double?) -> Double {
        guard let factor = finite(sizeScaleFactor) else { return 1 }
        return min(max(factor, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// A length the merchant asked for, or nil when they cannot have meant it.
    ///
    /// Every number on this API crosses from a Dart double or a JSON body, so
    /// NaN and infinity are reachable without anybody typing them. A NaN that
    /// reaches a corner radius does not draw a strange corner: it takes the
    /// layout pass down with it, on the payment sheet. Negative is not a
    /// radius, a border or a height either. All of them read as unset, which
    /// leaves the value the sheet already drew.
    package static func dimension(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// Colour pairs that fall under the WCAG AA ratio for body text.
    ///
    /// Reported rather than corrected: the merchant chose these colours, and a
    /// sheet that silently ignores what it was told is worse than one that says
    /// so during development. Only pairs the SDK actually decides are checked;
    /// what a merchant's own text colour does against their own surface is
    /// theirs.
    package static func contrastWarnings(for resolved: ResolvedAppearance) -> [String] {
        var seen: Set<UInt64> = []
        var warnings: [String] = []

        for (mode, palette) in [("light", resolved.light), ("dark", resolved.dark)] {
            for (role, pair) in [
                ("brand", (palette.brand, palette.onBrand)),
                ("primaryButton", (palette.buttonBackground, palette.buttonLabel)),
                // Only when the merchant set both. A surface with no text
                // colour is drawn on by the platform's own label colour, which
                // follows the device rather than the surface, and comparing
                // against the colour we would have derived is a tautology: it
                // is chosen to pass.
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

    /// The WCAG contrast ratio between two colours, ignoring alpha.
    package static func contrastRatio(
        _ one: PayCrossColor, _ other: PayCrossColor
    ) -> Double {
        let first = relativeLuminance(of: one)
        let second = relativeLuminance(of: other)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
