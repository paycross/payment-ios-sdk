#if os(iOS)
import XCTest
@testable import PayCross

/// A `Text("Card Number")` inside a package resolves its key against
/// `Bundle.main` — the merchant's app — so a merchant whose own strings file
/// happens to define one of our labels repaints it. These assert the two halves
/// of the fix: the strings ship with us, and lookups find them there. The last
/// two cover the contract that replaced the accident — a merchant bundle that
/// names one of our keys wins, and a key nobody defines still reads.
final class LocalizedTests: XCTestCase {

    func testEnglishStringsShipInTheSDKBundle() {
        XCTAssertNotNil(sdkBundle.url(forResource: "en", withExtension: "lproj"), "en.lproj missing from the SDK bundle")
    }

    func testKeysResolveFromTheSDKBundleNotTheFallback() {
        // The fallback is deliberately wrong: if the key is missing, this fails.
        XCTAssertEqual(L("paycross_card_number", "MISSING"), "Card Number")
    }

    func testMerchantBundleOverridesTheSDKString() {
        // This test target's own bundle defines paycross_card_number, playing
        // the merchant app that wants its own wording for that one label.
        XCTAssertEqual(L("paycross_card_number", "MISSING", merchant: Bundle.module), "Kartennummer")
    }

    func testUnknownKeyFallsBackToTheEnglishLiteral() {
        XCTAssertEqual(L("paycross_no_such_key", "Fallback"), "Fallback")
    }
}
#endif
