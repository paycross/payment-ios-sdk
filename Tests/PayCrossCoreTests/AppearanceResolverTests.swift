import XCTest
@testable import PayCrossCore

/// The rules that decide what the sheet draws, asserted where they can run on
/// every commit rather than only on a Mac.
final class AppearanceResolverTests: XCTestCase {

    // MARK: - Packing

    func testARGBRoundTrips() {
        let color = PayCrossColor(argb: 0x8012_34AB)
        XCTAssertEqual(color.alpha, 0x80)
        XCTAssertEqual(color.red, 0x12)
        XCTAssertEqual(color.green, 0x34)
        XCTAssertEqual(color.blue, 0xAB)
        XCTAssertEqual(
            PayCrossColor(red: 0x12, green: 0x34, blue: 0xAB, alpha: 0x80), color
        )
    }

    func testComponentsDefaultToOpaque() {
        XCTAssertEqual(PayCrossColor(red: 1, green: 2, blue: 3).argb, 0xFF01_0203)
    }

    // MARK: - Label contrast

    func testWhiteBackgroundTakesBlackLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: .white), .black)
    }

    func testBlackBackgroundTakesWhiteLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: .black), .white)
    }

    /// The two greys either side of the 0.179 crossover. Anything looser would
    /// pass with the midpoint rule this replaced.
    func testCrossoverSitsBetweenTheseTwoGreys() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0xFF75_7575)), .white)
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0xFF76_7676)), .black)
    }

    /// The case the defect was reported on: a light brand kept white text.
    func testLightBrandTakesBlackLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0xFFFF_EB3B)), .black)
    }

    func testDarkBrandTakesWhiteLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0xFF67_50A4)), .white)
    }

    /// Alpha is not part of the reading, so a translucent brand resolves the
    /// same way its opaque twin does.
    func testAlphaDoesNotChangeTheLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0x1067_50A4)), .white)
    }

    func testLuminanceMatchesTheWCAGReferenceValues() {
        XCTAssertEqual(AppearanceResolver.relativeLuminance(of: .white), 1, accuracy: 0.0001)
        XCTAssertEqual(AppearanceResolver.relativeLuminance(of: .black), 0, accuracy: 0.0001)
        XCTAssertEqual(
            AppearanceResolver.relativeLuminance(of: PayCrossColor(argb: 0xFF80_8080)),
            0.2159, accuracy: 0.0005
        )
    }
}
