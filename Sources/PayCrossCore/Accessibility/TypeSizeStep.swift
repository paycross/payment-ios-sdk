// SwiftUI and UIKit state the text size in two systems, so the ceiling is written once here, not as two literals.
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

    /// The largest step the sheet renders at. Above it the card form does not fit a phone, and the Pay button becomes unreachable.
    package static let ceiling: Self = .accessibility3

    package var clamped: Self { min(self, Self.ceiling) }
}
