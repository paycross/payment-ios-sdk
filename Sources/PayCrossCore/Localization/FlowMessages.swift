import Foundation

// WHY: This module cannot look a string up itself: the merchant-bundle lookup sits behind `#if os(iOS)` and a closure holding a `Bundle` is not `Sendable`, so the sheet resolves these strings before the flow starts.
package struct FlowMessages: Sendable, Equatable {
    package var paymentFailed: String

    package var networkError: String

    package var submissionFailed: String

    package var fieldRequired: String

    package var fieldInvalid: String

    package var fieldTooLong: String

    package init(
        paymentFailed: String = "Payment failed. Please try again.",
        networkError: String = "Network error. Please try again.",
        submissionFailed: String = "Payment submission failed",
        fieldRequired: String = "%@ is required",
        fieldInvalid: String = "%@ is invalid",
        fieldTooLong: String = "%@ must be %@ characters or fewer"
    ) {
        self.paymentFailed = paymentFailed
        self.networkError = networkError
        self.submissionFailed = submissionFailed
        self.fieldRequired = fieldRequired
        self.fieldInvalid = fieldInvalid
        self.fieldTooLong = fieldTooLong
    }

    package static let english = FlowMessages()

    package func requiredMessage(for label: String) -> String {
        Template.fill(fieldRequired, with: label)
    }

    package func invalidMessage(for label: String) -> String {
        Template.fill(fieldInvalid, with: label)
    }

    package func tooLongMessage(for label: String, limit: Int) -> String {
        Template.fill(fieldTooLong, with: label, String(limit))
    }
}
