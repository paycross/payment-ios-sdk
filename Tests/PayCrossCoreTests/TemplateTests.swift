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
}
