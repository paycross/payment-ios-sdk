import XCTest
@testable import PayCrossCore

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

    func testATemplateDecidesWhereTheLabelGoes() {
        let french = FlowMessages(
            fieldRequired: "Champ obligatoire : %@",
            fieldInvalid: "Champ non valide : %@"
        )
        XCTAssertEqual(french.requiredMessage(for: "Code postal"), "Champ obligatoire : Code postal")
        XCTAssertEqual(french.invalidMessage(for: "Code postal"), "Champ non valide : Code postal")
    }

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
