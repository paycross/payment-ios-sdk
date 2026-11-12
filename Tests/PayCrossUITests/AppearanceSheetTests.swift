#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

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

    func testAnUnconfiguredSheetFollowsTheDevice() {
        let host = PaymentHostController(model: makeModel())
        XCTAssertEqual(host.overrideUserInterfaceStyle, .unspecified)
    }

    // MARK: - The server's brand colour

    func testTheSessionBrandColourReachesTheSheetInBothAppearances() async {
        let model = makeModel(json: Self.brandedSession)
        await model.load()

        XCTAssertEqual(model.appearance.resolved.light.brand, Self.serverBlue)
        XCTAssertEqual(model.appearance.resolved.dark.brand, Self.serverBlue)
    }

    func testACodeSetBrandBeatsTheSessionBrandColour() async {
        let code = PayCrossColor(argb: 0xFF67_50A4)
        let model = makeModel(appearance: .brand(code), json: Self.brandedSession)
        await model.load()

        XCTAssertEqual(model.appearance.resolved.light.brand, code)
        XCTAssertEqual(model.appearance.resolved.dark.brand, code)
    }

    func testACodeAppearanceWithoutABrandStillTakesTheServerColour() async {
        let model = makeModel(
            appearance: PayCrossAppearance(light: PayCrossColors(surface: .white)),
            json: Self.brandedSession
        )
        await model.load()

        XCTAssertEqual(model.appearance.resolved.light.brand, Self.serverBlue)
        XCTAssertEqual(model.appearance.resolved.light.surface, .white)
    }

    func testASessionWithoutBrandingLeavesThePlatformAccent() async {
        let model = makeModel()
        await model.load()

        XCTAssertNil(model.appearance.resolved.light.brand)
        XCTAssertNil(model.appearance.color(\.brand))
    }

    func testTheServerColourGetsTheContrastRuleToo() async {
        let model = makeModel(json: ##"""
        {"session_id":"sess_1","status":"open","data":{"branding":{"brand_color":"#FFEB3B"}}}
        """##)
        await model.load()

        XCTAssertEqual(model.appearance.resolved.light.buttonLabel, .black)
    }
}
#endif
