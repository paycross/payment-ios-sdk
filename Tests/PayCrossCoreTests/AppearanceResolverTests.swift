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

    // MARK: - Hex

    func testParsesSixDigitHex() {
        XCTAssertEqual(PayCrossColor(hex: "#1E88E5"), PayCrossColor(argb: 0xFF1E_88E5))
    }

    func testParsesEitherCaseAndTrimsSurroundingSpace() {
        XCTAssertEqual(PayCrossColor(hex: "#1e88e5"), PayCrossColor(argb: 0xFF1E_88E5))
        XCTAssertEqual(PayCrossColor(hex: "  #1E88E5 "), PayCrossColor(argb: 0xFF1E_88E5))
    }

    func testParsesThreeDigitHexByDoublingEachDigit() {
        XCTAssertEqual(PayCrossColor(hex: "#1AF"), PayCrossColor(argb: 0xFF11_AAFF))
    }

    /// The hash is required and eight digits are refused, which is exactly the
    /// grammar the core's own normaliser accepts and the one Android matches.
    /// A brand colour the shopper can partly see through is a mistake rather
    /// than a request, so an alpha channel is not a thing this reads.
    func testRejectsAnythingOutsideTheAgreedGrammar() {
        XCTAssertNil(PayCrossColor(hex: "1e88e5"))
        XCTAssertNil(PayCrossColor(hex: "1AF"))
        XCTAssertNil(PayCrossColor(hex: "#801E88E5"))
        XCTAssertNil(PayCrossColor(hex: ""))
        XCTAssertNil(PayCrossColor(hex: "#"))
        XCTAssertNil(PayCrossColor(hex: "#12345"))
        XCTAssertNil(PayCrossColor(hex: "#GGGGGG"))
        XCTAssertNil(PayCrossColor(hex: "rebeccapurple"))
    }

    // MARK: - Precedence

    private static let code = PayCrossColor(argb: 0xFF11_2233)
    private static let server = "#445566"

    func testCodeBrandBeatsTheServerBrand() {
        let resolved = AppearanceResolver.resolve(
            appearance: .brand(Self.code), serverBrandColor: Self.server
        )
        XCTAssertEqual(resolved.light.brand, Self.code)
        XCTAssertEqual(resolved.dark.brand, Self.code)
    }

    func testServerBrandIsUsedWhenCodeSetsNoneAndAppliesToBothAppearances() {
        let resolved = AppearanceResolver.resolve(appearance: nil, serverBrandColor: Self.server)
        XCTAssertEqual(resolved.light.brand, PayCrossColor(argb: 0xFF44_5566))
        XCTAssertEqual(resolved.dark.brand, PayCrossColor(argb: 0xFF44_5566))
    }

    func testAMalformedServerBrandLeavesThePlatformDefault() {
        let resolved = AppearanceResolver.resolve(appearance: nil, serverBrandColor: "not a colour")
        XCTAssertNil(resolved.light.brand)
    }

    /// The whole point of the nullable roles: nothing set means nothing changes.
    func testAnEmptyAppearanceLeavesEveryRoleToThePlatform() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance())
        for palette in [resolved.light, resolved.dark] {
            XCTAssertNil(palette.brand)
            XCTAssertNil(palette.onBrand)
            XCTAssertNil(palette.surface)
            XCTAssertNil(palette.component)
            XCTAssertNil(palette.componentBorder)
            XCTAssertNil(palette.text)
            XCTAssertNil(palette.textSecondary)
            XCTAssertNil(palette.placeholder)
            XCTAssertNil(palette.icon)
            XCTAssertNil(palette.error)
            XCTAssertNil(palette.buttonBackground)
            XCTAssertNil(palette.buttonLabel)
        }
        XCTAssertNil(resolved.cornerRadius)
        XCTAssertNil(resolved.borderWidth)
        XCTAssertEqual(resolved.themeMode, .system)
        XCTAssertEqual(resolved.sizeScaleFactor, 1)
    }

    func testEachAppearanceKeepsItsOwnPalette() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(surface: .white, text: .black),
            dark: PayCrossColors(surface: .black, text: .white)
        ))
        XCTAssertEqual(resolved.light.surface, .white)
        XCTAssertEqual(resolved.light.text, .black)
        XCTAssertEqual(resolved.dark.surface, .black)
        XCTAssertEqual(resolved.dark.text, .white)
    }

    /// The server brand is one colour for both appearances, because the
    /// branding record holds no light/dark variants. A code palette still wins
    /// per appearance.
    func testACodeBrandInOneAppearanceOnlyLeavesTheOtherOnTheServerBrand() {
        let resolved = AppearanceResolver.resolve(
            appearance: PayCrossAppearance(dark: PayCrossColors(brand: Self.code)),
            serverBrandColor: Self.server
        )
        XCTAssertEqual(resolved.light.brand, PayCrossColor(argb: 0xFF44_5566))
        XCTAssertEqual(resolved.dark.brand, Self.code)
    }

    // MARK: - Derived onBrand

    func testOnBrandIsDerivedFromTheBrandWhenUnset() {
        let light = AppearanceResolver.resolve(appearance: .brand(PayCrossColor(argb: 0xFFFF_EB3B)))
        XCTAssertEqual(light.light.onBrand, .black)

        let dark = AppearanceResolver.resolve(appearance: .brand(PayCrossColor(argb: 0xFF67_50A4)))
        XCTAssertEqual(dark.light.onBrand, .white)
    }

    func testAnExplicitOnBrandIsNotOverridden() {
        let pink = PayCrossColor(argb: 0xFFFF_00FF)
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(brand: PayCrossColor(argb: 0xFFFF_EB3B), onBrand: pink)
        ))
        XCTAssertEqual(resolved.light.onBrand, pink)
    }

    func testNoBrandMeansNoDerivedOnBrand() {
        XCTAssertNil(AppearanceResolver.resolve(appearance: PayCrossAppearance()).light.onBrand)
    }

    // MARK: - Pay button

    func testTheButtonFollowsTheBrandWhenItIsNotOverridden() {
        let brand = PayCrossColor(argb: 0xFF67_50A4)
        let resolved = AppearanceResolver.resolve(appearance: .brand(brand))
        XCTAssertEqual(resolved.light.buttonBackground, brand)
        XCTAssertEqual(resolved.light.buttonLabel, .white)
    }

    /// A merchant who overrode the fill and not the label gets the contrast
    /// rule applied to the fill they chose, not to the brand they did not use.
    func testAnOverriddenFillDerivesItsOwnLabel() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(brand: PayCrossColor(argb: 0xFF67_50A4)),
            primaryButton: PayCrossPrimaryButton(background: PayCrossColor(argb: 0xFFFF_EB3B))
        ))
        XCTAssertEqual(resolved.light.buttonBackground, PayCrossColor(argb: 0xFFFF_EB3B))
        XCTAssertEqual(resolved.light.buttonLabel, .black)
    }

    func testAnOverriddenButtonLabelWins() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            primaryButton: PayCrossPrimaryButton(
                background: PayCrossColor(argb: 0xFFFF_EB3B), textColor: .white
            )
        ))
        XCTAssertEqual(resolved.light.buttonLabel, .white)
    }

    func testTheDisabledPairIsOnlySetWhenTheMerchantSetIt() {
        let untouched = AppearanceResolver.resolve(appearance: .brand(.black))
        XCTAssertNil(untouched.light.buttonDisabledBackground)
        XCTAssertNil(untouched.light.buttonDisabledLabel)

        let overridden = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            primaryButton: PayCrossPrimaryButton(disabledBackground: .white)
        ))
        XCTAssertEqual(overridden.light.buttonDisabledBackground, .white)
        XCTAssertEqual(overridden.light.buttonDisabledLabel, .black)
    }

    // MARK: - Shapes and mode

    func testButtonRadiusFallsBackThroughShapesToTheGeneralRadius() {
        let general = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            shapes: PayCrossShapes(cornerRadius: 16)
        ))
        XCTAssertEqual(general.cornerRadius, 16)
        XCTAssertEqual(general.buttonCornerRadius, 16)

        let button = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            shapes: PayCrossShapes(cornerRadius: 16, buttonCornerRadius: 28)
        ))
        XCTAssertEqual(button.buttonCornerRadius, 28)

        let override = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            shapes: PayCrossShapes(cornerRadius: 16, buttonCornerRadius: 28),
            primaryButton: PayCrossPrimaryButton(cornerRadius: 4)
        ))
        XCTAssertEqual(override.buttonCornerRadius, 4)
    }

    func testThemeModeCrossesUnchanged() {
        for mode in PayCrossThemeMode.allCases {
            let resolved = AppearanceResolver.resolve(
                appearance: PayCrossAppearance(themeMode: mode)
            )
            XCTAssertEqual(resolved.themeMode, mode)
        }
    }

    // MARK: - Size scale

    func testScaleFactorIsClampedToTheDocumentedRange() {
        XCTAssertEqual(AppearanceResolver.clamped(nil), 1)
        XCTAssertEqual(AppearanceResolver.clamped(1.15), 1.15)
        XCTAssertEqual(AppearanceResolver.clamped(0.8), 0.8)
        XCTAssertEqual(AppearanceResolver.clamped(1.3), 1.3)
        XCTAssertEqual(AppearanceResolver.clamped(0.1), 0.8)
        XCTAssertEqual(AppearanceResolver.clamped(4), 1.3)
        XCTAssertEqual(AppearanceResolver.clamped(-2), 0.8)
        XCTAssertEqual(AppearanceResolver.clamped(.nan), 1)
    }

    func testScaleFactorReachesTheResolvedAppearanceClamped() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            typography: PayCrossTypography(sizeScaleFactor: 9)
        ))
        XCTAssertEqual(resolved.sizeScaleFactor, 1.3)
    }

    // MARK: - Contrast warnings

    func testAReadableBrandWarnsAboutNothing() {
        let resolved = AppearanceResolver.resolve(appearance: .brand(PayCrossColor(argb: 0xFF67_50A4)))
        XCTAssertEqual(AppearanceResolver.contrastWarnings(for: resolved), [])
    }

    func testAnUnreadableMerchantPairIsReported() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(
                brand: PayCrossColor(argb: 0xFFFF_EB3B), onBrand: .white
            )
        ))
        let warnings = AppearanceResolver.contrastWarnings(for: resolved)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("light.brand"), warnings[0])
    }

    func testTheSamePairIsNotReportedTwice() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(brand: PayCrossColor(argb: 0xFFFF_EB3B), onBrand: .white),
            dark: PayCrossColors(brand: PayCrossColor(argb: 0xFFFF_EB3B), onBrand: .white)
        ))
        XCTAssertEqual(AppearanceResolver.contrastWarnings(for: resolved).count, 1)
    }

    func testContrastRatioMatchesTheWCAGExtremes() {
        XCTAssertEqual(AppearanceResolver.contrastRatio(.black, .white), 21, accuracy: 0.01)
        XCTAssertEqual(AppearanceResolver.contrastRatio(.white, .white), 1, accuracy: 0.01)
    }
}
