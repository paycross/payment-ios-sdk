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
