import XCTest
@testable import PayCrossCore

final class TypeSizeStepTests: XCTestCase {

    func testStepsAreOrderedSmallestFirst() {
        XCTAssertLessThan(TypeSizeStep.xSmall, .large)
        XCTAssertLessThan(TypeSizeStep.large, .xxxLarge)
        XCTAssertLessThan(TypeSizeStep.xxxLarge, .accessibility1)
        XCTAssertLessThan(TypeSizeStep.accessibility1, .accessibility5)
    }

    func testTheCeilingIsTheThirdAccessibilityStep() {
        XCTAssertEqual(TypeSizeStep.ceiling, .accessibility3)
    }

    func testClampingLeavesEveryStepUpToTheCeilingAlone() {
        for step in TypeSizeStep.allCases where step <= .accessibility3 {
            XCTAssertEqual(step.clamped, step)
        }
    }

    func testClampingPullsTheTwoStepsAboveTheCeilingDownToIt() {
        XCTAssertEqual(TypeSizeStep.accessibility4.clamped, .accessibility3)
        XCTAssertEqual(TypeSizeStep.accessibility5.clamped, .accessibility3)
    }

    /// The iOS side maps every case to a `DynamicTypeSize` and a
    /// `UIContentSizeCategory`, both by exhaustive switch. A case added here
    /// without a rung on the other two ladders fails to compile there; this
    /// catches the reverse, a rung quietly dropped from this list.
    func testTheLadderHasTheTwelveStepsIOSOffers() {
        XCTAssertEqual(TypeSizeStep.allCases.count, 12)
    }
}
