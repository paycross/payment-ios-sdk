import XCTest
@testable import PayCrossCore

final class DeviceLanguagesTests: XCTestCase {

    // MARK: - The rule

    func testTheShoppersListIsUsedInTheOrderItIsGiven() {
        XCTAssertEqual(
            DeviceLanguages.ranked(raw: ["fr-FR", "en-US"], fallback: ["en"]),
            ["fr-FR", "en-US"]
        )
    }

    func testTheSheetTakesTheFirstLanguageItShipsFromThatList() {
        let device = DeviceLanguages.ranked(raw: ["de-DE", "fr-FR", "en-US"], fallback: ["en"])
        XCTAssertEqual(LocaleResolution.resolve(device: device).language, "fr")
    }

    func testAMissingKeyFallsBackToTheFilteredList() {
        XCTAssertEqual(DeviceLanguages.ranked(raw: nil, fallback: ["fr-FR"]), ["fr-FR"])
    }

    func testAnEmptyListFallsBackToo() {
        XCTAssertEqual(DeviceLanguages.ranked(raw: [], fallback: ["fr-FR"]), ["fr-FR"])
    }

    func testTheDefaultFallbackIsThePlatformsOwnList() {
        XCTAssertEqual(DeviceLanguages.ranked(raw: nil), Locale.preferredLanguages)
    }

    // MARK: - The read

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

private final class RecordingDefaults: UserDefaults {
    private(set) var askedFor: [String] = []

    override func stringArray(forKey defaultName: String) -> [String]? {
        askedFor.append(defaultName)
        return ["fr-FR", "en-US"]
    }
}
