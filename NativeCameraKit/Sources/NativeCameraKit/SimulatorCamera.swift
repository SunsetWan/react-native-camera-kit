import AVFoundation
import UIKit

/// Simulator calls are made by CameraView on the main queue, as required by UIKit.
final class SimulatorCamera: CameraProtocol {
    var onError: ((String) -> Void)?
    var previewView: UIView { mockPreview }
    private let mockPreview = SimulatorPreviewView(frame: .zero)
    private var onOrientationChange: ((Orientation) -> Void)?
    private var onZoom: ((Double) -> Void)?
    private var zoom: Double?
    private var maxZoom: Double?
    private var cameraType: CameraType?
    private var currentZoom = 1.0
    private var lastZoom: Double?
    private var zoomStartedAt = 1.0
    private var running = false
    private var didSetup = false
    private var orientationObserver: NSObjectProtocol?
    private var focusTimer: Timer?

    func setup(cameraType: CameraType, supportedBarcodeType: [CodeFormat]) {
        guard !didSetup else { return }
        didSetup = true
        update(cameraType: cameraType)
    }

    func start() {
        guard didSetup, !running else { return }
        running = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: UIDevice.current, queue: .main
        ) { [weak self] _ in
            if let orientation = Orientation(from: UIDevice.current.orientation) {
                self?.onOrientationChange?(orientation)
            }
        }
    }

    func stop() {
        running = false
        focusTimer?.invalidate()
        focusTimer = nil
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    deinit {
        if let orientationObserver { NotificationCenter.default.removeObserver(orientationObserver) }
        focusTimer?.invalidate()
    }

    func cameraRemovedFromSuperview() { stop() }
    func update(onOrientationChange: ((Orientation) -> Void)?) { self.onOrientationChange = onOrientationChange }
    func update(onZoom: ((Double) -> Void)?) { self.onZoom = onZoom }
    func update(iOsDeferredStartEnabled: Bool?) {}
    func update(maxPhotoQualityPrioritization: MaxPhotoQualityPrioritization?) {}
    func update(barcodeFrameSize: CGSize?) {}
    func update(scannerFrameSize: CGRect?) {}
    func update(faceDetectionThrottleMs: Int) {}
    func isBarcodeScannerEnabled(_ isEnabled: Bool, supportedBarcodeTypes: [CodeFormat],
                                 onBarcodeRead: ((String, CodeFormat) -> Void)?) {}
    func isFaceDetectionEnabled(_ isEnabled: Bool, onFaceDetected: (([FaceDetectionPayload]) -> Void)?) {}

    func update(torchMode: TorchMode) { mockPreview.torchModeLabel.text = "Torch: \(torchMode)" }
    func update(flashMode: FlashMode) { mockPreview.flashModeLabel.text = "Flash: \(flashMode)" }
    func update(cameraType: CameraType) {
        guard self.cameraType != cameraType else { return }
        self.cameraType = cameraType
        mockPreview.cameraTypeLabel.text = "Camera: \(cameraType)"
        mockPreview.randomize()
        setZoom(zoom ?? 1)
        emitZoom(currentZoom)
    }
    func update(resizeMode: ResizeMode) {
        mockPreview.resizeModeLabel.text = "Resize: \(resizeMode)"
        mockPreview.randomize()
    }

    func update(maxZoom: Double?) {
        self.maxZoom = maxZoom.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        setZoom(zoom ?? currentZoom)
    }

    func update(zoom: Double?) {
        self.zoom = zoom.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        setZoom(self.zoom ?? currentZoom)
    }

    func zoomPinchStart() {
        zoomStartedAt = currentZoom
        lastZoom = nil
    }

    func zoomPinchChange(pinchScale: CGFloat) {
        guard pinchScale.isFinite, pinchScale > 0 else { return }
        let desired = clamp(zoomStartedAt * pinchScale)
        guard desired != currentZoom else { return }
        if zoom == nil { setZoom(desired) }
        emitZoom(desired)
    }

    private func emitZoom(_ value: Double) {
        guard value != lastZoom else { return }
        lastZoom = value
        onZoom?(value)
    }

    private func clamp(_ value: Double) -> Double {
        max(cameraType == .front ? 1 : 0.5, min(value, min(maxZoom ?? 75, 75)))
    }
    private func setZoom(_ value: Double) {
        currentZoom = clamp(value)
        mockPreview.zoomLabel.text = String(format: "Zoom: %.2fx", currentZoom)
    }

    func focus(at touchPoint: CGPoint, focusBehavior: FocusBehavior) {
        mockPreview.focusAtLabel.text = "Focus: (\(Int(touchPoint.x)), \(Int(touchPoint.y)))"
        focusTimer?.invalidate()
        if case .customFocus(_, _, let finished) = focusBehavior {
            focusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in finished() }
        }
    }

    func capturePicture(onWillCapture: @escaping () -> Void,
                        onSuccess: @escaping (Data, Data?, CMVideoDimensions) -> Void,
                        onError: @escaping (String) -> Void) {
        guard running else { onError("The camera is not running."); return }
        let image = mockPreview.snapshot()
        guard let pixels = image.cgImage, let data = image.jpegData(compressionQuality: 0.85) else {
            onError("The simulator could not encode the photo.")
            return
        }
        // Snapshot before the caller starts its shutter animation.
        onWillCapture()
        onSuccess(data, nil, CMVideoDimensions(width: Int32(pixels.width), height: Int32(pixels.height)))
    }
}
