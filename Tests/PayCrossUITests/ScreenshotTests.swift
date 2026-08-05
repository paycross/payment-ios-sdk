#if os(iOS)
import XCTest
import SwiftUI
@testable import PayCross
@testable import PayCrossCore

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
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // One run-loop turn so UIKit-backed subviews commit their text.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
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
        isLoading: Bool = false
    ) -> some View {
        StatefulPreviewWrapper(state) { binding in
            CardFormView(
                state: binding,
                amount: self.amount,
                savedCards: savedCards,
                allowsSaving: true,
                isLoading: isLoading,
                onPay: {}
            )
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
