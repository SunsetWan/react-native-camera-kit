import AVFoundation
import UIKit
import XCTest
@testable import NativeCameraKit

final class UIParityTests: XCTestCase {
    @MainActor
    func testRatioGuideHasRequestedAspectAndStaysCenteredInEveryViewport() {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390), CGSize(width: 400, height: 400)] {
            for (ratio, widthOverHeight) in [("16:9", 9.0 / 16.0), ("9:16", 16.0 / 9.0), ("1:1", 1.0)] {
                let view = RatioOverlayView(frame: CGRect(origin: CGPoint(x: 40, y: 80), size: size), ratioString: ratio, overlayColor: nil)
                view.layoutIfNeeded()
                let visible = unobscuredRectangle(in: view)
                XCTAssertEqual(visible.width / visible.height, widthOverHeight, accuracy: 0.001, "\(size) \(ratio)")
                XCTAssertEqual(visible.midX, view.bounds.midX, accuracy: 0.001)
                XCTAssertEqual(visible.midY, view.bounds.midY, accuracy: 0.001)
                XCTAssertTrue(view.bounds.contains(visible))
                XCTAssertTrue(visible.width == size.width || visible.height == size.height)
            }
        }
    }

    func testRatioParserRejectsExtraSeparatorsAndOverflow() {
        for ratio in [":16:9", "16::9", "16:9:", "1e-30:1e30", "1e30:1e-30"] {
            XCTAssertEqual(RatioOverlayData(from: ratio).ratio, 0, ratio)
        }
    }

    @MainActor
    func testCameraPrimesControlledSettingsBeforeSessionSetup() {
        let backend = UIParityCameraSpy()
        var configuration = CameraConfiguration()
        configuration.zoom = 3
        configuration.maxZoom = 4
        configuration.flashMode = .off
        configuration.torchMode = .on
        configuration.maxPhotoQualityPrioritization = .quality
        let camera = CameraView(camera: backend, configuration: configuration, bypassCameraPermission: true)
        camera.start()
        XCTAssertEqual(backend.zoomAtSetup, 3)
        XCTAssertEqual(backend.maximumZoomAtSetup, 4)
        XCTAssertEqual(backend.flashAtSetup, .off)
        XCTAssertEqual(backend.torchAtSetup, .on)
        XCTAssertEqual(backend.qualityAtSetup, .quality)
        camera.stop()
    }

    @MainActor
    func testFaceDetectionOnlyInstallsOutputWhileCallbackExists() {
        let backend = UIParityCameraSpy()
        var configuration = CameraConfiguration()
        configuration.faceDetectionEnabled = true
        let camera = CameraView(camera: backend, configuration: configuration, bypassCameraPermission: true)
        camera.start()
        XCTAssertFalse(backend.hasFaceOutput)
        camera.onFaceDetected = { _ in }
        XCTAssertTrue(backend.hasFaceOutput)
        camera.onFaceDetected = nil
        XCTAssertFalse(backend.hasFaceOutput)
        camera.stop()
    }

    @MainActor
    func testBarcodeReadsKeepLaserRunningUntilHiddenOrStopped() throws {
        let backend = UIParityCameraSpy()
        var configuration = CameraConfiguration()
        configuration.scanBarcode = true
        configuration.showFrame = true
        let camera = CameraView(camera: backend, configuration: configuration, bypassCameraPermission: true)
        camera.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        var acceptedCodes: [String] = []
        camera.onReadCode = { acceptedCodes.append($0.codeStringValue) }
        camera.start()
        camera.layoutIfNeeded()
        let scanner = try XCTUnwrap(camera.subviews.compactMap { $0 as? ScannerInterfaceView }.first)
        let frame = try XCTUnwrap(scanner.subviews.compactMap { $0 as? ScannerFrameView }.first)
        frame.layoutIfNeeded()
        let laser = try XCTUnwrap(frame.subviews.first)
        XCTAssertNotNil(laser.layer.animation(forKey: "scan"))
        camera.receiveBarcode("accepted", format: .qr)
        XCTAssertNotNil(laser.layer.animation(forKey: "scan"))
        camera.receiveBarcode("throttled", format: .qr)
        XCTAssertEqual(acceptedCodes, ["accepted"])
        XCTAssertNotNil(laser.layer.animation(forKey: "scan"))
        camera.configuration.torchMode = .on
        XCTAssertNotNil(laser.layer.animation(forKey: "scan"))
        camera.configuration.showFrame = false
        XCTAssertTrue(scanner.isHidden)
        XCTAssertNil(laser.layer.animation(forKey: "scan"))
        camera.configuration.showFrame = true
        XCTAssertNotNil(laser.layer.animation(forKey: "scan"))
        camera.stop()
        XCTAssertNil(laser.layer.animation(forKey: "scan"))
    }

    @MainActor
    func testBarcodeCallbackTracksListenerPresence() {
        let backend = UIParityCameraSpy()
        var configuration = CameraConfiguration()
        configuration.scanBarcode = true
        let camera = CameraView(camera: backend, configuration: configuration, bypassCameraPermission: true)
        camera.start()
        XCTAssertFalse(backend.hasBarcodeListener)
        camera.onReadCode = { _ in }
        XCTAssertTrue(backend.hasBarcodeListener)
        camera.onReadCode = nil
        XCTAssertFalse(backend.hasBarcodeListener)
        camera.stop()
    }

    @MainActor
    func testFocusCancellationRestoresContinuousModeAtLocalCenter() {
        let delegate = UIParityCameraSpy()
        let focus = FocusInterfaceView(frame: CGRect(x: 80, y: 120, width: 300, height: 500))
        focus.delegate = delegate
        focus.update(focusMode: .on)
        focus.focusAndExposeTap(FixedPointTap(point: CGPoint(x: 30, y: 50)))
        XCTAssertEqual(delegate.focusPoints.last, CGPoint(x: 30, y: 50))
        focus.cancelPendingFocus()
        XCTAssertEqual(delegate.focusPoints.last, CGPoint(x: 150, y: 250))
        XCTAssertTrue(delegate.lastFocusWasContinuous)
        XCTAssertTrue(focus.subviews.allSatisfy(\.isHidden))
    }

    @MainActor
    func testStaleFocusCallbackDoesNotResetNewerTap() async throws {
        let delegate = UIParityCameraSpy()
        let focus = FocusInterfaceView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        focus.delegate = delegate
        focus.update(focusMode: .on)
        focus.focusAndExposeTap(FixedPointTap(point: CGPoint(x: 30, y: 50)))
        let staleReset = try XCTUnwrap(delegate.focusReset)
        focus.focusAndExposeTap(FixedPointTap(point: CGPoint(x: 200, y: 400)))
        staleReset()
        await drainMainQueue()
        XCTAssertEqual(delegate.focusPoints.count, 2)
        XCTAssertFalse(delegate.lastFocusWasContinuous)
        focus.cancelPendingFocus()
    }

    @MainActor
    func testFocusCompletionCannotRearmTimerAfterCancellation() async throws {
        let delegate = UIParityCameraSpy()
        let focus = FocusInterfaceView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        focus.delegate = delegate
        focus.update(focusMode: .on)
        focus.update(resetFocusTimeout: 10)
        focus.focusAndExposeTap(FixedPointTap(point: CGPoint(x: 30, y: 50)))
        let staleFinished = try XCTUnwrap(delegate.focusFinished)
        focus.cancelPendingFocus()
        staleFinished()
        await drainMainQueue()
        let callCount = delegate.focusPoints.count
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(delegate.focusPoints.count, callCount)
        XCTAssertTrue(focus.subviews.allSatisfy(\.isHidden))
    }

    @MainActor
    func testCompletedFocusResetsAfterConfiguredTimeout() async throws {
        let delegate = UIParityCameraSpy()
        let focus = FocusInterfaceView(frame: CGRect(x: 80, y: 120, width: 300, height: 500))
        focus.delegate = delegate
        focus.update(focusMode: .on)
        focus.update(resetFocusTimeout: 10)
        focus.focusAndExposeTap(FixedPointTap(point: CGPoint(x: 30, y: 50)))
        let reset = expectation(description: "Manual focus returns to continuous focus")
        delegate.onContinuousFocus = { point in
            XCTAssertEqual(point, CGPoint(x: 150, y: 250))
            reset.fulfill()
        }
        delegate.focusFinished?()
        await fulfillment(of: [reset], timeout: 1)
        XCTAssertTrue(delegate.lastFocusWasContinuous)
        focus.cancelPendingFocus()
    }

    @MainActor
    func testSwiftUIControllerPreservesOptionalDetectionCallbacks() {
        let backend = UIParityCameraSpy()
        var configuration = CameraConfiguration()
        configuration.scanBarcode = true
        configuration.faceDetectionEnabled = true
        let controller = CameraController(configuration: configuration)
        let view = CameraView(camera: backend, bypassCameraPermission: true)
        controller.attach(view)
        view.start()
        XCTAssertNil(view.onReadCode)
        XCTAssertFalse(backend.hasFaceOutput)
        controller.onReadCode = { _ in }
        controller.onFaceDetected = { _ in }
        XCTAssertNotNil(view.onReadCode)
        XCTAssertTrue(backend.hasFaceOutput)
        controller.onReadCode = nil
        controller.onFaceDetected = nil
        XCTAssertNil(view.onReadCode)
        XCTAssertFalse(backend.hasFaceOutput)
        controller.detach(view)
    }

    @MainActor
    func testQueuedOrientationAndZoomEventsDoNotEscapeStoppedSession() async {
        let backend = UIParityCameraSpy()
        let camera = CameraView(camera: backend, bypassCameraPermission: true)
        var callbacks = 0
        camera.onOrientationChange = { _ in callbacks += 1 }
        camera.onZoom = { _ in callbacks += 1 }
        camera.start()
        backend.orientationCallback?(.landscapeLeft)
        backend.zoomCallback?(3)
        camera.stop()
        await drainMainQueue()
        XCTAssertEqual(callbacks, 0)
    }

    @MainActor
    private func unobscuredRectangle(in view: RatioOverlayView) -> CGRect {
        let masks = view.subviews.map(\.frame).filter { !$0.isEmpty }
        guard let first = masks.first, let last = masks.last else { return view.bounds }
        if first.width == view.bounds.width {
            return CGRect(x: view.bounds.minX, y: first.maxY, width: view.bounds.width, height: last.minY - first.maxY)
        }
        return CGRect(x: first.maxX, y: view.bounds.minY, width: last.minX - first.maxX, height: view.bounds.height)
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }
}

private final class FixedPointTap: UITapGestureRecognizer {
    let point: CGPoint
    init(point: CGPoint) {
        self.point = point
        super.init(target: nil, action: nil)
    }
    override func location(in view: UIView?) -> CGPoint { point }
}

private final class UIParityCameraSpy: CameraProtocol {
    let previewView = UIView()
    var onError: ((String) -> Void)?
    var zoom: Double?
    var maximumZoom: Double?
    var flash: FlashMode?
    var torch: TorchMode?
    var quality: MaxPhotoQualityPrioritization?
    var zoomAtSetup: Double?
    var maximumZoomAtSetup: Double?
    var flashAtSetup: FlashMode?
    var torchAtSetup: TorchMode?
    var qualityAtSetup: MaxPhotoQualityPrioritization?
    var hasFaceOutput = false
    var hasBarcodeListener = false
    var focusPoints: [CGPoint] = []
    var onContinuousFocus: ((CGPoint) -> Void)?
    var lastFocusWasContinuous = false
    var focusReset: (() -> Void)?
    var focusFinished: (() -> Void)?
    var orientationCallback: ((Orientation) -> Void)?
    var zoomCallback: ((Double) -> Void)?

    func setup(cameraType: CameraType, supportedBarcodeType: [CodeFormat]) {
        zoomAtSetup = zoom
        maximumZoomAtSetup = maximumZoom
        flashAtSetup = flash
        torchAtSetup = torch
        qualityAtSetup = quality
    }
    func start() {}
    func stop() {}
    func cameraRemovedFromSuperview() {}
    func update(torchMode: TorchMode) { torch = torchMode }
    func update(flashMode: FlashMode) { flash = flashMode }
    func update(cameraType: CameraType) {}
    func update(onOrientationChange: ((Orientation) -> Void)?) { orientationCallback = onOrientationChange }
    func update(onZoom: ((Double) -> Void)?) { zoomCallback = onZoom }
    func update(iOsDeferredStartEnabled: Bool?) {}
    func update(zoom: Double?) { self.zoom = zoom }
    func update(maxZoom: Double?) { maximumZoom = maxZoom }
    func update(resizeMode: ResizeMode) {}
    func update(maxPhotoQualityPrioritization: MaxPhotoQualityPrioritization?) { quality = maxPhotoQualityPrioritization }
    func update(barcodeFrameSize: CGSize?) {}
    func zoomPinchStart() {}
    func zoomPinchChange(pinchScale: CGFloat) {}
    func update(scannerFrameSize: CGRect?) {}
    func update(faceDetectionThrottleMs: Int) {}
    func focus(at touchPoint: CGPoint, focusBehavior: FocusBehavior) {
        focusPoints.append(touchPoint)
        if case .customFocus(_, let reset, let finished) = focusBehavior {
            lastFocusWasContinuous = false
            focusReset = reset
            focusFinished = finished
        } else {
            lastFocusWasContinuous = true
            onContinuousFocus?(touchPoint)
        }
    }
    func isBarcodeScannerEnabled(_ isEnabled: Bool, supportedBarcodeTypes: [CodeFormat], onBarcodeRead: ((String, CodeFormat) -> Void)?) {
        hasBarcodeListener = onBarcodeRead != nil
    }
    func isFaceDetectionEnabled(_ isEnabled: Bool, onFaceDetected: (([FaceDetectionPayload]) -> Void)?) {
        hasFaceOutput = isEnabled && onFaceDetected != nil
    }
    func capturePicture(onWillCapture: @escaping () -> Void, onSuccess: @escaping (Data, Data?, CMVideoDimensions) -> Void, onError: @escaping (String) -> Void) {
        onError("Test camera does not capture")
    }
}
