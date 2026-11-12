import XCTest
@testable import PayCrossCore

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

    func testGooglePayFalseDoesNotHideApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(applePay: true, googlePay: false)))
    }

    func testAccountFundingDoesNotHideApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(applePay: true, accountFunding: true)))
    }

    func testAccountFundingWithNoWalletBlockOffersApplePay() {
        XCTAssertTrue(
            WalletGate.allowsApplePay(data(walletsPresent: false, accountFunding: true))
        )
    }

    func testAnExplicitFalseHidesApplePayOnAnAccountFundingSession() {
        XCTAssertFalse(WalletGate.allowsApplePay(data(applePay: false, accountFunding: true)))
    }

    func testAccountFundingFalseOffersApplePay() {
        XCTAssertTrue(WalletGate.allowsApplePay(data(applePay: true, accountFunding: false)))
    }

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

    func testNotEligibleWithAWhitespaceOnlyIdentifier() {
        XCTAssertFalse(offers(gate: true, identifier: "   ", canPay: true))
        XCTAssertFalse(offers(gate: true, identifier: "\n", canPay: true))
    }

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
