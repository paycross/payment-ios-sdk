import XCTest
@testable import PayCrossCore

/// The rule that decides whether an Apple Pay button is offered at all.
///
/// It is strict-false on purpose and mirrors the Android SDK
/// (`GooglePayRequests.isSessionEligible`) and the checkout page: the wallet is
/// offered unless the session says `false` in so many words. Anything stricter
/// silently drops the wallet from every session snapshotted before the backend
/// shipped the block, and there are live ones.
final class WalletGateTests: XCTestCase {

    private func data(
        applePay: Bool? = nil,
        googlePay: Bool? = nil,
        walletsPresent: Bool = true,
        accountFunding: Bool? = nil
    ) -> SessionData {
        SessionData(
            wallets: walletsPresent
                ? WalletsAvailability(applePay: applePay, googlePay: googlePay)
                : nil,
            accountFunding: accountFunding
        )
    }

    // MARK: - The gate

    func testAnAbsentWalletBlockOffersApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(walletsPresent: false)))
    }

    func testANullMemberOffersApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(applePay: nil)))
    }

    func testAnExplicitTrueOffersApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(applePay: true)))
    }

    func testAnExplicitFalseHidesApplePay() {
        XCTAssertFalse(WalletGate.allowsApplePay(data(applePay: false)))
    }

    /// The two members are independent. A merchant with Google Pay switched
    /// off still gets Apple Pay, and the same session is the Android SDK's
    /// mirror image of this case.
    func testGooglePayFalseDoesNotHideApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(applePay: true, googlePay: false)))
    }

    /// Account funding is not a wallet refusal. Core accepts a wallet payment
    /// on an account-funding session and forwards the transfer block with it,
    /// so the flag marks what the session is, not what it may pay with.
    func testAccountFundingDoesNotHideApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(applePay: true, accountFunding: true)))
    }

    /// The absent-block path, on an account-funding session. Two silences at
    /// once are still two silences: neither one is the explicit false.
    func testAccountFundingWithNoWalletBlockOffersApplePay() {
        XCTAssertTrue(
            WalletGate.allowsApplePay(data(walletsPresent: false, accountFunding: true))
        )
    }

    /// The one refusal that survives account funding. A merchant who switched
    /// Apple Pay off stays switched off whatever else the session carries.
    func testAnExplicitFalseHidesApplePayOnAnAccountFundingSession() {
        XCTAssertFalse(WalletGate.allowsApplePay(data(applePay: false, accountFunding: true)))
    }

    func testAccountFundingFalseOffersApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(applePay: true, accountFunding: false)))
    }

    /// No snapshot at all is not a refusal. `SessionData` is optional all the
    /// way up and a resolution failure must not be spelled as "no wallet".
    func testNoSessionDataOffersApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(nil))
    }

    // MARK: - Eligibility, all eight rows

    private func offers(
        gate: Bool,
        identifier: String?,
        canPay: Bool,
        walletsPresent: Bool = true
    ) -> Bool {
        WalletGate.offersApplePay(
            data: data(applePay: gate, walletsPresent: walletsPresent),
            merchantIdentifier: identifier,
            deviceCanPay: canPay
        )
    }

    func testEligibleOnlyWhenAllThreeHold() {
        XCTAssertTrue(offers(gate: true, identifier: "merchant.pay-cross.com", canPay: true))
    }

    func testNotEligibleWhenTheGateSaysNo() {
        XCTAssertFalse(offers(gate: false, identifier: "merchant.pay-cross.com", canPay: true))
    }

    func testNotEligibleWithoutAConfiguredIdentifier() {
        XCTAssertFalse(offers(gate: true, identifier: nil, canPay: true))
    }

    /// The empty string is what a merchant gets from an unset build constant
    /// or a trimmed text field, and it is not a configured identifier. Left
    /// unhandled it produces a button that authorises and then 400s.
    func testNotEligibleWithAnEmptyIdentifier() {
        XCTAssertFalse(offers(gate: true, identifier: "", canPay: true))
    }

    func testNotEligibleWhenTheDeviceCannotPay() {
        XCTAssertFalse(offers(gate: true, identifier: "merchant.pay-cross.com", canPay: false))
    }

    func testNotEligibleWhenOnlyTheGateHolds() {
        XCTAssertFalse(offers(gate: true, identifier: nil, canPay: false))
    }

    func testNotEligibleWhenOnlyTheIdentifierHolds() {
        XCTAssertFalse(offers(gate: false, identifier: "merchant.pay-cross.com", canPay: false))
    }

    func testNotEligibleWhenNothingHolds() {
        XCTAssertFalse(offers(gate: false, identifier: nil, canPay: false))
    }

    /// Whitespace is not a configured identifier either. It is what a text
    /// field yields when a merchant clears it by hand, and it fails worse than
    /// nil: it is truthy enough to reach the submit body, where it cannot match
    /// the signed session claim and the shopper gets a bare 400.
    func testNotEligibleWithAWhitespaceOnlyIdentifier() {
        XCTAssertFalse(offers(gate: true, identifier: "   ", canPay: true))
        XCTAssertFalse(offers(gate: true, identifier: "\n", canPay: true))
    }

    /// The eight rows above all run against a `wallets` block that exists,
    /// while every session minted before the backend shipped the block takes
    /// the absent path. This composes the two: no block, everything else held.
    func testEligibleWhenTheWalletBlockIsAbsentEntirely() {
        XCTAssertTrue(
            offers(
                gate: true,
                identifier: "merchant.pay-cross.com",
                canPay: true,
                walletsPresent: false
            )
        )
    }
}
