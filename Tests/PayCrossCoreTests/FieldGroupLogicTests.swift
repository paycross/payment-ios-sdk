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

    // MARK: - Opt-in groups

    private let contact = FieldGroup(
        key: "contact",
        label: "Contact",
        fields: [FieldDefinition(name: "email", label: "Email", required: true)]
    )

    /// A shipping group the merchant offers rather than requires. Its fields are
    /// required *if* the group counts at all, which is the whole difficulty.
    private let shipping = FieldGroup(
        key: "shipping_address",
        label: "Shipping Address",
        labels: ["en": "Shipping Address", "fr": "Adresse de livraison"],
        optIn: true,
        fields: [
            FieldDefinition(name: "line1", label: "Address line 1", required: true),
            FieldDefinition(name: "city", label: "City", required: true)
        ]
    )

    /// The same group as a merchant who did not mark it sends it.
    private var shippingMandatory: FieldGroup {
        FieldGroup(
            key: shipping.key, label: shipping.label, labels: shipping.labels,
            fields: shipping.fields
        )
    }

    func testAGroupWithoutTheFlagIsNotOptIn() {
        XCTAssertFalse(shippingMandatory.isOptIn)
        XCTAssertNil(shippingMandatory.optIn)
    }

    func testAnOptInGroupCountsOnlyOnceItIsTickedIn() {
        XCTAssertFalse(FieldGroupLogic.isActive(shipping, optedIn: []))
        XCTAssertTrue(FieldGroupLogic.isActive(shipping, optedIn: ["shipping_address"]))
    }

    /// The flag is what makes a group declinable. A key in the set that names a
    /// group nobody marked must not turn that group off, or a stale entry would
    /// silently drop a mandatory address.
    func testAMandatoryGroupAlwaysCountsWhateverTheSetHolds() {
        XCTAssertTrue(FieldGroupLogic.isActive(contact, optedIn: []))
        XCTAssertTrue(FieldGroupLogic.isActive(shippingMandatory, optedIn: []))
        XCTAssertTrue(FieldGroupLogic.isActive(shippingMandatory, optedIn: ["contact"]))
    }

    func testActiveGroupsDropsOnlyTheDeclinedOnes() {
        XCTAssertEqual(
            FieldGroupLogic.activeGroups([contact, shipping], optedIn: []).map(\.key),
            ["contact"]
        )
        XCTAssertEqual(
            FieldGroupLogic.activeGroups(
                [contact, shipping], optedIn: ["shipping_address"]
            ).map(\.key),
            ["contact", "shipping_address"]
        )
    }

    /// The bug as filed: five required shipping fields with no way to decline,
    /// so a shopper who wanted delivery to the billing address could not pay.
    func testADeclinedGroupsRequiredFieldsDoNotBlockThePayment() {
        let errors = FieldGroupLogic.validate(
            groups: FieldGroupLogic.activeGroups([contact, shipping], optedIn: []),
            values: ["contact": ["email": "a@b.test"]]
        )
        XCTAssertEqual(errors, [])
    }

    func testATickedGroupIsValidatedLikeAnyOther() {
        let errors = FieldGroupLogic.validate(
            groups: FieldGroupLogic.activeGroups(
                [contact, shipping], optedIn: ["shipping_address"]
            ),
            values: ["contact": ["email": "a@b.test"]]
        )
        XCTAssertEqual(errors.map(\.fieldName), ["line1", "city"])
        XCTAssertEqual(errors.first?.groupKey, "shipping_address")
    }

    /// Without the flag nothing changes: the same group still blocks the same
    /// payment it blocked before, whatever the set says.
    func testAGroupWithoutTheFlagStillBlocksThePayment() {
        let errors = FieldGroupLogic.validate(
            groups: FieldGroupLogic.activeGroups(
                [contact, shippingMandatory], optedIn: []
            ),
            values: ["contact": ["email": "a@b.test"]]
        )
        XCTAssertEqual(errors.map(\.fieldName), ["line1", "city"])
    }

    /// Omitted, not emptied. An empty dictionary under `shipping_address` is a
    /// shopper saying "here is my shipping address: nothing", which is a
    /// different claim from not having been asked.
    func testADeclinedGroupIsAbsentFromTheSubmissionEntirely() {
        let submitted = FieldGroupLogic.submissionValues(
            groups: FieldGroupLogic.activeGroups([contact, shipping], optedIn: []),
            values: [
                "contact": ["email": "a@b.test"],
                // The merchant prefilled it and the shopper never ticked the
                // group. Held in state so ticking restores it; never sent.
                "shipping_address": ["line1": "1 Rue de Rivoli", "city": "Paris"]
            ]
        )
        XCTAssertEqual(submitted, ["contact": ["email": "a@b.test"]])
        XCTAssertNil(submitted["shipping_address"])
    }

    func testATickedGroupIsSubmittedWithItsValues() {
        let submitted = FieldGroupLogic.submissionValues(
            groups: FieldGroupLogic.activeGroups(
                [contact, shipping], optedIn: ["shipping_address"]
            ),
            values: [
                "contact": ["email": "a@b.test"],
                "shipping_address": ["line1": "1 Rue de Rivoli", "city": "Paris"]
            ]
        )
        XCTAssertEqual(
            submitted["shipping_address"], ["line1": "1 Rue de Rivoli", "city": "Paris"]
        )
    }

    // MARK: - The server's length limit

    /// 254 rather than a round number, so an off-by-one shows up as the wrong
    /// count rather than as a plausible one.
    private let limit = 254

    private func notesErrors(
        _ value: String,
        messages: FlowMessages = .english,
        language: String? = nil,
        validation: FieldValidation? = nil
    ) -> [FieldGroupError] {
        let group = FieldGroup(
            key: "extra",
            fields: [
                field(
                    "notes",
                    label: "Notes",
                    labels: ["en": "Notes", "fr": "Remarques"],
                    validation: validation ?? FieldValidation(maxLength: limit)
                )
            ]
        )
        return FieldGroupLogic.validate(
            groups: [group], values: ["extra": ["notes": value]],
            messages: messages, language: language
        )
    }

    func testAValueAtTheLimitPasses() {
        XCTAssertEqual(notesErrors(String(repeating: "a", count: limit)), [])
    }

    func testOneCharacterPastTheLimitIsRejected() {
        let errors = notesErrors(String(repeating: "a", count: limit + 1))
        XCTAssertEqual(errors.map(\.fieldName), ["notes"])
        XCTAssertEqual(errors.first?.message, "Notes must be 254 characters or fewer")
    }

    /// The sentence has to name both the field and the limit. One without the
    /// other leaves the shopper knowing either what to shorten or how far.
    func testTheFallbackSentenceNamesTheFieldAndTheLimit() throws {
        let message = try XCTUnwrap(
            notesErrors(String(repeating: "a", count: limit + 1)).first?.message
        )
        XCTAssertTrue(message.contains("Notes"), message)
        XCTAssertTrue(message.contains("254"), message)
    }

    /// The shopper reads this in the language the sheet is in, and the SDK's own
    /// wording reaches Core already looked up.
    func testTheFallbackSentenceIsTheSheetsOwn() {
        var french = FlowMessages.english
        french.fieldTooLong = "Champ trop long : %@ (%@ caractères maximum)"
        let errors = notesErrors(
            String(repeating: "a", count: limit + 1), messages: french, language: "fr"
        )
        XCTAssertEqual(
            errors.first?.message, "Champ trop long : Remarques (254 caractères maximum)"
        )
    }

    /// A sentence the server wrote for this one field wins over ours, in the
    /// sheet's language, exactly as `required` and `pattern` already do.
    func testTheServersOwnSentenceWinsInTheSheetsLanguage() {
        let errors = notesErrors(
            String(repeating: "a", count: limit + 1),
            language: "fr",
            validation: FieldValidation(
                maxLength: limit,
                messages: ["max_length": "Too long"],
                messagesI18n: ["fr": ["max_length": "Trop long, désolé"]]
            )
        )
        XCTAssertEqual(errors.first?.message, "Trop long, désolé")
    }

    /// A session minted before the per-language maps carries one sentence, and
    /// it is still the server's to give.
    func testTheServersSingularSentenceIsUsedWhenItSendsNoMaps() {
        let errors = notesErrors(
            String(repeating: "a", count: limit + 1),
            validation: FieldValidation(
                maxLength: limit, messages: ["max_length": "Keep it short"]
            )
        )
        XCTAssertEqual(errors.first?.message, "Keep it short")
    }

    /// UTF-16 code units, because that is what Kotlin's `String.length` and
    /// JavaScript's `String.slice` count. Swift's own `count` is grapheme
    /// clusters, and a family emoji is one of those and eleven code units, so
    /// the two answers differ by ten on a single character.
    func testTheLimitIsCountedInUTF16CodeUnitsLikeTheOtherClients() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        XCTAssertEqual(family.count, 1, "the fixture is not the character it claims to be")
        XCTAssertEqual(family.utf16.count, 11)

        let errors = notesErrors(
            family, validation: FieldValidation(maxLength: 10)
        )
        XCTAssertEqual(
            errors.map(\.fieldName), ["notes"],
            "eleven code units passed a limit of ten; this SDK is counting graphemes"
        )
        XCTAssertEqual(notesErrors(family, validation: FieldValidation(maxLength: 11)), [])
    }

    /// One complaint per field. A value that is both too long and off-pattern
    /// must not stack two messages under one box.
    func testALengthFailureIsReportedInsteadOfThePatternNotAsWell() {
        let errors = notesErrors(
            String(repeating: "a", count: limit + 1),
            validation: FieldValidation(pattern: "^[0-9]+$", maxLength: limit)
        )
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.message, "Notes must be 254 characters or fewer")
    }

    /// A field the shopper left alone is not too long, however low the limit.
    func testABlankOptionalFieldIsNeverTooLong() {
        XCTAssertEqual(notesErrors("", validation: FieldValidation(maxLength: 1)), [])
        XCTAssertEqual(notesErrors("   ", validation: FieldValidation(maxLength: 1)), [])
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

    /// An empty label is not a name. This is the field the whole fix is for —
    /// the one nothing on screen identifies — so handing it an explicitly empty
    /// name would leave it exactly as unnamed as the placeholder fallback did.
    func testAFieldWhoseLabelIsEmptyIsSpokenAsItsName() {
        let blank = FieldDefinition(
            name: "first_name", label: "", labels: ["en": "", "fr": ""]
        )
        XCTAssertEqual(
            FieldGroupLogic.accessibleName(
                for: blank, state: optional, requiredTemplate: requiredEN, language: "en"
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
