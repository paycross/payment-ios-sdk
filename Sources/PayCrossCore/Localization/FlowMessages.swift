import Foundation

/// The shopper-facing sentences Core produces, handed in from the sheet.
///
/// Core is deliberately free of UIKit so it builds on Linux, and `L(...)` — the
/// merchant-bundle-first lookup — sits behind `#if os(iOS)` in the `PayCross`
/// target. Core therefore cannot look a string up for itself. A closure would
/// not cross the gap either: `PaymentFlowRunner` is an actor, and a closure
/// holding a `Bundle` is not `Sendable`. A struct of already-resolved `String`s
/// crosses for free, and the sheet fills it in on the main actor before the flow
/// starts.
///
/// The defaults are the English the SDK shipped before it spoke French, so every
/// Core test still asserts a sentence rather than a key and none of them changed.
package struct FlowMessages: Sendable, Equatable {

    /// A decline the shopper may retry.
    package var paymentFailed: String

    /// The request never reached the server, or the reply never came back.
    package var networkError: String

    /// The server refused the submission. Its own sentence wins when it sent one.
    package var submissionFailed: String

    /// Client-side validation of a server-driven field. `%@` is the field's
    /// label, or its name when the server sent no label.
    package var fieldRequired: String

    /// The field was filled in but does not match the server's pattern. `%@` is
    /// the same label.
    package var fieldInvalid: String

    package init(
        paymentFailed: String = "Payment failed. Please try again.",
        networkError: String = "Network error. Please try again.",
        submissionFailed: String = "Payment submission failed",
        fieldRequired: String = "%@ is required",
        fieldInvalid: String = "%@ is invalid"
    ) {
        self.paymentFailed = paymentFailed
        self.networkError = networkError
        self.submissionFailed = submissionFailed
        self.fieldRequired = fieldRequired
        self.fieldInvalid = fieldInvalid
    }

    /// What the SDK says when nobody has localized it.
    package static let english = FlowMessages()

    package func requiredMessage(for label: String) -> String {
        Self.fill(fieldRequired, with: label)
    }

    package func invalidMessage(for label: String) -> String {
        Self.fill(fieldInvalid, with: label)
    }

    /// Substitutes the first `%@`, leaving a template without one alone.
    ///
    /// Not `String(format:)`, for two reasons. `%@` with a Swift `String`
    /// argument is a Darwin facility and this code is asserted on Linux. And
    /// these templates can come from a merchant's own strings file, where a
    /// `%d` someone typed by mistake would send `String(format:)` reading a
    /// vararg that was never passed.
    private static func fill(_ template: String, with value: String) -> String {
        guard let range = template.range(of: "%@") else { return template }
        return template.replacingCharacters(in: range, with: value)
    }
}
