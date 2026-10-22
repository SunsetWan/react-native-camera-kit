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
    private var currentZoom = 1.0
    private var zoomStartedAt = 1.0
    private var running = false
    private var didSetup = false
    private var orientationObserver: NSObjectProtocol?
    private var focusTimer: Timer?

    func setup(cameraType: CameraType, supportedBarcodeType: [CodeFormat]) {
        guard !didSetup else { return }
        didSetup = true
        update(cameraType: cameraType)
        update(zoom: nil)
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
    func update(cameraType: CameraType) { mockPreview.cameraTypeLabel.text = "Camera: \(cameraType)" }
    func update(resizeMode: ResizeMode) { mockPreview.resizeModeLabel.text = "Resize: \(resizeMode)" }

    func update(maxZoom: Double?) {
        self.maxZoom = maxZoom.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        setZoom(zoom ?? currentZoom)
    }

    func update(zoom: Double?) {
        self.zoom = zoom.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        setZoom(self.zoom ?? currentZoom)
    }

    func zoomPinchStart() { zoomStartedAt = currentZoom }

    func zoomPinchChange(pinchScale: CGFloat) {
        guard pinchScale.isFinite, pinchScale > 0 else { return }
        let desired = clamp(zoomStartedAt * pinchScale)
        guard desired != currentZoom else { return }
        if zoom == nil { setZoom(desired) }
        onZoom?(desired)
    }

    private func clamp(_ value: Double) -> Double { max(0.5, min(value, maxZoom ?? 75)) }
    private func setZoom(_ value: Double) {
        currentZoom = clamp(value)
        mockPreview.zoomLabel.text = String(format: "Zoom: %.2fx", currentZoom)
    }

    func focus(at touchPoint: CGPoint, focusBehavior: FocusBehavior) {
        mockPreview.focusAtLabel.text = "Focus: (\(Int(touchPoint.x)), \(Int(touchPoint.y)))"
        focusTimer?.invalidate()
        if case .customFocus(_, _, let finished) = focusBehavior {
            focusTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in finished() }
        }
    }

    func capturePicture(onWillCapture: @escaping () -> Void,
                        onSuccess: @escaping (Data, Data?, CMVideoDimensions) -> Void,
                        onError: @escaping (String) -> Void) {
        guard running else { onError("The camera is not running."); return }
        onWillCapture()
        guard let data = mockPreview.snapshot().jpegData(compressionQuality: 0.85) else {
            onError("The simulator could not encode the photo.")
            return
        }
        onSuccess(data, nil, CMVideoDimensions(width: 480, height: 640))
    }
}
