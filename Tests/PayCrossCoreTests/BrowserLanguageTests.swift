import XCTest
@testable import PayCrossCore

/// Guards the tag the device actually produces, not just the happy path: with
/// Region set away from the language's home region, `Locale.identifier(.bcp47)`
/// returns "en-US-u-rg-lvzzzz" (17 chars), the backend's `max:10` rejects it,
/// and every payment from that device dies after submit returned 200.
final class BrowserLanguageClampTests: XCTestCase {

    func testDropsExtensionSubtags() {
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("en-US-u-rg-lvzzzz"), "en-US")
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("lv-LV-u-ca-gregory"), "lv-LV")
    }

    /// "zh-Hant-TW" is exactly the backend's 10-character limit and every
    /// subtag is a language fact, so it must survive whole.
    func testLanguageScriptRegionAtTheLimitSurvives() {
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("zh-Hant-TW"), "zh-Hant-TW")
    }

    func testPlainTagsPassThrough() {
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("en"), "en")
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("en-GB"), "en-GB")
    }

    /// A purely private-use tag has no subtags left after the singleton cut;
    /// the backend requires the field non-blank, so it falls back to the raw
    /// prefix rather than an empty string.
    func testPrivateUseTagFallsBackToRawPrefix() {
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("x-private"), "x-private")
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("x-averyprivatetag"), "x-averypri")
    }

    /// No extension singleton to cut and no subtag boundary inside the limit:
    /// the only remaining move is a hard truncation to 10.
    func testOversizedExtensionlessTagHardTruncates() {
        let clamped = BrowserInfo.clampedLanguageTag("abcdefghijkl")
        XCTAssertEqual(clamped, "abcdefghij")
        XCTAssertLessThanOrEqual(clamped.count, 10)
        // A subtag that cannot be appended whole is dropped, not split.
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("en-US-POSIX"), "en-US")
    }

    func testNonEmptyInputNeverClampsToEmpty() {
        for tag in ["en", "en-US-u-rg-lvzzzz", "x-private", "u-ca-gregory", "abcdefghijkl"] {
            XCTAssertFalse(
                BrowserInfo.clampedLanguageTag(tag).isEmpty,
                "\(tag) clamped to empty; a blank language is itself a rejection"
            )
        }
    }

    func testAllClampedOutputsFitTheBackendLimit() {
        for tag in [
            "en", "en-GB", "zh-Hant-TW", "en-US-u-rg-lvzzzz",
            "x-private", "abcdefghijkl", "ja-JP-u-ca-japanese-nu-latn"
        ] {
            XCTAssertLessThanOrEqual(BrowserInfo.clampedLanguageTag(tag).count, 10)
        }
    }
}
