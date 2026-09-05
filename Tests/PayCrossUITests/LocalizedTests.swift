#if os(iOS)
import XCTest
@testable import PayCross

/// A `Text("Card Number")` inside a package resolves its key against
/// `Bundle.main` — the merchant's app — so a merchant whose own strings file
/// happens to define one of our labels repaints it. These assert the two halves
/// of the fix: the strings ship with us, and lookups find them there.
final class LocalizedTests: XCTestCase {

    func testEnglishStringsShipInTheSDKBundle() {
        XCTAssertNotNil(sdkBundle.url(forResource: "en", withExtension: "lproj"), "en.lproj missing from the SDK bundle")
    }

    func testKeysResolveFromTheSDKBundleNotTheFallback() {
        // The fallback is deliberately wrong: if the key is missing, this fails.
        XCTAssertEqual(L("card_number", "MISSING"), "Card Number")
    }
}
#endif
