import AVFoundation
import AVKit
import UIKit

/// A UIKit camera preview with capture, scanning, focus, and zoom controls.
/// Configure callbacks before adding the view to a window. Call `stop()` to pause it.
@MainActor
public final class CameraView: UIView {
    private let camera: CameraProtocol
    private let bypassCameraPermission: Bool
    private let focusInterfaceView = FocusInterfaceView()
    private let scannerInterfaceView = ScannerInterfaceView(frameColor: .white, laserColor: .red)
    private var ratioOverlayView: RatioOverlayView?
    private var zoomGestureRecognizer: UIPinchGestureRecognizer?
    private var scanThrottle = ScanThrottle()
    private var hasCameraBeenSetup = false
    private var wantsRunning = false
    private var permissionRequestPending = false
    private var isInBackground = false
    private var captureInProgress = false
    private var hardwareInteraction: Any?

    /// True while a session start is requested. Hardware readiness is asynchronous.
    public private(set) var isRunning = false
    public var configuration: CameraConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            applyConfiguration(previous: oldValue)
        }
    }

    public var onReadCode: ((Barcode) -> Void)? {
        didSet { updateBarcodeDetection() }
    }
    public var onFaceDetected: (([FaceDetectionPayload]) -> Void)? {
        didSet { updateFaceDetection() }
    }
    public var onOrientationChange: ((Orientation) -> Void)?
    public var onZoom: ((Double) -> Void)?
    public var onCaptureButtonPressIn: (() -> Void)?
    public var onCaptureButtonPressOut: (() -> Void)?
    public var onError: ((CameraError) -> Void)?

    public convenience init(configuration: CameraConfiguration = .init()) {
        #if targetEnvironment(simulator)
        self.init(camera: SimulatorCamera(), configuration: configuration, bypassCameraPermission: true)
        #else
        self.init(camera: RealCamera(), configuration: configuration)
        #endif
    }

    init(
        camera: CameraProtocol,
        configuration: CameraConfiguration = .init(),
        bypassCameraPermission: Bool = false
    ) {
        self.camera = camera
        self.configuration = configuration
        self.bypassCameraPermission = bypassCameraPermission
        super.init(frame: .zero)
        clipsToBounds = true
        backgroundColor = .black
        addSubview(camera.previewView)
        addSubview(scannerInterfaceView)
        addSubview(focusInterfaceView)
        focusInterfaceView.delegate = camera
        scannerInterfaceView.isUserInteractionEnabled = false
        camera.onError = { [weak self] message in
            DispatchQueue.main.async { self?.onError?(.captureFailed(message)) }
        }
        camera.update(onOrientationChange: { [weak self] orientation in
            DispatchQueue.main.async { self?.onOrientationChange?(orientation) }
        })
        camera.update(onZoom: { [weak self] zoom in
            DispatchQueue.main.async { self?.onZoom?(zoom) }
        })
        applyConfiguration(previous: nil)
        configureHardwareInteraction()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let camera = camera
        Task { @MainActor [camera] in camera.stop() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        camera.previewView.frame = bounds
        scannerInterfaceView.frame = bounds
        scannerInterfaceView.layoutIfNeeded()
        focusInterfaceView.frame = bounds
        ratioOverlayView?.frame = bounds
        updateScanRegion()
    }

    /// Requests permission if necessary and starts or resumes the camera.
    public func start() {
        wantsRunning = true
        guard !isRunning, !isInBackground else { return }
        if bypassCameraPermission {
            startAuthorizedCamera()
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorizedCamera()
        case .notDetermined:
            guard !permissionRequestPending else { return }
            guard let description = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
                !description.isEmpty else {
                onError?(.missingUsageDescription)
                return
            }
            permissionRequestPending = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permissionRequestPending = false
                    guard self.wantsRunning else { return }
                    if granted { self.startAuthorizedCamera() } else { self.onError?(.permissionDenied) }
                }
            }
        default:
            onError?(.permissionDenied)
        }
    }

    /// Stops the session without discarding its configuration or callbacks.
    public func stop() {
        wantsRunning = false
        pauseCamera()
    }

    private func pauseCamera() {
        isRunning = false
        camera.stop()
        focusInterfaceView.cancelPendingFocus()
        scannerInterfaceView.stopAnimatingScanner()
        setHardwareInteractionEnabled(false)
    }

    @objc private func applicationDidEnterBackground() {
        isInBackground = true
        pauseCamera()
    }

    @objc private func applicationWillEnterForeground() {
        isInBackground = false
        if wantsRunning { start() }
    }

    /// Captures JPEG data and writes it to the app cache off the main thread.
    public func capture() async throws -> CapturedPhoto {
        guard isRunning else { throw CameraError.notRunning }
        guard !captureInProgress else { throw CameraError.captureInProgress }
        captureInProgress = true
        defer { captureInProgress = false }
        return try await withCheckedThrowingContinuation { continuation in
            camera.capturePicture(
                onWillCapture: { [weak self] in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.camera.previewView.alpha = 0
                        UIView.animate(withDuration: 0.35) { self.camera.previewView.alpha = 1 }
                    }
                },
                onSuccess: { [weak self] data, _, dimensions in
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = Result { try CapturedPhotoWriter.write(data, dimensions: dimensions) }
                        DispatchQueue.main.async {
                            self?.focusInterfaceView.resetFocus()
                            continuation.resume(with: result)
                        }
                    }
                },
                onError: { message in
                    continuation.resume(throwing: CameraError.captureFailed(message))
                }
            )
        }
    }

    private func startAuthorizedCamera() {
        guard wantsRunning, !isRunning, !isInBackground else { return }
        camera.update(iOsDeferredStartEnabled: configuration.iOsDeferredStart)
        camera.setup(
            cameraType: effectiveCameraType,
            supportedBarcodeType: configuration.scanBarcode ? configuration.supportedBarcodeTypes : []
        )
        hasCameraBeenSetup = true
        applyConfiguration(previous: nil)
        isRunning = true
        camera.start()
        if configuration.showFrame { scannerInterfaceView.startAnimatingScanner() }
        setHardwareInteractionEnabled(true)
    }

    private var effectiveCameraType: CameraType {
        #if targetEnvironment(macCatalyst)
        return .front
        #else
        return configuration.cameraType
        #endif
    }

    private func applyConfiguration(previous: CameraConfiguration?) {
        let current = configuration
        focusInterfaceView.update(focusMode: current.focusMode)
        focusInterfaceView.update(resetFocusTimeout: current.resetFocusTimeout)
        focusInterfaceView.update(resetFocusWhenMotionDetected: current.resetFocusWhenMotionDetected)
        updateZoomGesture()
        updateRatioOverlay()
        scannerInterfaceView.isHidden = !current.showFrame
        scannerInterfaceView.update(frameColor: current.frameColor)
        scannerInterfaceView.update(laserColor: current.laserColor)
        scannerInterfaceView.update(frameSize: current.barcodeFrameSize ?? CGSize(width: 300, height: 150))
        if current.showFrame && isRunning {
            scannerInterfaceView.startAnimatingScanner()
        } else {
            scannerInterfaceView.stopAnimatingScanner()
        }
        setNeedsLayout()
        guard hasCameraBeenSetup else { return }
        if let previous, previous.cameraType != current.cameraType {
            camera.update(cameraType: effectiveCameraType)
        }
        if previous?.flashMode != current.flashMode { camera.update(flashMode: current.flashMode) }
        if previous?.torchMode != current.torchMode || previous?.cameraType != current.cameraType {
            camera.update(torchMode: current.torchMode)
        }
        if previous?.resizeMode != current.resizeMode { camera.update(resizeMode: current.resizeMode) }
        if previous?.maxPhotoQualityPrioritization != current.maxPhotoQualityPrioritization {
            camera.update(maxPhotoQualityPrioritization: current.maxPhotoQualityPrioritization)
        }
        if previous == nil || previous?.maxZoom != current.maxZoom { camera.update(maxZoom: current.maxZoom) }
        if previous == nil || previous?.zoom != current.zoom { camera.update(zoom: current.zoom) }
        if previous?.iOsDeferredStart != current.iOsDeferredStart {
            camera.update(iOsDeferredStartEnabled: current.iOsDeferredStart)
        }
        if previous?.faceDetectionThrottleMs != current.faceDetectionThrottleMs {
            camera.update(faceDetectionThrottleMs: current.faceDetectionThrottleMs)
        }
        if previous?.scanBarcode != current.scanBarcode || previous?.allowedBarcodeTypes != current.allowedBarcodeTypes {
            updateBarcodeDetection()
        }
        if previous?.faceDetectionEnabled != current.faceDetectionEnabled { updateFaceDetection() }
        updateScanRegion()
    }

    private func updateBarcodeDetection() {
        guard hasCameraBeenSetup else { return }
        camera.isBarcodeScannerEnabled(
            configuration.scanBarcode,
            supportedBarcodeTypes: configuration.supportedBarcodeTypes,
            onBarcodeRead: { [weak self] value, format in
                DispatchQueue.main.async { self?.receiveBarcode(value, format: format) }
            }
        )
    }

    func receiveBarcode(_ value: String, format: CodeFormat) {
        guard isRunning, configuration.scanBarcode, onReadCode != nil,
            scanThrottle.shouldEmit(at: ProcessInfo.processInfo.systemUptime, delayMilliseconds: configuration.scanThrottleDelay)
        else { return }
        onReadCode?(Barcode(codeStringValue: value, codeFormat: format))
    }

    private func updateFaceDetection() {
        guard hasCameraBeenSetup else { return }
        camera.isFaceDetectionEnabled(configuration.faceDetectionEnabled, onFaceDetected: { [weak self] faces in
            DispatchQueue.main.async {
                guard let self, self.isRunning, self.configuration.faceDetectionEnabled else { return }
                self.onFaceDetected?(faces)
            }
        })
    }

    private func updateScanRegion() {
        guard hasCameraBeenSetup else { return }
        camera.update(scannerFrameSize: configuration.showFrame ? scannerInterfaceView.frameSize : nil)
    }

    private func updateRatioOverlay() {
        guard let ratio = configuration.ratioOverlay else {
            ratioOverlayView?.removeFromSuperview()
            ratioOverlayView = nil
            return
        }
        if let ratioOverlayView {
            ratioOverlayView.setRatio(ratio)
            ratioOverlayView.setColor(configuration.ratioOverlayColor ?? .black.withAlphaComponent(0.3))
        } else {
            let overlay = RatioOverlayView(frame: bounds, ratioString: ratio, overlayColor: configuration.ratioOverlayColor)
            addSubview(overlay)
            ratioOverlayView = overlay
        }
    }

    private func updateZoomGesture() {
        if configuration.zoomMode == .on, zoomGestureRecognizer == nil {
            let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            addGestureRecognizer(gesture)
            zoomGestureRecognizer = gesture
        } else if configuration.zoomMode == .off, let zoomGestureRecognizer {
            removeGestureRecognizer(zoomGestureRecognizer)
            self.zoomGestureRecognizer = nil
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isRunning else { return }
        if gesture.state == .began { camera.zoomPinchStart() }
        if gesture.state == .changed { camera.zoomPinchChange(pinchScale: gesture.scale) }
    }

    private func configureHardwareInteraction() {
        #if !targetEnvironment(macCatalyst)
        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard let self, self.isRunning else { return }
            switch event.phase {
            case .began: self.onCaptureButtonPressIn?()
            case .ended: self.onCaptureButtonPressOut?()
            case .cancelled: break
            @unknown default: break
            }
        }
        interaction.isEnabled = false
        addInteraction(interaction)
        hardwareInteraction = interaction
        #endif
    }

    private func setHardwareInteractionEnabled(_ enabled: Bool) {
        #if !targetEnvironment(macCatalyst)
        (hardwareInteraction as? AVCaptureEventInteraction)?.isEnabled = enabled
        #endif
    }
}

enum CapturedPhotoWriter {
    static func write(_ data: Data, dimensions: CMVideoDimensions) throws -> CapturedPhoto {
        do {
            var directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            if let bundleID = Bundle.main.bundleIdentifier {
                directory.appendPathComponent(bundleID, isDirectory: true)
            }
            directory.appendPathComponent("com.tesla.react-native-camera-kit", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            try data.write(to: url, options: .atomic)
            return CapturedPhoto(url: url, size: data.count, width: Int(dimensions.width), height: Int(dimensions.height))
        } catch {
            throw CameraError.fileWriteFailed(error.localizedDescription)
        }
    }
}
