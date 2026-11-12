import XCTest
@testable import PayCrossCore

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

    func testAThirdPlaceholderIsLeftAlone() {
        XCTAssertEqual(Template.fill("%@ %@ %@", with: "one", "two"), "one two %@")
    }
}
