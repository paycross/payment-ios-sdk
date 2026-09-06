/// One step of the shopper's text-size setting, smallest first.
///
/// Exists so the ceiling the sheet renders at is written **once**. iOS states the
/// same setting in two type systems that do not know about each other — SwiftUI's
/// `DynamicTypeSize`, which the root modifier clamps, and UIKit's
/// `UIContentSizeCategory`, which is what a font resolved through
/// `UIFontMetrics` or `preferredFont(forTextStyle:compatibleWith:)` answers to.
/// A merchant's size factor is applied on the UIKit side, so if the two ceilings
/// were separate literals they could drift and the product would stop being
/// bounded by the clamp the shopper can see.
package enum TypeSizeStep: Int, Sendable, Comparable, CaseIterable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5

    package static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The largest step the sheet renders at.
    ///
    /// Not the largest iOS offers. Above this the card form stops being a form:
    /// the amount, the four labelled fields, the save toggle and a pinned Pay
    /// button do not co-exist on a phone at AX4, and a shopper who cannot reach
    /// the Pay button cannot pay. Three of the five accessibility steps are
    /// honoured in full, which is the floor this SDK documents, and the two above
    /// it are the trade the sheet makes to stay operable.
    package static let ceiling: Self = .accessibility3

    /// This step, or the ceiling when it is above it.
    package var clamped: Self { min(self, Self.ceiling) }
}
