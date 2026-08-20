#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore
import DemoHarnessCore
import DemoHarnessUI

/// Renders the card form in each of its meaningful states and writes PNGs.
///
/// This exists because the author develops on Linux and cannot open a simulator.
/// CI runs these on a macOS runner and uploads the PNGs as build artifacts, which
/// is the only way anyone sees this UI before a Mac arrives.
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

    /// Renders through a real `UIHostingController` in a real window.
    ///
    /// `ImageRenderer` looks like the obvious tool and produces blank images here:
    /// it cannot render UIKit-backed views, and `TextField`/`SecureField` are
    /// exactly that. Hosting in a window and calling `drawHierarchy` renders the
    /// genuine view hierarchy, text fields included.
    private func capture(_ name: String, @ViewBuilder _ content: () -> some View) throws {
        let controller = UIHostingController(rootView: content())
        let window = UIWindow(frame: CGRect(origin: .zero, size: Self.size))
        // Attach to the live scene when there is one. A SwiftPM test bundle often
        // has no foreground scene, which is why drawHierarchy alone renders blank.
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
        // Let SwiftUI commit its layout and UIKit-backed subviews draw their text.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        // layer.render(in:) walks the layer tree directly and does not require the
        // window to be attached to a live screen, unlike drawHierarchy.
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

        // Also attach, so the PNG survives in the .xcresult even if the artifact
        // upload path changes.
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // A blank render is comfortably larger than 1KB, so size proves nothing.
        // The first version of this harness shipped seven byte-identical blank
        // PNGs and passed. Assert the image actually has content in it.
        XCTAssertTrue(
            Self.hasVariedContent(image),
            "\(name) rendered as a flat colour - the view hierarchy did not draw"
        )
        Self.captured.insert(data.count)
    }

    /// True when the image contains meaningfully more than one colour.
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
            // Any pixel differing by more than a rounding wobble means content.
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
        savedCards: [SavedCard] = [],
        isLoading: Bool = false,
        fieldGroups: [FieldGroup] = [],
        fieldErrors: [FieldGroupError] = []
    ) -> some View {
        StatefulPreviewWrapper([String: [String: String]]()) { values in
        StatefulPreviewWrapper(state) { binding in
            CardFormView(
                state: binding,
                amount: self.amount,
                savedCards: savedCards,
                allowsSaving: true,
                isLoading: isLoading,
                fieldGroups: fieldGroups,
                fieldValues: values,
                fieldErrors: fieldErrors,
                onPay: {}
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
        let saved = [
            SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30"),
            SavedCard(id: "b", brand: .mastercard, last4: "4444", expiryLabel: "01/29")
        ]
        var state = CardFormState()
        CardFormReducer.reduce(state: &state, event: .sourceSelected(.saved(saved[0])))
        CardFormReducer.reduce(state: &state, event: .cvvChanged("123"))
        try capture("06-saved-card") { form(state, savedCards: saved) }
    }

    func testNewCardAlongsideSavedCards() throws {
        let saved = [SavedCard(id: "a", brand: .visa, last4: "1111", expiryLabel: "12/30")]
        try capture("07-new-card-with-saved") { form(CardFormState(), savedCards: saved) }
    }

    /// A checkout the server has decorated with extra fields, one of them
    /// conditional and one showing a validation failure.
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

/// Gives a `@Binding` to a value in a context that has no `@State`.
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
