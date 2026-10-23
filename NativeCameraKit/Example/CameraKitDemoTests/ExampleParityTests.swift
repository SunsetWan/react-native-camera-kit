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

    func testHardwarePressInDoesNotDimOrCaptureBeforeRelease() throws {
        let controller = CameraViewController()
        controller.loadViewIfNeeded()
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        let shutter = try XCTUnwrap(descendants(of: UIButton.self, in: controller.view).first {
            $0.accessibilityIdentifier == "capture"
        })
        let count = try XCTUnwrap(descendants(of: UILabel.self, in: controller.view).first {
            $0.accessibilityIdentifier == "capture-count"
        })
        // A cancelled hardware press does not send the release callback.
        camera.onCaptureButtonPressIn?()
        XCTAssertEqual(shutter.alpha, 1, accuracy: 0.001)
        XCTAssertTrue(shutter.isEnabled)
        XCTAssertEqual(count.text, "0 photos")
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

    func testPhotoLandscapeKeepsPreviewTallAndControlsVisible() throws {
        let controller = CameraViewController()
        controller.loadViewIfNeeded()
        let status = try XCTUnwrap(descendants(of: UILabel.self, in: controller.view).first {
            $0.accessibilityIdentifier == "camera-status"
        })
        status.text = "Tap to focus. Pinch to zoom."
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        layout(controller, in: window, size: CGSize(width: 956, height: 440),
               safeArea: UIEdgeInsets(top: 80, left: 62, bottom: 21, right: 62))
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        let preview = camera.convert(camera.bounds, to: controller.view)
        print("PHOTO_LANDSCAPE preview=\(preview) safeArea=\(controller.view.safeAreaInsets)")
        XCTAssertGreaterThanOrEqual(preview.height, 250)
        let capture = try XCTUnwrap(descendants(of: UIButton.self, in: controller.view).first {
            $0.accessibilityIdentifier == "capture"
        })
        XCTAssertGreaterThanOrEqual(capture.convert(capture.bounds, to: controller.view).minX, preview.maxX)

        for identifier in ["flash", "switch-camera", "torch", "faces", "scan", "settings",
                           "reset-zoom", "capture", "latest-photo", "capture-count", "camera-status"] {
            let control = try XCTUnwrap(descendants(of: UIView.self, in: controller.view).first {
                $0.accessibilityIdentifier == identifier
            })
            let frame = control.convert(control.bounds, to: controller.view)
            XCTAssertFalse(control.isHidden, identifier)
            XCTAssertFalse(frame.isEmpty, identifier)
            XCTAssertTrue(controller.view.bounds.contains(frame), "\(identifier): \(frame)")
        }

        status.text = "Saved five JPEGs · median capture 999 ms"
        let count = try XCTUnwrap(descendants(of: UILabel.self, in: controller.view).first {
            $0.accessibilityIdentifier == "capture-count"
        })
        count.text = "125 photos"
        controller.view.layoutIfNeeded()
        let photo = try XCTUnwrap(descendants(of: UIButton.self, in: controller.view).first {
            $0.accessibilityIdentifier == "latest-photo"
        })
        let captureFrame = capture.convert(capture.bounds, to: controller.view)
        XCTAssertFalse(captureFrame.intersects(photo.convert(photo.bounds, to: controller.view)))
        XCTAssertFalse(captureFrame.intersects(count.convert(count.bounds, to: controller.view)))
        XCTAssertLessThanOrEqual(count.intrinsicContentSize.width, count.bounds.width + 1)
        XCTAssertLessThanOrEqual(status.sizeThatFits(CGSize(width: status.bounds.width, height: .greatestFiniteMagnitude)).height,
                                status.bounds.height + 1)
        let slider = try XCTUnwrap(descendants(of: UISlider.self, in: controller.view).first)
        XCTAssertGreaterThanOrEqual(slider.bounds.width, 100)
        attachLayout(controller.view, name: "Photo landscape")
    }

    func testPhotoRotationKeepsCameraHierarchyAndRestoresPortraitLayout() throws {
        let controller = CameraViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let portrait = CGSize(width: 440, height: 956)
        let portraitSafeArea = UIEdgeInsets(top: 100, left: 0, bottom: 34, right: 0)
        layout(controller, in: window, size: portrait, safeArea: portraitSafeArea)
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        camera.configuration.zoom = 3
        let hierarchy = ancestors(of: camera)
        let portraitFrame = camera.convert(camera.bounds, to: controller.view)
        XCTAssertGreaterThan(portraitFrame.height, 500)

        layout(controller, in: window, size: CGSize(width: 956, height: 440),
               safeArea: UIEdgeInsets(top: 80, left: 62, bottom: 21, right: 62))
        XCTAssertEqual(ancestors(of: camera), hierarchy)
        layout(controller, in: window, size: portrait, safeArea: portraitSafeArea)
        XCTAssertEqual(ancestors(of: camera), hierarchy)
        XCTAssertEqual(camera.convert(camera.bounds, to: controller.view), portraitFrame)
        XCTAssertEqual(camera.configuration.zoom, 3)
        XCTAssertTrue(camera.isRunning)
        attachLayout(controller.view, name: "Photo portrait after rotation")
    }

    func testScannerKeepsThreeToFourPreviewInBothLayouts() throws {
        let controller = CameraViewController(mode: .scanner)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let camera = try XCTUnwrap(descendants(of: CameraView.self, in: controller.view).first)
        for size in [CGSize(width: 440, height: 956), CGSize(width: 956, height: 440)] {
            layout(controller, in: window, size: size, safeArea: UIEdgeInsets(top: 80, left: 0, bottom: 21, right: 0))
            XCTAssertGreaterThan(camera.bounds.height, 0)
            XCTAssertEqual(camera.bounds.width / camera.bounds.height, 3 / 4, accuracy: 0.001)
        }
    }

    private func layout(_ controller: UIViewController, in window: UIWindow, size: CGSize, safeArea: UIEdgeInsets) {
        window.frame = CGRect(origin: .zero, size: size)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.additionalSafeAreaInsets = .zero
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        let systemInsets = controller.view.safeAreaInsets
        controller.additionalSafeAreaInsets = UIEdgeInsets(
            top: max(0, safeArea.top - systemInsets.top),
            left: max(0, safeArea.left - systemInsets.left),
            bottom: max(0, safeArea.bottom - systemInsets.bottom),
            right: max(0, safeArea.right - systemInsets.right)
        )
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    private func ancestors(of view: UIView) -> [ObjectIdentifier] {
        var result: [ObjectIdentifier] = []
        var ancestor = view.superview
        while let current = ancestor {
            result.append(ObjectIdentifier(current))
            ancestor = current.superview
        }
        return result
    }

    private func attachLayout(_ view: UIView, name: String) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants<View: UIView>(of type: View.Type, in root: UIView) -> [View] {
        root.subviews.flatMap { view in
            ((view as? View).map { [$0] } ?? []) + descendants(of: type, in: view)
        }
    }
}
