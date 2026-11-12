#if os(iOS)
import SwiftUI
import UIKit
import XCTest

@MainActor
final class ViewHost {

    static let size = CGSize(width: 390, height: 844)

    static let settleTime: TimeInterval = 0.3

    private var windows: [UIWindow] = []

    @discardableResult
    func callAsFunction(_ view: some View) -> UIWindow {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(origin: .zero, size: Self.size)
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

    func settle(_ seconds: TimeInterval = ViewHost.settleTime) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func release() {
        windows.forEach { $0.isHidden = true }
        windows.removeAll()
    }
}

private extension UIWindow {
    convenience init(origin: CGPoint, size: CGSize) {
        self.init(frame: CGRect(origin: origin, size: size))
    }
}

@MainActor
func textFields(in view: UIView) -> [UITextField] {
    (view.subviews.compactMap { $0 as? UITextField }) + view.subviews.flatMap(textFields(in:))
}

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
