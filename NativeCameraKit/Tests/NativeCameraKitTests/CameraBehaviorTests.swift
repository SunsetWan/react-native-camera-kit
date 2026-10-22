import AVFoundation
import UIKit
import XCTest
@testable import NativeCameraKit

final class CameraBehaviorTests: XCTestCase {
    func testScanThrottleUsesMillisecondsAndAllowsFirstEvent() {
        var throttle = ScanThrottle()
        XCTAssertTrue(throttle.shouldEmit(at: 0, delayMilliseconds: 2_000))
        XCTAssertFalse(throttle.shouldEmit(at: 1.999, delayMilliseconds: 2_000))
        XCTAssertFalse(throttle.shouldEmit(at: 2, delayMilliseconds: 2_000))
        XCTAssertTrue(throttle.shouldEmit(at: 2.001, delayMilliseconds: 2_000))
        XCTAssertTrue(throttle.shouldEmit(at: 2.002, delayMilliseconds: -1))
    }

    @MainActor
    func testSessionCanStopAndRestartWithSameBackend() {
        let backend = CameraSpy()
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        view.start()
        view.start()
        XCTAssertEqual(backend.setupCount, 1)
        XCTAssertEqual(backend.startCount, 1)
        view.stop()
        XCTAssertFalse(view.isRunning)
        view.start()
        XCTAssertEqual(backend.setupCount, 2)
        XCTAssertEqual(backend.startCount, 2)
        XCTAssertEqual(backend.stopCount, 1)
        view.stop()
    }

    @MainActor
    func testReleasingUnattachedViewStopsBackend() async {
        let backend = CameraSpy()
        weak var releasedView: CameraView?
        autoreleasepool {
            let view = CameraView(camera: backend, bypassCameraPermission: true)
            releasedView = view
            view.start()
        }
        XCTAssertNil(releasedView)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertGreaterThanOrEqual(backend.stopCount, 1)
    }

    @MainActor
    func testInitialAndUpdatedBarcodeFiltersReachBackend() {
        let backend = CameraSpy()
        var configuration = CameraConfiguration()
        configuration.scanBarcode = true
        configuration.allowedBarcodeTypes = [.qr]
        let view = CameraView(camera: backend, configuration: configuration, bypassCameraPermission: true)
        view.start()
        XCTAssertEqual(backend.barcodeTypes, [.qr])
        configuration.allowedBarcodeTypes = [.ean13, .code128]
        view.configuration = configuration
        XCTAssertEqual(backend.barcodeTypes, [.ean13, .code128])
        configuration.allowedBarcodeTypes = []
        view.configuration = configuration
        XCTAssertEqual(Set(backend.barcodeTypes), Set(CodeFormat.allCases))
        view.stop()
    }

    @MainActor
    func testBarcodeCallbackStopsAfterStopOrDisable() {
        let backend = CameraSpy()
        var configuration = CameraConfiguration()
        configuration.scanBarcode = true
        configuration.scanThrottleDelay = 0
        let view = CameraView(camera: backend, configuration: configuration, bypassCameraPermission: true)
        var values: [String] = []
        view.onReadCode = { values.append($0.codeStringValue) }
        view.start()
        view.receiveBarcode("first", format: .qr)
        view.stop()
        view.receiveBarcode("stale", format: .qr)
        view.start()
        view.configuration.scanBarcode = false
        view.receiveBarcode("disabled", format: .qr)
        XCTAssertEqual(values, ["first"])
        view.stop()
    }

    @MainActor
    func testCaptureBeforeStartFailsWithoutCallingBackend() async {
        let backend = CameraSpy()
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        do {
            _ = try await view.capture()
            XCTFail("Capture must fail before start")
        } catch {
            XCTAssertEqual(error as? CameraError, .notRunning)
        }
        XCTAssertEqual(backend.captureCount, 0)
    }

    @MainActor
    func testBackendCaptureFailureResumesAsyncCaller() async {
        let backend = CameraSpy()
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        view.start()
        do {
            _ = try await view.capture()
            XCTFail("Expected backend failure")
        } catch {
            XCTAssertEqual(error as? CameraError, .captureFailed("Test camera unavailable"))
        }
        XCTAssertEqual(backend.captureCount, 1)
        view.stop()
    }

    @MainActor
    func testConcurrentCaptureIsRejectedAndNextCaptureCanProceed() async throws {
        let backend = CameraSpy()
        backend.holdsCapture = true
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        view.start()
        let started = expectation(description: "First capture started")
        backend.onCaptureRequested = { started.fulfill() }
        let first = Task { try await view.capture() }
        await fulfillment(of: [started], timeout: 2)
        backend.onCaptureRequested = nil
        XCTAssertEqual(backend.captureCount, 1)
        do {
            _ = try await view.capture()
            XCTFail("An overlapping capture must fail")
        } catch {
            XCTAssertEqual(error as? CameraError, .captureInProgress)
        }
        backend.pendingError?("Interrupted")
        do {
            _ = try await first.value
            XCTFail("The first capture was interrupted")
        } catch {
            XCTAssertEqual(error as? CameraError, .captureFailed("Interrupted"))
        }
        backend.holdsCapture = false
        do { _ = try await view.capture() } catch {}
        XCTAssertEqual(backend.captureCount, 2)
        view.stop()
    }

    @MainActor
    func testSimulatorCaptureWritesDecodableUniqueJPEGFiles() async throws {
        let camera = CameraView(camera: SimulatorCamera(), bypassCameraPermission: true)
        camera.start()
        defer { camera.stop() }
        let first = try await camera.capture()
        let second = try await camera.capture()
        defer {
            try? FileManager.default.removeItem(at: first.url)
            try? FileManager.default.removeItem(at: second.url)
        }
        XCTAssertNotEqual(first.url, second.url)
        let data = try Data(contentsOf: first.url)
        XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xd8])
        XCTAssertEqual(first.size, data.count)
        XCTAssertEqual(first.url.pathExtension, "jpg")
        XCTAssertTrue(first.uri.hasPrefix("file://"))
        XCTAssertEqual(first.thumb, "")
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(first.width, image.width)
        XCTAssertEqual(first.height, image.height)
        XCTAssertGreaterThan(first.width, 0)
    }

    @MainActor
    func testBackgroundResumeDoesNotUndoExplicitStop() {
        let backend = CameraSpy()
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        view.start()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(view.isRunning)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(view.isRunning)
        XCTAssertEqual(backend.startCount, 2)
        view.stop()
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertFalse(view.isRunning)
        XCTAssertEqual(backend.startCount, 2)
    }

    func testCancelledPhotoDelegateCompletesOnlyOnce() async {
        let completion = expectation(description: "Capture reports cancellation")
        completion.assertForOverFulfill = true
        let delegate = PhotoCaptureDelegate(
            with: AVCapturePhotoSettings(), onWillCapture: {},
            onCaptureSuccess: { _, _, _, _ in XCTFail("A cancelled photo cannot succeed") },
            onCaptureError: { _, message in
                XCTAssertEqual(message, "Interrupted")
                XCTAssertTrue(Thread.isMainThread)
                completion.fulfill()
            }
        )
        delegate.cancel(message: "Interrupted")
        delegate.cancel(message: "Stopped")
        await fulfillment(of: [completion], timeout: 2)
    }

    func testInvalidRatioInputsDoNotProduceOverlays() {
        for input in ["", "4", "0:1", "1:0", "-4:3", "nan:3", "inf:2"] {
            XCTAssertEqual(RatioOverlayData(from: input).ratio, 0, input)
        }
        XCTAssertEqual(RatioOverlayData(from: "16:9").ratio, 9.0 / 16.0, accuracy: 0.001)
    }

    @MainActor
    func testScannerFrameStaysInLocalBoundsWhenViewHasOffset() {
        let view = ScannerInterfaceView(frameColor: .white, laserColor: .red)
        view.frame = CGRect(x: 100, y: 200, width: 240, height: 160)
        view.update(frameSize: CGSize(width: 300, height: 150))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(view.frameSize.midX, view.bounds.midX, accuracy: 0.01)
        XCTAssertEqual(view.frameSize.midY, view.bounds.midY, accuracy: 0.01)
        XCTAssertTrue(view.bounds.contains(view.frameSize))
    }
}

private final class CameraSpy: CameraProtocol {
    let previewView = UIView()
    var onError: ((String) -> Void)?
    var setupCount = 0
    var startCount = 0
    var stopCount = 0
    var captureCount = 0
    var barcodeTypes: [CodeFormat] = []
    var onCaptureRequested: (() -> Void)?
    var holdsCapture = false
    var pendingError: ((String) -> Void)?

    func setup(cameraType: CameraType, supportedBarcodeType: [CodeFormat]) { setupCount += 1 }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func cameraRemovedFromSuperview() { stop() }
    func update(torchMode: TorchMode) {}
    func update(flashMode: FlashMode) {}
    func update(cameraType: CameraType) {}
    func update(onOrientationChange: ((Orientation) -> Void)?) {}
    func update(onZoom: ((Double) -> Void)?) {}
    func update(iOsDeferredStartEnabled: Bool?) {}
    func update(zoom: Double?) {}
    func update(maxZoom: Double?) {}
    func update(resizeMode: ResizeMode) {}
    func update(maxPhotoQualityPrioritization: MaxPhotoQualityPrioritization?) {}
    func update(barcodeFrameSize: CGSize?) {}
    func zoomPinchStart() {}
    func zoomPinchChange(pinchScale: CGFloat) {}
    func update(scannerFrameSize: CGRect?) {}
    func update(faceDetectionThrottleMs: Int) {}
    func focus(at touchPoint: CGPoint, focusBehavior: FocusBehavior) {}
    func isBarcodeScannerEnabled(
        _ isEnabled: Bool, supportedBarcodeTypes: [CodeFormat],
        onBarcodeRead: ((String, CodeFormat) -> Void)?
    ) { barcodeTypes = supportedBarcodeTypes }
    func isFaceDetectionEnabled(_ isEnabled: Bool, onFaceDetected: (([FaceDetectionPayload]) -> Void)?) {}
    func capturePicture(
        onWillCapture: @escaping () -> Void,
        onSuccess: @escaping (Data, Data?, CMVideoDimensions) -> Void,
        onError: @escaping (String) -> Void
    ) {
        captureCount += 1
        onCaptureRequested?()
        if holdsCapture { pendingError = onError } else { onError("Test camera unavailable") }
    }
}
