import XCTest
@testable import PayCrossCore

/// Core cannot look a string up — `L(...)` is iOS-only — so the sheet hands it
/// these. The defaults are what the SDK said before it spoke a second language,
/// which is why every other Core test still asserts English prose.
final class FlowMessagesTests: XCTestCase {

    func testTheDefaultsAreTheEnglishTheSDKAlreadyShipped() {
        let messages = FlowMessages.english
        XCTAssertEqual(messages.paymentFailed, "Payment failed. Please try again.")
        XCTAssertEqual(messages.networkError, "Network error. Please try again.")
        XCTAssertEqual(messages.submissionFailed, "Payment submission failed")
        XCTAssertEqual(messages.fieldRequired, "%@ is required")
        XCTAssertEqual(messages.fieldInvalid, "%@ is invalid")
    }

    func testTheFieldTemplatesTakeTheFieldsLabel() {
        XCTAssertEqual(FlowMessages.english.requiredMessage(for: "Postcode"), "Postcode is required")
        XCTAssertEqual(FlowMessages.english.invalidMessage(for: "Postcode"), "Postcode is invalid")
    }

    /// French puts the label last. The template decides where it goes, so a
    /// translation is not stuck with English word order.
    func testATemplateDecidesWhereTheLabelGoes() {
        let french = FlowMessages(
            fieldRequired: "Champ obligatoire : %@",
            fieldInvalid: "Champ non valide : %@"
        )
        XCTAssertEqual(french.requiredMessage(for: "Code postal"), "Champ obligatoire : Code postal")
        XCTAssertEqual(french.invalidMessage(for: "Code postal"), "Champ non valide : Code postal")
    }

    /// A merchant override of these keys is a string somebody typed, so both of
    /// the ways they can get it wrong have to be survivable rather than fatal.
    func testATemplateWithNoPlaceholderIsUsedAsItStands() {
        let messages = FlowMessages(fieldRequired: "Champ obligatoire")
        XCTAssertEqual(messages.requiredMessage(for: "Code postal"), "Champ obligatoire")
    }

    func testATemplateWithTheWrongPlaceholderIsNotTreatedAsAFormatString() {
        let messages = FlowMessages(fieldRequired: "%d is required")
        XCTAssertEqual(messages.requiredMessage(for: "Postcode"), "%d is required")
    }

    func testOnlyTheFirstPlaceholderIsFilled() {
        let messages = FlowMessages(fieldRequired: "%@ / %@")
        XCTAssertEqual(messages.requiredMessage(for: "Postcode"), "Postcode / %@")
    }
}
