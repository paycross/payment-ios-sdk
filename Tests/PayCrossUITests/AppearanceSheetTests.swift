#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

/// The two things about the appearance that only exist above Core: the sheet's
/// own window carrying a pinned mode, and the merchant's back-office brand
/// colour arriving on the session rather than in code.
@MainActor
final class AppearanceSheetTests: XCTestCase {

    private static let openSession = #"{"session_id":"sess_1","status":"open"}"#
    private static let brandedSession = ##"""
    {"session_id":"sess_1","status":"open","data":{"branding":{"brand_color":"#1E88E5"}}}
    """##
    private static let serverBlue = PayCrossColor(argb: 0xFF1E_88E5)

    private func makeModel(
        appearance: PayCrossAppearance? = nil,
        json: String = AppearanceSheetTests.openSession
    ) -> PaymentSheetModel {
        PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1", brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"), expiresAt: nil
            ),
            configuration: Configuration(environment: .sandbox, appearance: appearance),
            transport: StubTransport(json: json)
        )
    }

    // MARK: - Pinned mode

    /// A pinned mode reaches the sheet's own window and nothing else. Set at
    /// init because the mode is a code setting, so it is known long before the
    /// session is fetched, and the window resolves its style before then.
    func testTheHostPinsTheSheetToTheThemeMode() {
        let expected: [PayCrossThemeMode: UIUserInterfaceStyle] = [
            .system: .unspecified, .light: .light, .dark: .dark
        ]

        for (mode, style) in expected {
            let host = PaymentHostController(
                model: makeModel(appearance: PayCrossAppearance(themeMode: mode))
            )
            XCTAssertEqual(host.overrideUserInterfaceStyle, style, "themeMode .\(mode.rawValue)")
        }
    }

    /// No appearance at all is not a pinned mode. An integration that never
    /// mentions theming must leave the sheet following the device.
    func testAnUnconfiguredSheetFollowsTheDevice() {
        let host = PaymentHostController(model: makeModel())
        XCTAssertEqual(host.overrideUserInterfaceStyle, .unspecified)
    }

    // MARK: - The server's brand colour

    /// The whole point of the back-office field: an integration that passes no
    /// appearance still comes up in the merchant's own colour.
    func testTheSessionBrandColourReachesTheSheetInBothAppearances() async {
        let model = makeModel(json: Self.brandedSession)
        await model.load()

        XCTAssertEqual(model.appearance.resolved.light.brand, Self.serverBlue)
        XCTAssertEqual(model.appearance.resolved.dark.brand, Self.serverBlue)
    }

    /// Precedence, at the level a merchant actually meets it: their own code
    /// beats what their back office published.
    func testACodeSetBrandBeatsTheSessionBrandColour() async {
        let code = PayCrossColor(argb: 0xFF67_50A4)
        let model = makeModel(appearance: .brand(code), json: Self.brandedSession)
        await model.load()

        XCTAssertEqual(model.appearance.resolved.light.brand, code)
        XCTAssertEqual(model.appearance.resolved.dark.brand, code)
    }

    /// A code appearance that themes something else does not shut the server's
    /// colour out: precedence is per role, not per appearance.
    func testACodeAppearanceWithoutABrandStillTakesTheServerColour() async {
        let model = makeModel(
            appearance: PayCrossAppearance(light: PayCrossColors(surface: .white)),
            json: Self.brandedSession
        )
        await model.load()

        XCTAssertEqual(model.appearance.resolved.light.brand, Self.serverBlue)
        XCTAssertEqual(model.appearance.resolved.light.surface, .white)
    }

    /// Sessions minted before the backend shipped the block carry none, and
    /// there will be live ones. The sheet keeps the platform's own accent.
    func testASessionWithoutBrandingLeavesThePlatformAccent() async {
        let model = makeModel()
        await model.load()

        XCTAssertNil(model.appearance.resolved.light.brand)
        XCTAssertNil(model.appearance.color(\.brand))
    }

    /// The label on the Pay button is derived from whichever brand won, so a
    /// server colour gets the contrast rule the same as a code one.
    func testTheServerColourGetsTheContrastRuleToo() async {
        let model = makeModel(json: ##"""
        {"session_id":"sess_1","status":"open","data":{"branding":{"brand_color":"#FFEB3B"}}}
        """##)
        await model.load()

        XCTAssertEqual(model.appearance.resolved.light.buttonLabel, .black)
    }
}
#endif
