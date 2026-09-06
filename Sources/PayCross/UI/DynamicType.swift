#if os(iOS)
import SwiftUI
import UIKit
import PayCrossCore

/// The two ladders iOS states the shopper's text-size setting on.
///
/// SwiftUI's `DynamicTypeSize` is what the root modifier clamps and what a
/// `Font.system` style scales against. UIKit's `UIContentSizeCategory` is what a
/// font resolved through `UIFontMetrics` or
/// `preferredFont(forTextStyle:compatibleWith:)` answers to, which is the path a
/// merchant's size factor takes. Both are mapped from `TypeSizeStep` so the
/// clamp is one value rather than two literals that can drift apart.
extension TypeSizeStep {

    init(_ size: DynamicTypeSize) {
        self = switch size {
        case .xSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        case .xxxLarge: .xxxLarge
        case .accessibility1: .accessibility1
        case .accessibility2: .accessibility2
        case .accessibility3: .accessibility3
        case .accessibility4: .accessibility4
        case .accessibility5: .accessibility5
        @unknown default: .large
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .xSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .xLarge
        case .xxLarge: .xxLarge
        case .xxxLarge: .xxxLarge
        case .accessibility1: .accessibility1
        case .accessibility2: .accessibility2
        case .accessibility3: .accessibility3
        case .accessibility4: .accessibility4
        case .accessibility5: .accessibility5
        }
    }

    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        }
    }
}

extension View {
    /// Bounds the sheet's text size, and tells the appearance what it settled on.
    ///
    /// Two jobs that have to happen in this order. The clamp goes on the outside
    /// so everything below it, including the reader, sees the bounded size; the
    /// reader then hands that size to `AppearanceStyle`, which is where a
    /// merchant's size factor is multiplied in. Without the second half the
    /// factor would multiply against whatever the device reports and the product
    /// would be unbounded — the clamp would hold for the SDK's own semantic
    /// fonts and for nothing a themed sheet draws.
    func payCrossTypeScale(_ style: AppearanceStyle) -> some View {
        TypeScaledAppearance(style: style) { self }
            .dynamicTypeSize(...TypeSizeStep.ceiling.dynamicTypeSize)
    }
}

/// Reads the clamped size and puts it on the appearance the sheet's views read.
private struct TypeScaledAppearance<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let style: AppearanceStyle
    @ViewBuilder let content: Content

    var body: some View {
        content.environment(
            \.payCrossAppearance, style.withTypeSize(TypeSizeStep(dynamicTypeSize))
        )
    }
}
#endif
