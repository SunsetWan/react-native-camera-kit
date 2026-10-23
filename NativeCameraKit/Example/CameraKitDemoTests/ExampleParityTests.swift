import UIKit
import XCTest
@testable import CameraKitDemo
@testable import NativeCameraKit

@MainActor
final class ExampleParityTests: XCTestCase {
    func testCameraPresetMatchesSourceExample() throws {
        let controller = CameraViewController()
        controller.loadViewIfNeeded()
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        XCTAssertEqual(camera.configuration.maxZoom, 10)
        XCTAssertEqual(camera.configuration.maxPhotoQualityPrioritization, .speed)
        XCTAssertEqual(camera.configuration.faceDetectionThrottleMs, 50)
        XCTAssertEqual(camera.configuration.resizeMode, .contain)
        XCTAssertEqual(camera.configuration.flashMode, .auto)
        XCTAssertEqual(camera.configuration.torchMode, .off)
        XCTAssertTrue(camera.configuration.resetFocusWhenMotionDetected)
        XCTAssertNil(camera.configuration.zoom)
    }

    func testPhotoViewerKeepsSourcePixelsAndTenTimesZoom() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3072, height: 2304), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3072, height: 2304))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 2000, y: 1000, width: 1, height: 1))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 1))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let photo = CapturedPhoto(url: url, size: data.count, width: 3072, height: 2304)
        let controller = PhotoViewController(photo: photo)
        controller.loadViewIfNeeded()
        let scroll = try XCTUnwrap(descendants(of: UIScrollView.self, in: controller.view).first)
        let imageView = try XCTUnwrap(descendants(of: UIImageView.self, in: scroll).first)
        XCTAssertEqual(scroll.maximumZoomScale, 10)
        XCTAssertEqual(imageView.image?.cgImage?.width, 3072)
        XCTAssertEqual(imageView.image?.cgImage?.height, 2304)
    }

    func testScannerKeepsSourceDefaultsAndFilter() throws {
        let controller = CameraViewController(mode: .scanner)
        controller.loadViewIfNeeded()
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        XCTAssertNil(camera.configuration.maxZoom)
        XCTAssertNil(camera.configuration.zoom)
        XCTAssertEqual(camera.configuration.maxPhotoQualityPrioritization, .balanced)
        XCTAssertEqual(camera.configuration.faceDetectionThrottleMs, 100)
        XCTAssertEqual(camera.configuration.scanThrottleDelay, 2000)
        XCTAssertEqual(camera.configuration.allowedBarcodeTypes, [.qr, .ean13])
        XCTAssertEqual(camera.configuration.barcodeFrameSize, CGSize(width: 300, height: 150))
        XCTAssertTrue(camera.configuration.scanBarcode)
        XCTAssertTrue(camera.configuration.showFrame)
        XCTAssertEqual(camera.configuration.frameColor, .white)
        XCTAssertEqual(camera.configuration.laserColor, .red)
    }

    func testFaceStatsIncludeCountFacingAndNormalizedBounds() throws {
        let controller = CameraViewController()
        controller.loadViewIfNeeded()
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        camera.configuration.faceDetectionEnabled = true
        camera.onFaceDetected?([
            FaceDetectionPayload(id: 0, yaw: 1, pitch: 2, roll: 3, boundsX: 0.3, boundsY: 0.2, boundsWidth: 0.4, boundsHeight: 0.6)
        ])
        let text = descendants(of: UILabel.self, in: controller.view).compactMap(\.text).joined(separator: "\n")
        XCTAssertTrue(text.contains("Faces: 1"))
        XCTAssertTrue(text.contains("Facing: yes"))
        XCTAssertTrue(text.contains("Box: 0.30,0.20 0.40×0.60"))
        let statistics = try XCTUnwrap(descendants(of: UILabel.self, in: controller.view).first { $0.accessibilityIdentifier == "face-statistics" })
        XCTAssertFalse(statistics.isHidden)
        camera.onFaceDetected?([])
        let cleared = descendants(of: UILabel.self, in: controller.view).compactMap(\.text).joined(separator: "\n")
        XCTAssertTrue(cleared.contains("Faces: 0"))
        XCTAssertFalse(cleared.contains("Facing: yes"))
    }

    func testOrientationEventRotatesCameraIcons() throws {
        let controller = CameraViewController()
        controller.loadViewIfNeeded()
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        let flash = try XCTUnwrap(descendants(of: UIButton.self, in: controller.view).first { $0.accessibilityIdentifier == "flash" })
        UIView.performWithoutAnimation { camera.onOrientationChange?(.landscapeLeft) }
        let transform = try XCTUnwrap(flash.imageView?.transform)
        XCTAssertEqual(transform.a, 0, accuracy: 0.001)
        XCTAssertEqual(transform.b, 1, accuracy: 0.001)
    }

    func testIconRotationSubtractsTheInterfaceRotation() {
        let matchingOrientations: [(Orientation, UIInterfaceOrientation)] = [
            (.portrait, .portrait), (.landscapeLeft, .landscapeRight),
            (.portraitUpsideDown, .portraitUpsideDown), (.landscapeRight, .landscapeLeft)
        ]
        for (device, interface) in matchingOrientations {
            XCTAssertEqual(CameraViewController.iconRotation(for: device, interfaceOrientation: interface), 0, accuracy: 0.001)
        }
        XCTAssertEqual(CameraViewController.iconRotation(for: .landscapeLeft, interfaceOrientation: .portrait), .pi / 2, accuracy: 0.001)
        XCTAssertEqual(CameraViewController.iconRotation(for: .landscapeRight, interfaceOrientation: .portrait), -.pi / 2, accuracy: 0.001)
    }

    func testPhotoZoomCallbackKeepsTheSourceControlledZoomFlow() throws {
        let controller = CameraViewController()
        controller.loadViewIfNeeded()
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        camera.onZoom?(2.5)
        XCTAssertEqual(camera.configuration.zoom, 2.5)
        let switchButton = try XCTUnwrap(descendants(of: UIButton.self, in: controller.view).first { $0.accessibilityIdentifier == "switch-camera" })
        switchButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(camera.configuration.cameraType, .front)
        XCTAssertEqual(camera.configuration.zoom, 1)
    }

    private func descendants<View: UIView>(of type: View.Type, in root: UIView) -> [View] {
        root.subviews.flatMap { view in
            ((view as? View).map { [$0] } ?? []) + descendants(of: type, in: view)
        }
    }
}
