import XCTest
@testable import PayCrossCore

/// Both the sheet and Core fill their one placeholder through here rather than
/// through `String(format:)`, so this is where that decision is pinned.
///
/// The templates reaching it can come from a merchant's own strings file. A
/// `%d` typed by mistake into an override would, under `String(format:)`, read
/// an integer vararg that was never passed — undefined behaviour reached from a
/// text file the SDK does not own, on a screen holding a card number.
final class TemplateTests: XCTestCase {

    func testTheFirstPlaceholderIsReplaced() {
        XCTAssertEqual(Template.fill("Remove card, %@", with: "Visa"), "Remove card, Visa")
    }

    func testATemplateCanPutThePlaceholderAnywhere() {
        XCTAssertEqual(
            Template.fill("Champ obligatoire : %@", with: "Code postal"),
            "Champ obligatoire : Code postal"
        )
    }

    func testATemplateWithNoPlaceholderIsUntouched() {
        XCTAssertEqual(Template.fill("Champ obligatoire", with: "Code postal"), "Champ obligatoire")
    }

    /// The whole point. Nothing here reads a vararg; the worst a mistyped
    /// override achieves is a label that still says `%d`.
    func testAnyOtherFormatSpecifierIsLeftAlone() {
        for template in ["%d is required", "%s is required", "%1$@ is required", "100%% sure"] {
            XCTAssertEqual(
                Template.fill(template, with: "Postcode"), template,
                "\(template.debugDescription) must not be treated as a format string"
            )
        }
    }

    func testOnlyTheFirstPlaceholderIsFilled() {
        XCTAssertEqual(Template.fill("%@ and %@", with: "one"), "one and %@")
    }

    func testTheValueIsNotItselfExpanded() {
        XCTAssertEqual(Template.fill("Remove %@", with: "%@"), "Remove %@")
        XCTAssertEqual(Template.fill("Remove %@", with: "%d"), "Remove %d")
    }

    func testAnEmptyValueLeavesTheRestOfTheSentence() {
        XCTAssertEqual(Template.fill("%@ is required", with: ""), " is required")
    }

    // MARK: - Two values

    /// The length message names the field and the limit, and is the only string
    /// the SDK ships that carries two placeholders.
    func testBothPlaceholdersAreFilledInOrder() {
        XCTAssertEqual(
            Template.fill("%@ must be %@ characters or fewer", with: "Notes", "254"),
            "Notes must be 254 characters or fewer"
        )
    }

    func testTheSecondValueIsNotSubstitutedIntoTheFirst() {
        XCTAssertEqual(Template.fill("%@ and %@", with: "%@", "second"), "%@ and second")
    }

    func testATemplateShortOfASecondPlaceholderLosesTheSecondValue() {
        XCTAssertEqual(
            Template.fill("Champ trop long : %@", with: "Remarques", "254"),
            "Champ trop long : Remarques"
        )
    }

    func testATemplateWithNoPlaceholderIsUntouchedByEither() {
        XCTAssertEqual(Template.fill("Champ trop long", with: "Remarques", "254"), "Champ trop long")
    }

    /// A merchant override that grew a third loses the extra rather than
    /// repeating a value into it.
    func testAThirdPlaceholderIsLeftAlone() {
        XCTAssertEqual(Template.fill("%@ %@ %@", with: "one", "two"), "one two %@")
    }
}
