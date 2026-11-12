#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore
import DemoHarnessCore
import DemoHarnessUI

@MainActor
final class ScreenshotTests: XCTestCase {

    private static let size = CGSize(width: 390, height: 844) // iPhone 17 portrait

    private var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["PAYCROSS_SCREENSHOT_DIR"]
            ?? NSTemporaryDirectory().appending("paycross-screenshots")
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func capture(
        _ name: String,
        overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified,
        @ViewBuilder _ content: () -> some View
    ) throws {
        let controller = UIHostingController(rootView: content())
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.size))
        window.overrideUserInterfaceStyle = overrideUserInterfaceStyle
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        var image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        if !Self.hasVariedContent(image) {
            image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }

        let data = try XCTUnwrap(image.pngData(), "no PNG data for \(name)")
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try data.write(to: url)

        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(
            Self.hasVariedContent(image),
            "\(name) rendered as a flat colour - the view hierarchy did not draw"
        )
        Self.captured.insert(data.count)
    }

    private static func hasVariedContent(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = min(cgImage.width, 80)
        let height = min(cgImage.height, 160)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let first = Array(pixels.prefix(4))
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let pixel = Array(pixels[index..<index + 4])
            if zip(pixel, first).contains(where: { abs(Int($0) - Int($1)) > 8 }) {
                return true
            }
        }
        return false
    }

    private static var captured: Set<Int> = []

    private var amount: Amount { Amount(minorUnits: 2599, currencyCode: "EUR") }

    private func form(
        _ state: CardFormState,
        isLoading: Bool = false,
        fieldGroups: [FieldGroup] = [],
        fieldErrors: [FieldGroupError] = [],
        showsApplePayButton: Bool = false,
        allowsCardRemoval: Bool = false
    ) -> some View {
        let language = SheetLanguage.tag
        return StatefulPreviewWrapper([String: [String: String]]()) { values in
        StatefulPreviewWrapper(state) { binding in
            CardFormView(
                state: binding,
                amount: self.amount,
                allowsSaving: true,
                allowsCardRemoval: allowsCardRemoval,
                isLoading: isLoading,
                fieldGroups: fieldGroups,
                fieldValues: values,
                optedInGroups: .constant([]),
                fieldErrors: fieldErrors,
                language: language,
                onPay: {},
                showsApplePayButton: showsApplePayButton,
                onApplePay: {}
            )
        }
        }
    }

    // MARK: - States

    func testEmptyForm() throws {
        try capture("01-empty") { form(CardFormState()) }
    }

    func testFilledForm() throws {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))
        try capture("02-filled-visa") { form(state) }
    }

    func testAmexShowsFourDigitCVV() throws {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("378282246310005"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("1234"))
        try capture("03-filled-amex") { form(state) }
    }

    func testDeclinedForm() throws {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(state: &state, event: .declined(message: "Payment failed. Please try again."))
        try capture("04-declined") { form(state) }
    }

    func testLoadingForm() throws {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))
        try capture("05-loading") { form(state, isLoading: true) }
    }

    func testSavedCardSelection() throws {
        var state = CardFormState(savedCards: Self.savedCards)
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(Self.savedCards[0])))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))
        try capture("06-saved-card") { form(state) }
    }

    func testNewCardAlongsideSavedCards() throws {
        let state = CardFormState(savedCards: [Self.savedCards[0]])
        try capture("07-new-card-with-saved") { form(state) }
    }

    func testSavedCardsWithRemovalAllowed() throws {
        let state = CardFormState(savedCards: Self.savedCards)
        try capture("14-saved-card-removable") { form(state, allowsCardRemoval: true) }
    }

    // MARK: - French

    func testFrenchForm() throws {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        defer { SheetLanguage.reset() }

        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))

        try capture("21-french") {
            form(state, showsApplePayButton: true)
                .environment(\.locale, SheetLanguage.locale)
        }
    }

    func testFrenchFormAfterADecline() throws {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        defer { SheetLanguage.reset() }

        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(
            state: &state,
            event: .declined(message: L("paycross_error_payment_failed", "MISSING"))
        )

        let groups = [FieldGroup(key: "billing", label: "Adresse de facturation", fields: [
            FieldDefinition(
                name: "postcode", type: "text", label: "Code postal",
                placeholder: "75001", required: true
            )
        ])]
        let messages = FlowMessages(fieldRequired: L("paycross_field_required", "MISSING"))

        try capture("22-french-declined") {
            form(
                state, fieldGroups: groups,
                fieldErrors: [FieldGroupError(
                    groupKey: "billing", fieldName: "postcode",
                    message: messages.requiredMessage(for: "Code postal")
                )]
            )
            .environment(\.locale, SheetLanguage.locale)
        }
    }

    // MARK: - The confirmations

    func testCancelConfirmation() throws {
        let model = sheetModel()
        model.isConfirmingCancel = true
        try capture("25-cancel-confirmation") { PaymentSheetView(model: model) }
    }

    func testRemoveCardConfirmation() throws {
        let model = sheetModel()
        model.cardPendingRemoval = Self.savedCards[0]
        try capture("26-remove-confirmation") { PaymentSheetView(model: model) }
    }

    func testCancelConfirmationAtTheAccessibilityCeiling() throws {
        let model = sheetModel()
        model.isConfirmingCancel = true
        try capture("27-cancel-confirmation-ceiling") {
            PaymentSheetView(model: model).dynamicTypeSize(.accessibility5)
        }
    }

    func testFrenchRemoveConfirmationAtTheAccessibilityCeiling() throws {
        defer { SheetLanguage.reset() }

        let model = sheetModel(locale: "fr")
        model.cardPendingRemoval = Self.savedCards[0]
        try capture("28-french-remove-confirmation-ceiling") {
            PaymentSheetView(model: model).dynamicTypeSize(.accessibility5)
        }
    }

    func testFrenchCancelConfirmationAtTheAccessibilityCeiling() throws {
        defer { SheetLanguage.reset() }

        let model = sheetModel(locale: "fr")
        model.isConfirmingCancel = true
        try capture("29-french-cancel-confirmation-ceiling") {
            PaymentSheetView(model: model).dynamicTypeSize(.accessibility5)
        }
    }

    private func sheetModel(locale: String? = nil) -> PaymentSheetModel {
        PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1", brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"), expiresAt: nil
            ),
            configuration: Configuration(environment: .sandbox, locale: locale),
            sessionData: SessionData(),
            isPreparing: false,
            transport: StubTransport(json: #"{"session_id":"sess_1","status":"open"}"#)
        )
    }

    // MARK: - The accessibility ceiling

    func testFormAtTheAccessibilityCeiling() throws {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))

        try capture("23-accessibility-ceiling") {
            form(state, showsApplePayButton: true)
                .payCrossTypeScale(.unstyled)
                .dynamicTypeSize(.accessibility5)
        }
    }

    func testFrenchFormAtTheAccessibilityCeiling() throws {
        SheetLanguage.install(LocaleResolution.resolve(override: "fr"))
        defer { SheetLanguage.reset() }

        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(
            state: &state,
            event: .declined(message: L("paycross_error_payment_failed", "MISSING"))
        )

        try capture("24-french-accessibility-ceiling") {
            form(state)
                .environment(\.locale, SheetLanguage.locale)
                .payCrossTypeScale(.unstyled)
                .dynamicTypeSize(.accessibility5)
        }
    }

    private static let savedCards = [
        SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30"),
        SavedCard(id: "b", brand: .mastercard, last4: "4444", expiryLabel: "01/29")
    ]

    func testFormWithServerDrivenFields() throws {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))

        let groups = [FieldGroup(key: "billing", label: "Billing address", fields: [
            FieldDefinition(
                name: "country", type: "select", label: "Country", required: true,
                options: [FieldOption(value: "US", label: "United States"),
                          FieldOption(value: "GB", label: "United Kingdom")]
            ),
            FieldDefinition(
                name: "postcode", type: "text", label: "Postcode",
                placeholder: "SW1A 1AA", required: true,
                validation: FieldValidation(pattern: "^[A-Z0-9 ]+$", maxLength: 8)
            )
        ])]

        try capture("08-field-groups") {
            form(
                state, fieldGroups: groups,
                fieldErrors: [FieldGroupError(
                    groupKey: "billing", fieldName: "postcode",
                    message: "Postcode is required"
                )]
            )
        }
    }

    func testFormWithApplePayButton() throws {
        try capture("09-apple-pay") {
            form(CardFormState(), showsApplePayButton: true)
        }
    }

    // MARK: - Branded

    private static let branded = AppearanceStyle(
        resolved: AppearanceResolver.resolve(appearance: brandedAppearance)
    )

    private static let brandedAppearance = PayCrossAppearance(
        light: PayCrossColors(
            brand: PayCrossColor(hex: "#FFC107"),
            surface: PayCrossColor(hex: "#FFF8E1"),
            component: PayCrossColor(hex: "#FFFFFF"),
            componentBorder: PayCrossColor(hex: "#E0B84C"),
            text: PayCrossColor(hex: "#2B2118"),
            textSecondary: PayCrossColor(hex: "#7A6A55"),
            placeholder: PayCrossColor(hex: "#B9A483"),
            icon: PayCrossColor(hex: "#7A6A55"),
            error: PayCrossColor(hex: "#B3261E")
        ),
        dark: PayCrossColors(
            brand: PayCrossColor(hex: "#FFC107"),
            surface: PayCrossColor(hex: "#171310"),
            component: PayCrossColor(hex: "#241E18"),
            componentBorder: PayCrossColor(hex: "#4A3E2C"),
            text: PayCrossColor(hex: "#F5EFE6"),
            textSecondary: PayCrossColor(hex: "#BCAE99"),
            placeholder: PayCrossColor(hex: "#7A6A55"),
            icon: PayCrossColor(hex: "#BCAE99"),
            error: PayCrossColor(hex: "#F2B8B5")
        ),
        shapes: PayCrossShapes(cornerRadius: 16, buttonCornerRadius: 28, borderWidth: 1)
    )

    private var brandedState: CardFormState {
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .nameChanged("A Person"))
        CardFormReducer.reduce(state: &state, event: .panChanged("4111111111111111"))
        CardFormReducer.reduce(state: &state, event: .expiryChanged("1230"))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))
        return state
    }

    func testBrandedFormInLight() throws {
        try capture("15-branded-light", overrideUserInterfaceStyle: .light) {
            form(brandedState).environment(\.payCrossAppearance, Self.branded)
        }
    }

    func testBrandedFormInDark() throws {
        try capture("16-branded-dark", overrideUserInterfaceStyle: .dark) {
            form(brandedState).environment(\.payCrossAppearance, Self.branded)
        }
    }

    func testBrandedSavedCardsInLight() throws {
        try capture("17-branded-saved-cards-light", overrideUserInterfaceStyle: .light) {
            form(CardFormState(savedCards: Self.savedCards), allowsCardRemoval: true)
                .environment(\.payCrossAppearance, Self.branded)
        }
    }

    func testBrandedSavedCardsInDark() throws {
        try capture("18-branded-saved-cards-dark", overrideUserInterfaceStyle: .dark) {
            form(CardFormState(savedCards: Self.savedCards), allowsCardRemoval: true)
                .environment(\.payCrossAppearance, Self.branded)
        }
    }

    private func brandedSheet() -> PaymentSheetView {
        PaymentSheetView(model: PaymentSheetModel(
            sessionToken: "header.payload.signature",
            claims: SessionClaims(
                sessionID: "sess_1", merchantID: "m1", customerID: "c1", brandingID: nil,
                amount: Amount(minorUnits: 2599, currencyCode: "EUR"), expiresAt: nil
            ),
            configuration: Configuration(
                environment: .sandbox, appearance: Self.brandedAppearance
            ),
            sessionData: SessionData(),
            isPreparing: false,
            transport: StubTransport(json: #"{"session_id":"sess_1","status":"open"}"#)
        ))
    }

    func testBrandedSheetInLight() throws {
        try capture("19-branded-sheet-light", overrideUserInterfaceStyle: .light) {
            brandedSheet()
        }
    }

    func testBrandedSheetInDark() throws {
        try capture("20-branded-sheet-dark", overrideUserInterfaceStyle: .dark) {
            brandedSheet()
        }
    }

    // MARK: - Harness screens

    private var seededData: DemoData {
        let merchant = Merchant(
            id: "m1", name: "Sandbox merchant", environment: .staging,
            tokenURL: "https://auth.example.com/token", clientID: "id",
            clientSecret: "secret", paymentAPIURL: "https://api.example.com/payment-sessions"
        )
        let production = Merchant(id: "m2", name: "LIVE merchant", environment: .production)
        var data = DemoData(
            merchants: [merchant, production],
            scenarios: [
                Scenario(
                    id: "s1", merchantID: "m1", name: "Approve",
                    card: CardPrefill(pan: "4111111111111111"),
                    requestBody: "{}", hint: "Straight-through approval"
                ),
                Scenario(
                    id: "s2", merchantID: "m1", name: "3DS challenge",
                    card: CardPrefill(pan: "4000027891380961"),
                    requestBody: "{}", hint: "Presents an ACS challenge"
                ),
                Scenario(
                    id: "s3", merchantID: "m1", name: "Decline",
                    requestBody: "{}", hint: "Issuer decline, retryable"
                )
            ],
            selectedMerchantID: "m1"
        )
        data.record(RunRecord(
            scenarioName: "Approve", surface: .sdk, sessionID: "sess_a1b2c3",
            outcome: "succeeded", transactionID: "txn_1", amount: 2599, currency: "EUR"
        ))
        data.record(RunRecord(
            scenarioName: "3DS challenge", surface: .browser,
            sessionID: "sess_d4e5f6", outcome: "pending"
        ))
        data.record(RunRecord(
            scenarioName: "Decline", surface: .qr, sessionID: "sess_g7h8i9",
            outcome: "failed · declined"
        ))
        return data
    }

    func testHarnessHome() throws {
        try capture("10-harness-home") {
            StatefulPreviewWrapper(seededData) { data in
                StatefulPreviewWrapper(CheckoutSurface.sdk) { surface in
                    NavigationStack {
                        HarnessHomeView(
                            data: data, surface: surface,
                            onRun: { _, _ in }, onShowHistory: {}
                        )
                    }
                }
            }
        }
    }

    func testHarnessHomeWithProductionMerchantSelected() throws {
        var data = seededData
        data.selectedMerchantID = "m2"
        try capture("11-harness-production") {
            StatefulPreviewWrapper(data) { bound in
                StatefulPreviewWrapper(CheckoutSurface.browser) { surface in
                    NavigationStack {
                        HarnessHomeView(
                            data: bound, surface: surface,
                            onRun: { _, _ in }, onShowHistory: {}
                        )
                    }
                }
            }
        }
    }

    func testHarnessHistory() throws {
        try capture("12-harness-history") {
            NavigationStack {
                HarnessHistoryView(runs: seededData.runs, onSelect: { _ in })
            }
        }
    }

    func testProductionGate() throws {
        try capture("13-production-gate") {
            ProductionGateView(
                merchantName: "LIVE merchant", scenarioName: "Approve",
                onConfirm: {}, onCancel: {}
            )
        }
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
#endif
