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

/// The role colours, built once as dynamic colours.
///
/// Built here rather than in a view's `body`: a colour constructed in a body is
/// constructed again on every render, and this sheet re-renders on every
/// keystroke the shopper types.
struct DynamicPalette: Sendable {
    let brand: UIColor?
    let onBrand: UIColor?
    let surface: UIColor?
    let component: UIColor?
    /// What a read-only box draws instead, derived rather than named: a merchant
    /// who themed `component` gets a muted box that still belongs to their
    /// palette, and one who themed nothing gets the platform's own fill muted by
    /// the same rule. Never nil, because there is always a fill to mute.
    let componentMuted: UIColor
    let componentBorder: UIColor?
    let text: UIColor?
    let textSecondary: UIColor?
    let placeholder: UIColor?
    let icon: UIColor?
    let error: UIColor?
    let buttonBackground: UIColor?
    let buttonLabel: UIColor?
    let buttonDisabledBackground: UIColor?
    let buttonDisabledLabel: UIColor?

    init(_ resolved: ResolvedAppearance) {
        /// Nil when neither appearance named the role, so the call site keeps
        /// the system colour it already drew. A role named in one appearance
        /// only is used in both: a partial palette is a merchant changing one
        /// colour, not asking for the other appearance to fall back.
        func dynamic(_ role: KeyPath<ResolvedPalette, PayCrossColor?>) -> UIColor? {
            let light = resolved.light[keyPath: role]
            let dark = resolved.dark[keyPath: role]
            guard light != nil || dark != nil else { return nil }

            return UIColor { traits in
                let chosen = traits.userInterfaceStyle == .dark ? dark ?? light : light ?? dark
                return chosen?.uiColor ?? .clear
            }
        }

        brand = dynamic(\.brand)
        onBrand = dynamic(\.onBrand)
        surface = dynamic(\.surface)

        let componentFill = dynamic(\.component)
        component = componentFill
        // Resolved at draw time rather than muted up front, because the colour
        // being muted may be the platform's: `secondarySystemGroupedBackground`
        // is near-white in one appearance and near-black in the other, and only
        // the traits in hand say which. A fill with no RGB reading at all -- a
        // pattern colour -- is left exactly as it is rather than guessed at.
        componentMuted = UIColor { traits in
            let base = (componentFill ?? .secondarySystemGroupedBackground)
                .resolvedColor(with: traits)
            guard let packed = base.payCrossColor else { return base }
            return AppearanceResolver.muted(packed).uiColor
        }

        componentBorder = dynamic(\.componentBorder)
        text = dynamic(\.text)
        textSecondary = dynamic(\.textSecondary)
        placeholder = dynamic(\.placeholder)
        icon = dynamic(\.icon)
        error = dynamic(\.error)
        buttonBackground = dynamic(\.buttonBackground)
        buttonLabel = dynamic(\.buttonLabel)
        buttonDisabledBackground = dynamic(\.buttonDisabledBackground)
        buttonDisabledLabel = dynamic(\.buttonDisabledLabel)
    }
}

/// The resolved appearance, as the sheet's views read it.
///
/// Bridges Core's platform-free palettes to SwiftUI and UIKit. Every colour
/// accessor answers nil when the merchant set nothing for that role, so a call
/// site keeps the system colour it already drew and an unset appearance leaves
/// the sheet byte for byte where it was.
struct AppearanceStyle: Sendable, Equatable {
    let resolved: ResolvedAppearance
    /// The shopper's text-size setting as the sheet resolved it, which is what
    /// the merchant's size factor is multiplied against. `.large` is the
    /// system default and what a style built outside the sheet reads.
    let typeSize: TypeSizeStep
    private let palette: DynamicPalette
    /// Built with the style rather than per call, for the reason the palette
    /// is: `font(_:)` reads it once per font per render and `NumericField`
    /// reads it on every `updateUIView`, and it depends on nothing but
    /// `typeSize`.
    let scaledTraits: UITraitCollection

    init(resolved: ResolvedAppearance, typeSize: TypeSizeStep = .large) {
        self.resolved = resolved
        self.typeSize = typeSize
        palette = DynamicPalette(resolved)
        scaledTraits = Self.traits(for: typeSize)
    }

    private init(
        resolved: ResolvedAppearance, typeSize: TypeSizeStep, palette: DynamicPalette
    ) {
        self.resolved = resolved
        self.typeSize = typeSize
        self.palette = palette
        scaledTraits = Self.traits(for: typeSize)
    }

    /// The traits a UIKit font resolves its size against: the shopper's
    /// setting, held at the ceiling.
    ///
    /// Clamped here as well as at the sheet's root, because a style built
    /// outside the sheet — a screenshot, a preview — has no root modifier over
    /// it, and this is the one place the merchant's factor gets multiplied.
    private static func traits(for typeSize: TypeSizeStep) -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: typeSize.clamped.contentSizeCategory)
    }

    /// The same appearance reading a different text size.
    ///
    /// The palette comes across rather than being rebuilt: it is fourteen
    /// dynamic colours, this is called on every render, and none of them
    /// depends on the type size.
    func withTypeSize(_ step: TypeSizeStep) -> Self {
        Self(resolved: resolved, typeSize: step, palette: palette)
    }

    /// What the sheet looks like when nobody has themed it.
    static let unstyled = AppearanceStyle(resolved: .unstyled)

    /// Two styles are equal when they were resolved from the same values. The
    /// palette is derived from `resolved` and carries no identity of its own,
    /// and comparing freshly built dynamic colours would report every style as
    /// different and re-render the sheet for nothing.
    static func == (one: AppearanceStyle, other: AppearanceStyle) -> Bool {
        one.resolved == other.resolved && one.typeSize == other.typeSize
    }

    func uiColor(_ role: KeyPath<DynamicPalette, UIColor?>) -> UIColor? {
        palette[keyPath: role]
    }

    func color(_ role: KeyPath<DynamicPalette, UIColor?>) -> Color? {
        palette[keyPath: role].map(Color.init)
    }

    /// The same, as a shape style, so a call site can keep a hierarchical
    /// default such as `.secondary` that has no single colour to fall back to.
    func foreground(
        _ role: KeyPath<DynamicPalette, UIColor?>,
        default fallback: some ShapeStyle
    ) -> AnyShapeStyle {
        color(role).map { AnyShapeStyle($0) } ?? AnyShapeStyle(fallback)
    }

    /// The fill a read-only box draws: whatever an editable one would draw,
    /// muted.
    ///
    /// Answers a colour always, unlike the role accessors, so it has an
    /// accessor of its own rather than a keypath into the palette: the roles
    /// are nil when the merchant named nothing and the call site keeps the
    /// system colour, and here the system colour is the thing being muted.
    var readOnlyComponent: Color { Color(palette.componentMuted) }

    /// The radius for inputs, rows, groups and the banner. The fallback is the
    /// literal the call site used before it asked.
    func cornerRadius(or fallback: Double) -> CGFloat {
        CGFloat(resolved.cornerRadius ?? fallback)
    }

    /// The radius for the Pay button and the wallet button, which is the only
    /// property of the wallet button the SDK may change.
    func buttonCornerRadius(or fallback: Double) -> CGFloat {
        CGFloat(resolved.buttonCornerRadius ?? fallback)
    }

    /// Nil draws no border, which is what the sheet does today.
    var borderWidth: CGFloat? { resolved.borderWidth.map { CGFloat($0) } }

    func buttonHeight(or fallback: Double) -> CGFloat {
        CGFloat(resolved.buttonHeight ?? fallback)
    }

    /// The style to pin the sheet's own window to. Unspecified follows the device.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch resolved.themeMode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// A text style, multiplied by the merchant's scale factor.
    ///
    /// At the default factor this is the plain SwiftUI style, which keeps
    /// Dynamic Type entirely as it was — bounded by the sheet's own clamp, like
    /// every other semantic font. A merchant who set a factor gets a font built
    /// from the *clamped* Dynamic Type size times their factor: the
    /// multiplication has to happen in points, and a `Font` carrying a `UIFont`
    /// is the one form SwiftUI will not scale a second time, so resolving
    /// against the device's raw size here would put the product outside the
    /// clamp the shopper can see everywhere else.
    func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let scale = resolved.sizeScaleFactor
        guard scale != 1 else {
            let base = Font.system(style)
            return weight.map { base.weight($0) } ?? base
        }

        let size = UIFont.preferredFont(
            forTextStyle: Self.uiTextStyle(style), compatibleWith: scaledTraits
        ).pointSize
        return Font(UIFont.systemFont(ofSize: size * scale, weight: Self.uiWeight(weight)))
    }

    /// The point size a UIKit field should ask `UIFontMetrics` to scale.
    func scaledPointSize(_ base: Double) -> CGFloat {
        CGFloat(base * resolved.sizeScaleFactor)
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }

    private static func uiWeight(_ weight: Font.Weight?) -> UIFont.Weight {
        switch weight {
        case .some(.ultraLight): .ultraLight
        case .some(.thin): .thin
        case .some(.light): .light
        case .some(.medium): .medium
        case .some(.semibold): .semibold
        case .some(.bold): .bold
        case .some(.heavy): .heavy
        case .some(.black): .black
        default: .regular
        }
    }
}

private struct AppearanceStyleKey: EnvironmentKey {
    static let defaultValue = AppearanceStyle.unstyled
}

extension EnvironmentValues {
    var payCrossAppearance: AppearanceStyle {
        get { self[AppearanceStyleKey.self] }
        set { self[AppearanceStyleKey.self] = newValue }
    }
}

extension View {
    /// Paints the sheet's own chrome: the ground behind the loading spinner and
    /// the navigation bar the form sits under.
    ///
    /// Applied only when a surface resolved, so an unthemed sheet keeps the
    /// system bar it has always had. Without it a merchant who paints the sheet
    /// gets their colour framed by a system-coloured bar, which reads as a
    /// rendering fault rather than as a theme.
    @ViewBuilder
    func payCrossSheetChrome(_ style: AppearanceStyle) -> some View {
        if let surface = style.color(\.surface) {
            background(surface)
                .toolbarBackground(surface, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    /// Paints the sheet's component ground: an input, a stored-card row, a
    /// field group.
    ///
    /// One seam for all three, so the merchant's component colour, corner
    /// radius and border arrive at every box that is meant to have them and at
    /// none of the ones that are not. The border is drawn only when a width was
    /// asked for, because the sheet has never drawn one.
    ///
    /// `muted` is the read-only variant of the same box. It stays on this seam
    /// rather than becoming a second one so that a locked field cannot drift
    /// away from the shape, radius and border of the fields beside it: the only
    /// thing that differs is the fill.
    func payCrossComponentBackground(
        _ style: AppearanceStyle, muted: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius(or: 10))
        let fill = muted
            ? style.readOnlyComponent
            : style.color(\.component) ?? Color(.secondarySystemGroupedBackground)
        return background(fill, in: shape)
        .overlay {
            if let width = style.borderWidth {
                shape.strokeBorder(
                    style.color(\.componentBorder) ?? Color(.separator), lineWidth: width
                )
            }
        }
    }

    /// Drops text to the supporting colour, and only when asked.
    ///
    /// Conditional rather than a ternary at the call site so that the field
    /// this does not apply to keeps exactly the colour it drew before: an
    /// editable field inherits the sheet's own text colour, and naming
    /// `.primary` there would be a different answer dressed as the same one.
    @ViewBuilder
    func payCrossMutedForeground(_ style: AppearanceStyle, _ isMuted: Bool) -> some View {
        if isMuted {
            foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
        } else {
            self
        }
    }

    /// Sets the primary text colour only when the merchant chose one, so an
    /// unthemed sheet is left with the system's own hierarchy untouched.
    @ViewBuilder
    func payCrossForeground(_ color: Color?) -> some View {
        if let color {
            foregroundStyle(color)
        } else {
            self
        }
    }

    /// Tints only when a brand colour resolved.
    ///
    /// `.tint(nil)` is not the same as not tinting: it clears whatever the host
    /// app set on the window, so an unthemed sheet inside a tinted app would
    /// come back to system blue.
    @ViewBuilder
    func payCrossTint(_ color: Color?) -> some View {
        if let color {
            tint(color)
        } else {
            self
        }
    }
}
#endif
