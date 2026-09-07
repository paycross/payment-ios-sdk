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

    /// The key, spelled once, and the list handed back untouched.
    ///
    /// **Nothing here writes a preference, and nothing may.** `AppleLanguages`
    /// is a global-domain key: setting it through any `UserDefaults`, a private
    /// suite included, lands in the device's own `.GlobalPreferences` and
    /// relocalizes every later process on that simulator. Measured — a version
    /// of this test that set the key in a suite and did not remove it left an
    /// iPhone simulator in French, and the next run of this suite failed in
    /// `KeyboardDismissalTests`, `LocalizedTests` and `PassKitAdapterTests` with
    /// French strings. Removing the suite's persistent domain does not undo it,
    /// because the value was never in the suite.
    ///
    /// So the defaults are stubbed rather than written to. What is left to pin
    /// is what `preferred` asks for and what it does with the answer.
    func testTheListIsReadFromAppleLanguagesAndKeptInOrder() {
        let defaults = RecordingDefaults()

        XCTAssertEqual(DeviceLanguages.preferred(defaults), ["fr-FR", "en-US"])
        XCTAssertEqual(
            defaults.askedFor, ["AppleLanguages"],
            "the raw list is the one this reads; anything else is the filtered one"
        )
    }

    func testTheKeyIsTheOneTheSystemKeepsTheListUnder() {
        XCTAssertEqual(DeviceLanguages.appleLanguagesKey, "AppleLanguages")
    }
}

/// A `UserDefaults` that answers without owning a preference store, so a test
/// can see which key was read without putting anything on the device.
private final class RecordingDefaults: UserDefaults {
    private(set) var askedFor: [String] = []

    override func stringArray(forKey defaultName: String) -> [String]? {
        askedFor.append(defaultName)
        return ["fr-FR", "en-US"]
    }
}
