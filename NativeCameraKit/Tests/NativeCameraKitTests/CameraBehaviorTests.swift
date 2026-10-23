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
    func testConcurrentCapturesKeepIndependentResultsWhenTheyFinishOutOfOrder() async throws {
        let backend = CameraSpy()
        backend.holdsCapture = true
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        view.start()
        defer { view.stop() }
        let firstStarted = expectation(description: "First capture started")
        backend.onCaptureRequested = { firstStarted.fulfill() }
        let first = Task { try await view.capture() }
        await fulfillment(of: [firstStarted], timeout: 2)
        let secondStarted = expectation(description: "Second capture started before the first completed")
        backend.onCaptureRequested = { secondStarted.fulfill() }
        let second = Task { try await view.capture() }
        await fulfillment(of: [secondStarted], timeout: 2)
        backend.onCaptureRequested = nil
        XCTAssertEqual(backend.pendingCaptures.count, 2)
        guard backend.pendingCaptures.count == 2 else {
            backend.pendingCaptures.forEach { $0.fail("Test cleanup") }
            _ = await first.result
            _ = await second.result
            return
        }
        let firstData = jpegData(size: CGSize(width: 12, height: 8), color: .red)
        let secondData = jpegData(size: CGSize(width: 6, height: 10), color: .blue)
        backend.pendingCaptures[1].succeed(secondData, nil, CMVideoDimensions(width: 6, height: 10))
        let secondPhoto = try await second.value
        backend.pendingCaptures[0].succeed(firstData, nil, CMVideoDimensions(width: 12, height: 8))
        let firstPhoto = try await first.value
        defer {
            try? FileManager.default.removeItem(at: firstPhoto.url)
            try? FileManager.default.removeItem(at: secondPhoto.url)
        }
        XCTAssertNotEqual(firstPhoto.url, secondPhoto.url)
        XCTAssertEqual(try Data(contentsOf: firstPhoto.url), firstData)
        XCTAssertEqual(try Data(contentsOf: secondPhoto.url), secondData)
        XCTAssertEqual(firstPhoto.width, 12)
        XCTAssertEqual(secondPhoto.width, 6)
    }

    @MainActor
    func testConcurrentCaptureFailureDoesNotCompleteAnotherRequest() async {
        let backend = CameraSpy()
        backend.holdsCapture = true
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        view.start()
        defer { view.stop() }
        let firstStarted = expectation(description: "First capture started")
        backend.onCaptureRequested = { firstStarted.fulfill() }
        let first = Task { try await view.capture() }
        await fulfillment(of: [firstStarted], timeout: 2)
        let secondStarted = expectation(description: "Second capture started before the first completed")
        backend.onCaptureRequested = { secondStarted.fulfill() }
        let second = Task { try await view.capture() }
        await fulfillment(of: [secondStarted], timeout: 2)
        backend.onCaptureRequested = nil
        XCTAssertEqual(backend.pendingCaptures.count, 2)
        guard backend.pendingCaptures.count == 2 else {
            backend.pendingCaptures.forEach { $0.fail("Test cleanup") }
            _ = await first.result
            _ = await second.result
            return
        }
        backend.pendingCaptures[0].fail("First capture failed")
        await assertCaptureFailure(first, message: "First capture failed")
        backend.pendingCaptures[1].fail("Second capture was interrupted")
        await assertCaptureFailure(second, message: "Second capture was interrupted")
        backend.holdsCapture = false
        do { _ = try await view.capture() } catch {}
        XCTAssertEqual(backend.captureCount, 3)
    }

    @MainActor
    private func jpegData(size: CGSize, color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.jpegData(compressionQuality: 1)!
    }

    @MainActor
    private func assertCaptureFailure(_ task: Task<CapturedPhoto, Error>, message: String) async {
        do {
            _ = try await task.value
            XCTFail("Expected capture failure")
        } catch {
            XCTAssertEqual(error as? CameraError, .captureFailed(message))
        }
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

    @MainActor
    func testBackgroundResumePreservesSimulatorGestureZoomWithoutRepeatingResetEvent() async throws {
        let backend = SimulatorCamera()
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        var events: [Double] = []
        view.onZoom = { events.append($0) }
        view.start()
        defer { view.stop() }
        await drainMainQueue()
        backend.zoomPinchStart()
        backend.zoomPinchChange(pinchScale: 3)
        await drainMainQueue()
        let preview = try XCTUnwrap(backend.previewView as? SimulatorPreviewView)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 6.0")
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        await drainMainQueue()
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 6.0")
        XCTAssertEqual(events, [2, 6])
    }

    @MainActor
    func testSettingsChangedWhileStoppedReachSimulatorBeforeResume() async throws {
        let backend = SimulatorCamera()
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        var events: [Double] = []
        view.onZoom = { events.append($0) }
        view.start()
        await drainMainQueue()
        view.stop()
        view.configuration.maxZoom = 4
        view.configuration.zoom = 3
        let preview = try XCTUnwrap(backend.previewView as? SimulatorPreviewView)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 3.0")
        view.start()
        defer { view.stop() }
        await drainMainQueue()
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 3.0")
        XCTAssertEqual(events, [2])
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
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

    func testCancellingOverlappingPhotoDelegatesPreservesEachCaptureIDAndNativeLifetime() async {
        let completion = expectation(description: "Both captures report their own cancellation")
        completion.expectedFulfillmentCount = 2
        completion.assertForOverFulfill = true
        let settings = [AVCapturePhotoSettings(), AVCapturePhotoSettings()]
        let delegates = settings.enumerated().map { index, settings in
            PhotoCaptureDelegate(
                with: settings, onWillCapture: {},
                onCaptureSuccess: { _, _, _, _ in XCTFail("A cancelled photo cannot succeed") },
                onCaptureError: { id, message in
                    XCTAssertEqual(id, settings.uniqueID)
                    XCTAssertEqual(message, "Cancelled capture \(index)")
                    completion.fulfill()
                },
                onFinished: { _ in XCTFail("Cancellation must wait for the native capture transaction to finish") }
            )
        }
        delegates[1].cancel(message: "Cancelled capture 1")
        delegates[0].cancel(message: "Cancelled capture 0")
        delegates.forEach { $0.cancel(message: "Repeated cancellation") }
        await fulfillment(of: [completion], timeout: 2)
    }

    func testInvalidRatioInputsDoNotProduceOverlays() {
        for input in ["", "4", "0:1", "1:0", "-4:3", "nan:3", "inf:2"] {
            XCTAssertEqual(RatioOverlayData(from: input).ratio, 0, input)
        }
        XCTAssertEqual(RatioOverlayData(from: "16:9").ratio, 9.0 / 16.0, accuracy: 0.001)
    }

    @MainActor
    func testScannerFrameStaysCenteredWhenViewHasOffset() {
        let view = ScannerInterfaceView(frameColor: .white, laserColor: .red)
        view.frame = CGRect(x: 100, y: 200, width: 240, height: 160)
        view.update(frameSize: CGSize(width: 300, height: 150))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        XCTAssertEqual(view.frameSize.midX, view.bounds.midX, accuracy: 0.01)
        XCTAssertEqual(view.frameSize.midY, view.bounds.midY, accuracy: 0.01)
        XCTAssertEqual(view.frameSize.size, CGSize(width: 300, height: 150))
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
    struct PendingCapture {
        let succeed: (Data, Data?, CMVideoDimensions) -> Void
        let fail: (String) -> Void
    }
    var pendingCaptures: [PendingCapture] = []

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
        if holdsCapture {
            pendingCaptures.append(PendingCapture(succeed: onSuccess, fail: onError))
        } else {
            onError("Test camera unavailable")
        }
    }
}
