import XCTest
@testable import PayCrossCore

final class ThreeDSNavigationTests: XCTestCase {

    // MARK: - Return URL detection

    func testOurHostsAreReturnURLs() {
        XCTAssertTrue(ThreeDSNavigation.isReturnURL("https://checkout.pay-cross.com/done"))
        XCTAssertTrue(ThreeDSNavigation.isReturnURL("https://checkout.test-pay-cross.com/done"))
        XCTAssertTrue(ThreeDSNavigation.isReturnURL("https://pay-cross.com/x"))
        XCTAssertTrue(ThreeDSNavigation.isReturnURL("https://deep.sub.pay-cross.com/x"))
    }

    func testForeignHostsAreNot() {
        XCTAssertFalse(ThreeDSNavigation.isReturnURL("https://acs.issuer-bank.com/challenge"))
        XCTAssertFalse(ThreeDSNavigation.isReturnURL("https://example.com"))
    }

    /// A lookalike domain must not be mistaken for ours. "evilpay-cross.com" ends
    /// with the literal suffix but is a different registrable domain, so matching
    /// requires either equality or a dot-prefixed suffix.
    func testLookalikeDomainsAreRejected() {
        XCTAssertFalse(ThreeDSNavigation.isReturnURL("https://evilpay-cross.com/steal"))
        XCTAssertFalse(ThreeDSNavigation.isReturnURL("https://notpay-cross.com/x"))
        XCTAssertFalse(ThreeDSNavigation.isReturnURL("https://pay-cross.com.evil.net/x"))
    }

    func testMalformedInputIsNotAReturnURL() {
        XCTAssertFalse(ThreeDSNavigation.isReturnURL(""))
        XCTAssertFalse(ThreeDSNavigation.isReturnURL("not a url"))
        XCTAssertFalse(ThreeDSNavigation.isReturnURL("/relative/path"))
    }

    func testHostMatchingIsCaseInsensitive() {
        XCTAssertTrue(ThreeDSNavigation.isReturnURL("https://CHECKOUT.PAY-CROSS.COM/done"))
    }

    // MARK: - Completion detection

    /// The sandbox ACS is hosted on our own domain, so the action URL itself must
    /// not count as completion - otherwise the step completes on its initial load
    /// and the shopper never sees the challenge.
    func testActionURLItselfIsNotCompletion() {
        let action = "https://checkout.test-pay-cross.com/acs/simulate"
        XCTAssertFalse(ThreeDSNavigation.isCompletionURL(action, actionURL: action))
    }

    func testTrailingSlashesAreIgnoredWhenComparing() {
        let action = "https://checkout.test-pay-cross.com/acs/simulate"
        XCTAssertFalse(ThreeDSNavigation.isCompletionURL(action + "/", actionURL: action))
        XCTAssertFalse(ThreeDSNavigation.isCompletionURL(action, actionURL: action + "/"))
        XCTAssertFalse(ThreeDSNavigation.isCompletionURL(action + "///", actionURL: action))
    }

    func testReturnToADifferentPathOnOurHostCompletes() {
        let action = "https://checkout.test-pay-cross.com/acs/simulate"
        XCTAssertTrue(
            ThreeDSNavigation.isCompletionURL(
                "https://checkout.test-pay-cross.com/3ds/return",
                actionURL: action
            )
        )
    }

    func testNavigationOnTheACSHostDoesNotComplete() {
        let action = "https://acs.issuer-bank.com/challenge"
        XCTAssertFalse(
            ThreeDSNavigation.isCompletionURL(
                "https://acs.issuer-bank.com/challenge/step2",
                actionURL: action
            )
        )
    }

    // MARK: - Form encoding

    func testProviderFieldNamesAreNormalised() {
        // EMV 3DS wants "creq"; Nuvei emits "cReq".
        XCTAssertEqual(ThreeDSNavigation.encodeFormBody(["cReq": "abc"]), "creq=abc")
        XCTAssertEqual(ThreeDSNavigation.encodeFormBody(["CReq": "abc"]), "creq=abc")
        XCTAssertEqual(
            ThreeDSNavigation.encodeFormBody(["threeds_method_data": "xyz"]),
            "threeDSMethodData=xyz"
        )
    }

    func testEmptyValuesAreDropped() {
        XCTAssertEqual(
            ThreeDSNavigation.encodeFormBody(["creq": "abc", "empty": ""]),
            "creq=abc"
        )
        XCTAssertEqual(ThreeDSNavigation.encodeFormBody([:]), "")
        XCTAssertEqual(ThreeDSNavigation.encodeFormBody(nil), "")
    }

    func testBodyIsDeterministic() {
        let data = ["z": "1", "a": "2", "m": "3"]
        XCTAssertEqual(ThreeDSNavigation.encodeFormBody(data), "a=2&m=3&z=1")
        // Same input, repeated: Swift dictionary ordering must not leak through.
        for _ in 0..<20 {
            XCTAssertEqual(ThreeDSNavigation.encodeFormBody(data), "a=2&m=3&z=1")
        }
    }

    /// Java's URLEncoder is the reference: space becomes "+", unreserved
    /// characters pass through, everything else is percent-encoded uppercase.
    func testEncodingMatchesJavaURLEncoder() {
        XCTAssertEqual(ThreeDSNavigation.formURLEncode("hello world"), "hello+world")
        XCTAssertEqual(ThreeDSNavigation.formURLEncode("a.b-c*d_e"), "a.b-c*d_e")
        XCTAssertEqual(ThreeDSNavigation.formURLEncode("a+b"), "a%2Bb")
        XCTAssertEqual(ThreeDSNavigation.formURLEncode("a/b?c=d&e"), "a%2Fb%3Fc%3Dd%26e")
        XCTAssertEqual(ThreeDSNavigation.formURLEncode("100%"), "100%25")
    }

    func testUnicodeIsEncodedAsUTF8Bytes() {
        // "é" is C3 A9 in UTF-8.
        XCTAssertEqual(ThreeDSNavigation.formURLEncode("é"), "%C3%A9")
    }

    /// A base64 challenge request is the realistic payload; it must survive intact
    /// apart from its "+" "/" "=" characters being escaped.
    func testBase64ChallengeRequestEncodes() {
        let creq = "eyJ0aHJlZURTU2Vy+dmVyVHJhbnNJRCI6ImFiYy9kZWYifQ=="
        let body = ThreeDSNavigation.encodeFormBody(["cReq": creq])
        XCTAssertTrue(body.hasPrefix("creq="))
        XCTAssertFalse(body.contains("+"), "a literal + would decode as a space")
        XCTAssertTrue(body.contains("%2B"))
        XCTAssertTrue(body.contains("%3D"))
    }
}
