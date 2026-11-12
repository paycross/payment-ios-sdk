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
        // System colours have no fixed RGB, so the muted fill resolves at draw time from the traits.
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

struct AppearanceStyle: Sendable, Equatable {
    let resolved: ResolvedAppearance
    let typeSize: TypeSizeStep
    private let palette: DynamicPalette
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

    private static func traits(for typeSize: TypeSizeStep) -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: typeSize.clamped.contentSizeCategory)
    }

    func withTypeSize(_ step: TypeSizeStep) -> Self {
        Self(resolved: resolved, typeSize: step, palette: palette)
    }

    static let unstyled = AppearanceStyle(resolved: .unstyled)

    static func == (one: AppearanceStyle, other: AppearanceStyle) -> Bool {
        one.resolved == other.resolved && one.typeSize == other.typeSize
    }

    func uiColor(_ role: KeyPath<DynamicPalette, UIColor?>) -> UIColor? {
        palette[keyPath: role]
    }

    func color(_ role: KeyPath<DynamicPalette, UIColor?>) -> Color? {
        palette[keyPath: role].map(Color.init)
    }

    func foreground(
        _ role: KeyPath<DynamicPalette, UIColor?>,
        default fallback: some ShapeStyle
    ) -> AnyShapeStyle {
        color(role).map { AnyShapeStyle($0) } ?? AnyShapeStyle(fallback)
    }

    var readOnlyComponent: Color { Color(palette.componentMuted) }

    func cornerRadius(or fallback: Double) -> CGFloat {
        CGFloat(resolved.cornerRadius ?? fallback)
    }

    func buttonCornerRadius(or fallback: Double) -> CGFloat {
        CGFloat(resolved.buttonCornerRadius ?? fallback)
    }

    var borderWidth: CGFloat? { resolved.borderWidth.map { CGFloat($0) } }

    func buttonHeight(or fallback: Double) -> CGFloat {
        CGFloat(resolved.buttonHeight ?? fallback)
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch resolved.themeMode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    // A Font built from a UIFont is not scaled again by SwiftUI, so the merchant's factor is applied to the clamped size here.
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

    @ViewBuilder
    func payCrossMutedForeground(_ style: AppearanceStyle, _ isMuted: Bool) -> some View {
        if isMuted {
            foregroundStyle(style.foreground(\.textSecondary, default: .secondary))
        } else {
            self
        }
    }

    @ViewBuilder
    func payCrossForeground(_ color: Color?) -> some View {
        if let color {
            foregroundStyle(color)
        } else {
            self
        }
    }

    // Tint(nil) clears a tint the host app set on the window, so an unset colour keeps self.
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
