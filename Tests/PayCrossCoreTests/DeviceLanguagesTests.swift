import XCTest
@testable import PayCrossCore

/// Where the device rung of the language ladder gets its candidates.
///
/// The rung itself is `LocaleResolution`, asserted next door. This is the one
/// question that file cannot answer, because it takes the list as a parameter:
/// which list, and in whose order.
final class DeviceLanguagesTests: XCTestCase {

    // MARK: - The rule

    func testTheShoppersListIsUsedInTheOrderItIsGiven() {
        XCTAssertEqual(
            DeviceLanguages.ranked(raw: ["fr-FR", "en-US"], fallback: ["en"]),
            ["fr-FR", "en-US"]
        )
    }

    /// The rung is the shopper's ranking, so the sheet speaks the first language
    /// it ships strings for rather than the first one it recognises.
    func testTheSheetTakesTheFirstLanguageItShipsFromThatList() {
        let device = DeviceLanguages.ranked(raw: ["de-DE", "fr-FR", "en-US"], fallback: ["en"])
        XCTAssertEqual(LocaleResolution.resolve(device: device).language, "fr")
    }

    func testAMissingKeyFallsBackToTheFilteredList() {
        XCTAssertEqual(DeviceLanguages.ranked(raw: nil, fallback: ["fr-FR"]), ["fr-FR"])
    }

    /// An empty array is a missing answer, not an answer of "no languages": a
    /// device that reported one would otherwise get English whatever it is set
    /// to.
    func testAnEmptyListFallsBackToo() {
        XCTAssertEqual(DeviceLanguages.ranked(raw: [], fallback: ["fr-FR"]), ["fr-FR"])
    }

    /// The default fallback is the list the SDK used to read on its own, so a
    /// platform that keeps the shopper's languages somewhere else is no worse
    /// off than 0.7.0 was.
    func testTheDefaultFallbackIsThePlatformsOwnList() {
        XCTAssertEqual(DeviceLanguages.ranked(raw: nil), Locale.preferredLanguages)
    }

    // MARK: - The read

    /// The key, spelled once. `AppleLanguages` is the raw list; the filtered one
    /// the host app shapes is what this exists to stop reading.
    func testTheListIsReadFromAppleLanguages() throws {
        let suite = "com.paycross.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(["fr-FR", "en-US"], forKey: "AppleLanguages")
        XCTAssertEqual(DeviceLanguages.preferred(defaults), ["fr-FR", "en-US"])

        defaults.removeObject(forKey: "AppleLanguages")
        XCTAssertEqual(DeviceLanguages.preferred(defaults), Locale.preferredLanguages)
    }
}
