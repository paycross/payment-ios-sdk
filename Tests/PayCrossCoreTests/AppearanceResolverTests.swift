import XCTest
@testable import PayCrossCore

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

    // MARK: - The muted component fill

    func testALightFillIsMutedDarker() {
        let muted = AppearanceResolver.muted(.white)
        XCTAssertLessThan(muted.red, 255)
        XCTAssertEqual(muted.red, muted.green)
        XCTAssertEqual(muted.green, muted.blue, "a grey must stay grey")
    }

    func testADarkFillIsMutedLighter() {
        XCTAssertGreaterThan(AppearanceResolver.muted(.black).red, 0)
    }

    func testAMutedFillNeverMatchesTheFillItCameFrom() {
        for color in [
            PayCrossColor.white,
            PayCrossColor.black,
            PayCrossColor(red: 0x1E, green: 0x88, blue: 0xE5),
            PayCrossColor(red: 0xF5, green: 0xF5, blue: 0xF0),
            PayCrossColor(red: 0x1C, green: 0x1C, blue: 0x1E)
        ] {
            XCTAssertNotEqual(AppearanceResolver.muted(color), color)
        }
    }

    func testMutingCarriesTheAlphaAcross() {
        let translucent = PayCrossColor(red: 0xFF, green: 0xFF, blue: 0xFF, alpha: 0x80)
        XCTAssertEqual(AppearanceResolver.muted(translucent).alpha, 0x80)
    }

    func testAMutedFillStaysRecognisablyTheSameColour() {
        let brand = PayCrossColor(red: 0x1E, green: 0x88, blue: 0xE5)
        let muted = AppearanceResolver.muted(brand)
        XCTAssertLessThan(muted.blue, brand.blue)
        XCTAssertGreaterThan(muted.blue, muted.red, "the hue was thrown away")
    }

    // MARK: - Label contrast

    func testWhiteBackgroundTakesBlackLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: .white), .black)
    }

    func testBlackBackgroundTakesWhiteLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: .black), .white)
    }

    func testCrossoverSitsBetweenTheseTwoGreys() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0xFF75_7575)), .white)
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0xFF76_7676)), .black)
    }

    func testLightBrandTakesBlackLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0xFFFF_EB3B)), .black)
    }

    func testDarkBrandTakesWhiteLabel() {
        XCTAssertEqual(AppearanceResolver.onBrand(for: PayCrossColor(argb: 0xFF67_50A4)), .white)
    }

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

    func testAnOverriddenFillDerivesItsOwnLabel() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(brand: PayCrossColor(argb: 0xFF67_50A4)),
            primaryButton: PayCrossPrimaryButton(background: PayCrossColor(argb: 0xFFFF_EB3B))
        ))
        XCTAssertEqual(resolved.light.buttonBackground, PayCrossColor(argb: 0xFFFF_EB3B))
        XCTAssertEqual(resolved.light.buttonLabel, .black)
    }

    func testAButtonBackgroundOnItsOwnStillGetsAReadableLabel() {
        let onWhite = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            primaryButton: PayCrossPrimaryButton(background: .white)
        ))
        XCTAssertEqual(onWhite.light.buttonBackground, .white)
        XCTAssertEqual(onWhite.light.buttonLabel, .black)
        XCTAssertEqual(onWhite.dark.buttonLabel, .black)

        let onBlack = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            primaryButton: PayCrossPrimaryButton(background: .black)
        ))
        XCTAssertEqual(onBlack.light.buttonLabel, .white)
    }

    func testAButtonBackgroundBeatsAnExplicitOnBrandForItsOwnLabel() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(brand: .black, onBrand: .white),
            primaryButton: PayCrossPrimaryButton(background: .white)
        ))
        XCTAssertEqual(resolved.light.onBrand, .white)
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
    }

    func testAScaleFactorThatIsNotANumberReadsAsUnset() {
        XCTAssertEqual(AppearanceResolver.clamped(.nan), 1)
        XCTAssertEqual(AppearanceResolver.clamped(.infinity), 1)
        XCTAssertEqual(AppearanceResolver.clamped(-.infinity), 1)
        XCTAssertEqual(AppearanceResolver.clamped(.signalingNaN), 1)
    }

    // MARK: - Dimensions

    func testDimensionsPassThroughWhenTheyAreLengths() {
        XCTAssertEqual(AppearanceResolver.dimension(16), 16)
        XCTAssertEqual(AppearanceResolver.dimension(0), 0)
    }

    func testDimensionsThatCannotBeLengthsReadAsUnset() {
        XCTAssertNil(AppearanceResolver.dimension(nil))
        XCTAssertNil(AppearanceResolver.dimension(.nan))
        XCTAssertNil(AppearanceResolver.dimension(.infinity))
        XCTAssertNil(AppearanceResolver.dimension(-.infinity))
        XCTAssertNil(AppearanceResolver.dimension(-1))
    }

    func testEveryShapeValueIsValidated() {
        for bad in [Double.nan, .infinity, -.infinity, -1] {
            let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
                shapes: PayCrossShapes(
                    cornerRadius: bad, buttonCornerRadius: bad, borderWidth: bad
                ),
                primaryButton: PayCrossPrimaryButton(cornerRadius: bad, height: bad)
            ))

            XCTAssertNil(resolved.cornerRadius, "cornerRadius \(bad)")
            XCTAssertNil(resolved.buttonCornerRadius, "buttonCornerRadius \(bad)")
            XCTAssertNil(resolved.borderWidth, "borderWidth \(bad)")
            XCTAssertNil(resolved.buttonHeight, "buttonHeight \(bad)")
        }
    }

    func testANonsenseButtonRadiusFallsThroughToTheGeneralOne() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            shapes: PayCrossShapes(cornerRadius: 16),
            primaryButton: PayCrossPrimaryButton(cornerRadius: .nan)
        ))
        XCTAssertEqual(resolved.buttonCornerRadius, 16)
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

    func testAnUnreadableSurfaceAndTextPairIsReported() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(
                surface: .white, text: PayCrossColor(argb: 0xFFEE_EEEE)
            )
        ))
        let warnings = AppearanceResolver.contrastWarnings(for: resolved)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("light.surface"), warnings[0])
    }

    func testAReadableSurfaceAndTextPairWarnsAboutNothing() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(surface: .white, text: .black)
        ))
        XCTAssertEqual(AppearanceResolver.contrastWarnings(for: resolved), [])
    }

    func testASurfaceWithNoTextColourIsNotReported() {
        let resolved = AppearanceResolver.resolve(appearance: PayCrossAppearance(
            light: PayCrossColors(surface: .white)
        ))
        XCTAssertEqual(AppearanceResolver.contrastWarnings(for: resolved), [])
    }

    func testContrastRatioMatchesTheWCAGExtremes() {
        XCTAssertEqual(AppearanceResolver.contrastRatio(.black, .white), 21, accuracy: 0.01)
        XCTAssertEqual(AppearanceResolver.contrastRatio(.white, .white), 1, accuracy: 0.01)
    }
}
