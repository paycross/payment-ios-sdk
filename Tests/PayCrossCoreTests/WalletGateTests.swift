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

    /// Account funding beats an explicit yes: core rejects wallet payments on
    /// account-funding sessions server-side, so offering the button would
    /// spend a Face ID authorisation on a payment that cannot succeed.
    func testAccountFundingHidesApplePayEvenWhenTheBlockSaysTrue() {
        XCTAssertFalse(WalletGate.allowsApplePay(data(applePay: true, accountFunding: true)))
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

    private func offers(gate: Bool, identifier: String?, canPay: Bool) -> Bool {
        WalletGate.offersApplePay(
            data: data(applePay: gate),
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
}
