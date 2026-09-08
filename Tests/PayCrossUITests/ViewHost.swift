#if os(iOS)
import SwiftUI
import UIKit
import XCTest

/// Puts a SwiftUI view in a real window and keeps it there.
///
/// Every test that reads geometry, walks the view tree or takes a first
/// responder needs the same five lines, the same window size and the same wait
/// for SwiftUI to commit its layout. They were copied into five test files, each
/// with its own idea of how long to wait; this is the one place to change it if
/// the Mac job ever starts flaking.
///
/// `DeclineBannerTests` keeps its own: it compares renders pixel by pixel and
/// waits longer on purpose. `ThreeDSPresentationTests` keeps its own too,
/// because what it hosts is a `UIViewController` rather than a view.
@MainActor
final class ViewHost {

    static let size = CGSize(width: 390, height: 844) // iPhone 17 portrait

    /// SwiftUI commits its layout, and the UIKit-backed subviews draw their
    /// text, over the next few turns of the run loop rather than synchronously.
    static let settleTime: TimeInterval = 0.3

    /// Held for the duration of a test; a released window takes the hierarchy
    /// under test with it.
    private var windows: [UIWindow] = []

    @discardableResult
    func callAsFunction(_ view: some View) -> UIWindow {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(origin: .zero, size: Self.size)
        // Attach to the live scene when there is one. A SwiftPM test bundle
        // often has no foreground scene, and without one a hosted field cannot
        // take first responder.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.rootViewController = controller
        window.isHidden = false
        window.makeKeyAndVisible()
        windows.append(window)

        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        settle()
        return window
    }

    /// Lets SwiftUI catch up after something changed under it.
    func settle(_ seconds: TimeInterval = ViewHost.settleTime) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Call from `tearDown`, where there is one. A host held as a `let` on the
    /// test case releases with it either way, which is what the files that
    /// cannot write a main-actor `tearDown` rely on.
    func release() {
        // Hidden first: a window left key and visible after its test can take
        // events meant for the next one's.
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
    }
}

private extension UIWindow {
    convenience init(origin: CGPoint, size: CGSize) {
        self.init(frame: CGRect(origin: origin, size: size))
    }
}

/// Every `UITextField` under a view, in tree order.
@MainActor
func textFields(in view: UIView) -> [UITextField] {
    (view.subviews.compactMap { $0 as? UITextField }) + view.subviews.flatMap(textFields(in:))
}

/// How many pixels differ between two renders, ignoring alpha.
///
/// The measurement of last resort, and the only one that answers for a SwiftUI
/// `Text`: it is drawn into a layer rather than into a `UILabel`, and this
/// bundle has no app host to build an accessibility tree from.
func differingPixels(_ first: UIImage, _ second: UIImage) throws -> Int {
    let a = try XCTUnwrap(first.cgImage)
    let b = try XCTUnwrap(second.cgImage)
    let width = min(a.width, b.width)
    let height = min(a.height, b.height)

    var left = [UInt8](repeating: 0, count: width * height * 4)
    var right = left
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    CGContext(
        data: &left, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space, bitmapInfo: info
    )?.draw(a, in: bounds)
    CGContext(
        data: &right, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space, bitmapInfo: info
    )?.draw(b, in: bounds)

    var differing = 0
    for index in stride(from: 0, to: left.count, by: 4)
    where left[index] != right[index]
        || left[index + 1] != right[index + 1]
        || left[index + 2] != right[index + 2] {
        differing += 1
    }
    return differing
}
#endif
