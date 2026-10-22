import UIKit
import XCTest
@testable import NativeCameraKit

final class SimulatorSnapshotTests: XCTestCase {
    @MainActor
    func testBurstSnapshotKeepsSceneBrightnessDuringPreviousShutterFade() async throws {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        }
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let preview = SimulatorPreviewView(frame: CGRect(x: 0, y: 0, width: 240, height: 320))
        controller.view.addSubview(preview)
        preview.layoutIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(100))
        let baseline = try brightPixelFraction(in: preview.snapshot(withTimestamp: false))
        XCTAssertGreaterThan(baseline, 0.7)

        let shutter = CABasicAnimation(keyPath: "opacity")
        shutter.fromValue = 0.1
        shutter.toValue = 0.1
        shutter.duration = 5
        preview.layer.add(shutter, forKey: "opacity")
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertLessThan(try XCTUnwrap(preview.layer.presentation()).opacity, 0.2)

        let captured = try brightPixelFraction(in: preview.snapshot(withTimestamp: false))
        XCTAssertGreaterThan(captured, 0.7, "A previous shutter fade must not darken the next saved photo.")
        XCTAssertEqual(captured, baseline, accuracy: 0.1)
    }

    private func brightPixelFraction(in image: UIImage) throws -> Double {
        let source = try XCTUnwrap(image.cgImage)
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
        let bright = stride(from: 0, to: pixels.count, by: 4).filter { offset in
            max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) > 200
        }.count
        return Double(bright) / Double(size * size)
    }
}
