import XCTest
@testable import PayCrossCore

final class FieldGroupLogicTests: XCTestCase {

    private func field(
        _ name: String,
        required: Bool? = nil,
        readonly: Bool? = nil,
        value: String? = nil,
        label: String? = nil,
        labels: [String: String]? = nil,
        condition: FieldCondition? = nil,
        validation: FieldValidation? = nil
    ) -> FieldDefinition {
        FieldDefinition(
            name: name, label: label, labels: labels, required: required,
            readonly: readonly, value: value, condition: condition, validation: validation
        )
    }

    // MARK: - Condition evaluation

    func testUnconditionalFieldsUseTheirOwnFlags() {
        let state = FieldGroupLogic.fieldState(
            for: field("postcode", required: true, readonly: true),
            groupValues: [:]
        )
        XCTAssertEqual(state, FieldState(isVisible: true, isRequired: true, isReadOnly: true))
    }

    func testConditionMetAppliesDisplay() {
        let state = FieldGroupLogic.fieldState(
            for: field("state", condition: FieldCondition(
                whenField: "country", whenIn: ["US", "CA"], display: "required", default: "hidden"
            )),
            groupValues: ["country": "US"]
        )
        XCTAssertEqual(state, FieldState(isVisible: true, isRequired: true, isReadOnly: false))
    }

    func testConditionNotMetFallsBackToDefault() {
        let state = FieldGroupLogic.fieldState(
            for: field("state", condition: FieldCondition(
                whenField: "country", whenIn: ["US"], display: "required", default: "hidden"
            )),
            groupValues: ["country": "GB"]
        )
        XCTAssertFalse(state.isVisible)
        XCTAssertFalse(state.isRequired, "a hidden field is never required")
    }

    /// A missing control value is "" and simply fails the `in` test; it must not
    /// crash or accidentally satisfy the condition.
    func testAbsentControlValueIsTreatedAsEmpty() {
        let state = FieldGroupLogic.fieldState(
            for: field("state", condition: FieldCondition(
                whenField: "country", whenIn: ["US"], display: "required", default: "hidden"
            )),
            groupValues: [:]
        )
        XCTAssertFalse(state.isVisible)
    }

    /// With no `default`, an unmet condition leaves the field visible and
    /// optional — nil is not "hidden".
    func testNilDefaultLeavesTheFieldVisible() {
        let state = FieldGroupLogic.fieldState(
            for: field("state", condition: FieldCondition(
                whenField: "country", whenIn: ["US"], display: "required", default: nil
            )),
            groupValues: ["country": "GB"]
        )
        XCTAssertTrue(state.isVisible)
        XCTAssertFalse(state.isRequired)
    }

    func testReadonlyDisplay() {
        let state = FieldGroupLogic.fieldState(
            for: field("ref", condition: FieldCondition(
                whenField: "kind", whenIn: ["fixed"], display: "readonly"
            )),
            groupValues: ["kind": "fixed"]
        )
        XCTAssertTrue(state.isReadOnly)
        XCTAssertTrue(state.isVisible)
    }

    // MARK: - Initial values

    func testInitialValuesTakeServerDefaultsAndDropEmptyGroups() {
        let groups = [
            FieldGroup(key: "billing", fields: [
                field("country", value: "GB"),
                field("postcode", value: ""),
                field("city")
            ]),
            FieldGroup(key: "empty", fields: [field("nothing")])
        ]
        let values = FieldGroupLogic.initialValues(groups)

        XCTAssertEqual(values, ["billing": ["country": "GB"]])
        XCTAssertNil(values["empty"], "a group with no prefilled values is not carried")
    }

    // MARK: - Validation

    func testRequiredVisibleFieldMustHaveAValue() {
        let groups = [FieldGroup(key: "billing", fields: [
            field("postcode", required: true, label: "Postcode")
        ])]
        let errors = FieldGroupLogic.validate(groups: groups, values: [:])

        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].fieldName, "postcode")
        XCTAssertEqual(errors[0].message, "Postcode is required")
    }

    func testWhitespaceOnlyDoesNotSatisfyRequired() {
        let groups = [FieldGroup(key: "b", fields: [field("postcode", required: true)])]
        let errors = FieldGroupLogic.validate(
            groups: groups, values: ["b": ["postcode": "   "]]
        )
        XCTAssertEqual(errors.count, 1)
    }

    /// The whole point of conditions: a hidden field must never block submission.
    func testHiddenFieldsAreNotValidated() {
        let groups = [FieldGroup(key: "billing", fields: [
            field("state", required: true, condition: FieldCondition(
                whenField: "country", whenIn: ["US"], display: "required", default: "hidden"
            ))
        ])]
        let errors = FieldGroupLogic.validate(
            groups: groups, values: ["billing": ["country": "GB"]]
        )
        XCTAssertTrue(errors.isEmpty, "a hidden field cannot block checkout")
    }

    func testPatternIsCheckedOnlyWhenAValueIsPresent() {
        let validation = FieldValidation(pattern: "^[0-9]+$")
        let groups = [FieldGroup(key: "b", fields: [field("num", validation: validation)])]

        XCTAssertTrue(
            FieldGroupLogic.validate(groups: groups, values: ["b": [:]]).isEmpty,
            "an optional empty field is not a pattern failure"
        )
        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: ["b": ["num": "abc"]]).count, 1
        )
        XCTAssertTrue(
            FieldGroupLogic.validate(groups: groups, values: ["b": ["num": "123"]]).isEmpty
        )
    }

    func testServerMessagesOverrideTheDefaults() {
        let validation = FieldValidation(
            pattern: "^[0-9]+$",
            messages: ["required": "We need this", "pattern": "Digits only please"]
        )
        let groups = [FieldGroup(key: "b", fields: [
            field("num", required: true, validation: validation)
        ])]

        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:]).first?.message,
            "We need this"
        )
        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: ["b": ["num": "x"]]).first?.message,
            "Digits only please"
        )
    }

    func testMessageFallsBackToNameWhenThereIsNoLabel() {
        let groups = [FieldGroup(key: "b", fields: [field("tax_id", required: true)])]
        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:]).first?.message,
            "tax_id is required"
        )
    }

    func testTheFallbackMessagesAreTheOnesTheSheetResolved() {
        let groups = [FieldGroup(key: "b", fields: [
            field("postcode", required: true, label: "Code postal")
        ])]
        let french = FlowMessages(fieldRequired: "Champ obligatoire : %@")
        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:], messages: french).first?.message,
            "Champ obligatoire : Code postal"
        )
    }

    /// The server writes these for one field in one merchant's own words, so they
    /// are not translatable and they still win over anything the sheet resolved.
    func testAServerSuppliedMessageStillBeatsTheResolvedFallback() {
        let groups = [FieldGroup(key: "b", fields: [
            field(
                "postcode", required: true, label: "Code postal",
                validation: FieldValidation(messages: ["required": "We need this"])
            )
        ])]
        let french = FlowMessages(fieldRequired: "Champ obligatoire : %@")
        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:], messages: french).first?.message,
            "We need this"
        )
    }

    // MARK: - Validation in the sheet's language

    /// The server sends its own sentences in every language it renders, so the
    /// message that beats the resolved fallback is now the one for the language
    /// the sheet resolved rather than the single string it used to send.
    func testAServerMessageComesOutInTheSheetsLanguage() {
        let validation = FieldValidation(
            pattern: "^[0-9]+$",
            messages: ["required": "We need this", "pattern": "Digits only please"],
            messagesI18n: [
                "en": ["required": "We need this", "pattern": "Digits only please"],
                "fr": ["required": "Nous en avons besoin", "pattern": "Chiffres uniquement"]
            ]
        )
        let groups = [FieldGroup(key: "b", fields: [
            field("num", required: true, validation: validation)
        ])]

        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:], language: "fr").first?.message,
            "Nous en avons besoin"
        )
        XCTAssertEqual(
            FieldGroupLogic.validate(
                groups: groups, values: ["b": ["num": "x"]], language: "fr"
            ).first?.message,
            "Chiffres uniquement"
        )
        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:], language: "en").first?.message,
            "We need this"
        )
    }

    /// A session minted before the maps existed, and a language the maps do not
    /// name, both read the singular value.
    func testAMessageWithNoMapForTheLanguageFallsBackToTheSingularOne() {
        let groups = [FieldGroup(key: "b", fields: [
            field(
                "num", required: true,
                validation: FieldValidation(messages: ["required": "We need this"])
            )
        ])]
        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:], language: "fr").first?.message,
            "We need this"
        )
    }

    /// The same per-rule fallback as the reader has, through `validate`: the
    /// French shopper reads the French `required` and the pattern sentence the
    /// server wrote once, not our own wording for the second one.
    func testARuleMissingFromItsLanguagesMapStillComesFromTheServer() {
        let validation = FieldValidation(
            pattern: "^[0-9]+$",
            messages: ["required": "We need this", "pattern": "Digits only please"],
            messagesI18n: ["fr": ["required": "Nous en avons besoin"]]
        )
        let groups = [FieldGroup(key: "b", fields: [
            field("num", required: true, validation: validation)
        ])]

        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:], language: "fr").first?.message,
            "Nous en avons besoin"
        )
        XCTAssertEqual(
            FieldGroupLogic.validate(
                groups: groups, values: ["b": ["num": "x"]], language: "fr"
            ).first?.message,
            "Digits only please"
        )
    }

    /// The fallback sentence names the field, so the name it uses has to be the
    /// label the shopper is actually looking at.
    func testTheFallbackSentenceNamesTheFieldInTheSheetsLanguage() {
        let groups = [FieldGroup(key: "b", fields: [
            field(
                "postcode", required: true, label: "Postcode",
                labels: ["en": "Postcode", "fr": "Code postal"]
            )
        ])]
        let french = FlowMessages(fieldRequired: "Champ obligatoire : %@")
        XCTAssertEqual(
            FieldGroupLogic.validate(
                groups: groups, values: [:], messages: french, language: "fr"
            ).first?.message,
            "Champ obligatoire : Code postal"
        )
        XCTAssertEqual(
            FieldGroupLogic.validate(groups: groups, values: [:], language: "en").first?.message,
            "Postcode is required"
        )
    }

    /// Kotlin uses containsMatchIn, i.e. a substring match. Treating an unanchored
    /// server pattern as a whole-string match would reject values the checkout
    /// page accepts.
    func testPatternMatchingIsSubstringNotWholeString() {
        XCTAssertTrue(FieldGroupLogic.matches("AB12CD", pattern: "[0-9]+"))
        XCTAssertTrue(FieldGroupLogic.matches("abc", pattern: "b"))
        XCTAssertFalse(FieldGroupLogic.matches("abc", pattern: "^[0-9]+$"))
    }

    /// A broken server pattern must not make checkout impossible; the server
    /// validates too.
    func testMalformedPatternPassesRatherThanBlocking() {
        XCTAssertTrue(FieldGroupLogic.matches("anything", pattern: "([unclosed"))
    }

    func testErrorsAreOrderedByGroupThenField() {
        let groups = [
            FieldGroup(key: "a", fields: [field("a1", required: true), field("a2", required: true)]),
            FieldGroup(key: "b", fields: [field("b1", required: true)])
        ]
        let errors = FieldGroupLogic.validate(groups: groups, values: [:])
        XCTAssertEqual(errors.map(\.fieldName), ["a1", "a2", "b1"])
    }

    // MARK: - Submission

    func testOnlyVisibleNonBlankValuesAreSubmitted() {
        let groups = [FieldGroup(key: "billing", fields: [
            field("country"),
            field("blank"),
            field("state", condition: FieldCondition(
                whenField: "country", whenIn: ["US"], display: "required", default: "hidden"
            ))
        ])]
        let values = ["billing": ["country": "GB", "blank": "  ", "state": "NY"]]

        XCTAssertEqual(
            FieldGroupLogic.submissionValues(groups: groups, values: values),
            ["billing": ["country": "GB"]],
            "a hidden field's stale value must not reach the wire"
        )
    }

    func testVisibleConditionalValuesAreSubmitted() {
        let groups = [FieldGroup(key: "billing", fields: [
            field("country"),
            field("state", condition: FieldCondition(
                whenField: "country", whenIn: ["US"], display: "required", default: "hidden"
            ))
        ])]
        let values = ["billing": ["country": "US", "state": "NY"]]

        XCTAssertEqual(
            FieldGroupLogic.submissionValues(groups: groups, values: values),
            ["billing": ["country": "US", "state": "NY"]]
        )
    }

    func testEmptyGroupsAreDroppedEntirely() {
        let groups = [FieldGroup(key: "billing", fields: [field("x")])]
        XCTAssertTrue(
            FieldGroupLogic.submissionValues(groups: groups, values: ["billing": ["x": ""]]).isEmpty,
            "an empty group must not be sent as {}"
        )
    }

    func testUnknownKeysInValuesAreIgnored() {
        let groups = [FieldGroup(key: "billing", fields: [field("country")])]
        let values = ["billing": ["country": "GB", "not_a_field": "x"], "ghost": ["y": "z"]]

        XCTAssertEqual(
            FieldGroupLogic.submissionValues(groups: groups, values: values),
            ["billing": ["country": "GB"]],
            "only fields the server declared may be submitted"
        )
    }

    // MARK: - The name an assistive technology speaks

    /// The sheet's own copy, as it reaches Core already looked up.
    private let requiredEN = "%@, required"
    private let requiredFR = "%@, obligatoire"

    private let optional = FieldState(isVisible: true, isRequired: false, isReadOnly: false)
    private let required = FieldState(isVisible: true, isRequired: true, isReadOnly: false)

    private let line1 = FieldDefinition(
        name: "line1",
        label: "Address line 1",
        labels: ["en": "Address line 1", "fr": "Ligne d'adresse 1"],
        placeholder: "123 Main St",
        placeholders: ["en": "123 Main St", "fr": "123 Main St"]
    )

    /// The bug this replaces: the spoken name was the placeholder, so the
    /// billing line announced the example address instead of the field.
    func testAnOptionalFieldIsSpokenAsItsLabel() {
        XCTAssertEqual(
            FieldGroupLogic.accessibleName(
                for: line1, state: optional, requiredTemplate: requiredEN, language: "en"
            ),
            "Address line 1"
        )
    }

    func testARequiredFieldIsSpokenWithTheWordRatherThanTheStar() {
        let spoken = FieldGroupLogic.accessibleName(
            for: line1, state: required, requiredTemplate: requiredEN, language: "en"
        )
        XCTAssertEqual(spoken, "Address line 1, required")
        XCTAssertFalse(spoken.contains("*"), "the visual marker must not reach the spoken name")
    }

    func testTheSpokenNameFollowsTheSheetsLanguage() {
        XCTAssertEqual(
            FieldGroupLogic.accessibleName(
                for: line1, state: required, requiredTemplate: requiredFR, language: "fr"
            ),
            "Ligne d'adresse 1, obligatoire"
        )
    }

    /// A session minted before the per-language maps existed still has a name.
    func testASessionWithoutTheMapsIsSpokenAsItsSingularLabel() {
        let singular = FieldDefinition(name: "line1", label: "Address line 1")
        XCTAssertEqual(
            FieldGroupLogic.accessibleName(
                for: singular, state: optional, requiredTemplate: requiredFR, language: "fr"
            ),
            "Address line 1"
        )
    }

    /// The last resort. A field the merchant labelled nothing announced nothing
    /// at all before, because its placeholder was null too.
    func testAFieldWithNoLabelIsSpokenAsItsName() {
        XCTAssertEqual(
            FieldGroupLogic.accessibleName(
                for: field("first_name"), state: optional, requiredTemplate: requiredEN
            ),
            "first_name"
        )
    }

    /// Required-ness comes from the state, not from `field.required`. A field a
    /// condition makes required carries `required: nil` on the wire, so reading
    /// the flag would leave the shopper who most needs the word without it.
    func testAFieldMadeRequiredByItsConditionIsSpokenAsRequired() {
        let state = FieldGroupLogic.fieldState(
            for: field("state", condition: FieldCondition(
                whenField: "country", whenIn: ["US"], display: "required", default: "hidden"
            )),
            groupValues: ["country": "US"]
        )
        XCTAssertEqual(
            FieldGroupLogic.accessibleName(
                for: field("state", label: "State / Province"),
                state: state,
                requiredTemplate: requiredEN
            ),
            "State / Province, required"
        )
    }
}
