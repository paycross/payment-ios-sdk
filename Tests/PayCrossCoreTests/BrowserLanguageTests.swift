import XCTest
@testable import PayCrossCore

final class BrowserLanguageClampTests: XCTestCase {
    func testDropsExtensionSubtags() {
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("en-US-u-rg-lvzzzz"), "en-US")
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("lv-LV-u-ca-gregory"), "lv-LV")
    }

    func testLanguageScriptRegionAtTheLimitSurvives() {
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("zh-Hant-TW"), "zh-Hant-TW")
    }

    func testPlainTagsPassThrough() {
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("en"), "en")
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("en-GB"), "en-GB")
    }

    func testPrivateUseTagFallsBackToRawPrefix() {
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("x-private"), "x-private")
        XCTAssertEqual(BrowserInfo.clampedLanguageTag("x-averyprivatetag"), "x-averypri")
    }

    func testOversizedExtensionlessTagHardTruncates() {
        let clamped = BrowserInfo.clampedLanguageTag("abcdefghijkl")
        XCTAssertEqual(clamped, "abcdefghij")
        XCTAssertLessThanOrEqual(clamped.count, 10)
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
