#if os(iOS)
import SwiftUI
import UIKit
import PayCrossCore

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
    // WHY: The clamp wraps the reader, so the merchant's size factor multiplies the clamped size, not the device's raw one.
    func payCrossTypeScale(_ style: AppearanceStyle) -> some View {
        TypeScaledAppearance(style: style) { self }
            .dynamicTypeSize(...TypeSizeStep.ceiling.dynamicTypeSize)
    }
}

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
