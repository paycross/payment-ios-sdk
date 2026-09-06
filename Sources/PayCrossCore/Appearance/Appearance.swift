import Foundation

/// A colour, packed as ARGB.
///
/// Deliberately neither `UIColor` nor SwiftUI's `Color`: this type lives in
/// `PayCrossCore`, which imports no UI framework, so the precedence and
/// contrast rules that decide what the sheet draws are tested on Linux on every
/// commit rather than only on a Mac. The packing is the same one the Flutter
/// plugin sends over the channel, so a single number means the same colour on
/// iOS, on Android and in Dart.
public struct PayCrossColor: Sendable, Hashable {

    /// `0xAARRGGBB`.
    public let argb: UInt32

    public init(argb: UInt32) {
        self.argb = argb
    }

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 0xFF) {
        argb = UInt32(alpha) << 24 | UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
    }

    public var alpha: UInt8 { UInt8(truncatingIfNeeded: argb >> 24) }
    public var red: UInt8 { UInt8(truncatingIfNeeded: argb >> 16) }
    public var green: UInt8 { UInt8(truncatingIfNeeded: argb >> 8) }
    public var blue: UInt8 { UInt8(truncatingIfNeeded: argb) }

    public static let black = PayCrossColor(red: 0, green: 0, blue: 0)
    public static let white = PayCrossColor(red: 0xFF, green: 0xFF, blue: 0xFF)
}

/// Which palette the sheet draws with.
///
/// A pinned mode applies to the payment sheet only. The host app's own
/// appearance is never touched.
public enum PayCrossThemeMode: String, Sendable, Hashable, CaseIterable {
    case system
    case light
    case dark
}

/// One palette, used twice: once for light, once for dark.
///
/// Every role is nullable, and null means "keep the platform default" -- the
/// system colour the sheet already draws. An empty palette is therefore a
/// no-op, and a merchant who wants one colour changed sets one role.
public struct PayCrossColors: Sendable, Hashable {

    /// Pay button fill and selection accents.
    public var brand: PayCrossColor?
    /// Text and spinner drawn on `brand`. Null derives it from `brand`.
    public var onBrand: PayCrossColor?
    /// The sheet's own background.
    public var surface: PayCrossColor?
    /// Background of the inputs, the stored-card rows and the field groups.
    public var component: PayCrossColor?
    /// Input and row borders. Only drawn when `PayCrossShapes.borderWidth` is set.
    public var componentBorder: PayCrossColor?
    /// Primary text.
    public var text: PayCrossColor?
    /// Labels, hints and supporting text.
    public var textSecondary: PayCrossColor?
    /// Empty-input placeholder text.
    public var placeholder: PayCrossColor?
    /// The picker's radio and trash symbols.
    public var icon: PayCrossColor?
    /// Error text and the error banner.
    public var error: PayCrossColor?

    public init(
        brand: PayCrossColor? = nil,
        onBrand: PayCrossColor? = nil,
        surface: PayCrossColor? = nil,
        component: PayCrossColor? = nil,
        componentBorder: PayCrossColor? = nil,
        text: PayCrossColor? = nil,
        textSecondary: PayCrossColor? = nil,
        placeholder: PayCrossColor? = nil,
        icon: PayCrossColor? = nil,
        error: PayCrossColor? = nil
    ) {
        self.brand = brand
        self.onBrand = onBrand
        self.surface = surface
        self.component = component
        self.componentBorder = componentBorder
        self.text = text
        self.textSecondary = textSecondary
        self.placeholder = placeholder
        self.icon = icon
        self.error = error
    }
}

/// Corner radii and border thickness, in points.
public struct PayCrossShapes: Sendable, Hashable {

    /// Inputs, stored-card rows, field groups and the error banner. Default 10.
    public var cornerRadius: Double?
    /// The Pay button and the Apple Pay button. Falls back to `cornerRadius`,
    /// then to 12.
    public var buttonCornerRadius: Double?
    /// Input and row border thickness. Null draws no border at all, which is
    /// what the sheet does today.
    public var borderWidth: Double?

    public init(
        cornerRadius: Double? = nil,
        buttonCornerRadius: Double? = nil,
        borderWidth: Double? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.buttonCornerRadius = buttonCornerRadius
        self.borderWidth = borderWidth
    }
}

/// Pay button overrides. Each falls back to the matching palette role.
public struct PayCrossPrimaryButton: Sendable, Hashable {

    /// Falls back to `PayCrossColors.brand`.
    public var background: PayCrossColor?
    /// Falls back to the contrast rule applied to whatever fill won, then to
    /// `PayCrossColors.onBrand`.
    public var textColor: PayCrossColor?
    public var disabledBackground: PayCrossColor?
    public var disabledTextColor: PayCrossColor?
    /// Falls back to `PayCrossShapes.buttonCornerRadius`.
    public var cornerRadius: Double?
    /// Default 50 on iOS.
    public var height: Double?

    public init(
        background: PayCrossColor? = nil,
        textColor: PayCrossColor? = nil,
        disabledBackground: PayCrossColor? = nil,
        disabledTextColor: PayCrossColor? = nil,
        cornerRadius: Double? = nil,
        height: Double? = nil
    ) {
        self.background = background
        self.textColor = textColor
        self.disabledBackground = disabledBackground
        self.disabledTextColor = disabledTextColor
        self.cornerRadius = cornerRadius
        self.height = height
    }
}

/// Type sizing. A font family is deliberately not exposed in this release.
public struct PayCrossTypography: Sendable, Hashable {

    /// Multiplies every font size, on top of Dynamic Type rather than instead
    /// of it. Clamped to 0.8...1.3; null means 1.
    public var sizeScaleFactor: Double?

    public init(sizeScaleFactor: Double? = nil) {
        self.sizeScaleFactor = sizeScaleFactor
    }
}

/// How the payment sheet looks.
///
/// Roles rather than per-element styles, and no layout control of any kind: the
/// sheet's structure, the card-input internals, the wallet buttons' own colours
/// and labels, the 3DS page and the error copy are all fixed by design.
///
/// ```swift
/// PayCrossAPI.configure(
///     environment: .sandbox,
///     appearance: PayCrossAppearance(
///         light: PayCrossColors(brand: PayCrossColor(hex: "#1E88E5")),
///         dark: PayCrossColors(brand: PayCrossColor(hex: "#64B5F6")),
///         shapes: PayCrossShapes(cornerRadius: 16, buttonCornerRadius: 28)
///     )
/// )
/// ```
public struct PayCrossAppearance: Sendable, Hashable {

    public var light: PayCrossColors
    public var dark: PayCrossColors
    public var themeMode: PayCrossThemeMode
    public var shapes: PayCrossShapes
    public var primaryButton: PayCrossPrimaryButton
    public var typography: PayCrossTypography

    public init(
        light: PayCrossColors = PayCrossColors(),
        dark: PayCrossColors = PayCrossColors(),
        themeMode: PayCrossThemeMode = .system,
        shapes: PayCrossShapes = PayCrossShapes(),
        primaryButton: PayCrossPrimaryButton = PayCrossPrimaryButton(),
        typography: PayCrossTypography = PayCrossTypography()
    ) {
        self.light = light
        self.dark = dark
        self.themeMode = themeMode
        self.shapes = shapes
        self.primaryButton = primaryButton
        self.typography = typography
    }

    /// One brand colour in both appearances and platform defaults for the rest.
    public static func brand(_ color: PayCrossColor) -> PayCrossAppearance {
        PayCrossAppearance(
            light: PayCrossColors(brand: color),
            dark: PayCrossColors(brand: color)
        )
    }
}
