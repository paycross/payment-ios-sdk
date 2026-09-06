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
