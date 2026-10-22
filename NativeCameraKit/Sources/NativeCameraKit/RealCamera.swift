import AVFoundation
import CoreMotion
import ImageIO
import UIKit

/// Session, device, and output state belong to sessionQueue. Preview and client callbacks use main.
final class RealCamera: NSObject, CameraProtocol, AVCaptureMetadataOutputObjectsDelegate,
                        AVCaptureVideoDataOutputSampleBufferDelegate {
    var previewView: UIView { cameraPreview }
    var onError: ((String) -> Void)?

    private let cameraPreview = RealPreviewView(frame: .zero)
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "NativeCameraKit.session")
    private let visionQueue = DispatchQueue(label: "NativeCameraKit.vision")
    private let photoOutput = AVCapturePhotoOutput()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let faceDetector = FaceDetector()
    private var input: AVCaptureDeviceInput?
    private var setupResult: SetupResult = .notStarted
    private var wantsRunning = false
    private var videoDataAttached = false
    private var flashMode: FlashMode = .auto
    private var torchMode: TorchMode = .off
    private var quality: MaxPhotoQualityPrioritization = .balanced
    private var deferredStartEnabled = true
    private var zoom: Double?
    private var maxZoom: Double?
    private var zoomStartedAt = 1.0
    private var lastZoom: Double?
    private var onZoom: ((Double) -> Void)?
    private var onOrientationChange: ((Orientation) -> Void)?
    private var onBarcodeRead: ((String, CodeFormat) -> Void)?
    private var barcodeEnabled = false
    private var barcodeFormats: [CodeFormat] = []
    private var faceDetectionEnabled = false
    private var resetFocus: (() -> Void)?
    private var focusFinished: (() -> Void)?
    private var deviceOrientation: UIDeviceOrientation = .portrait
    private var interfaceOrientation: Orientation = .portrait
    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var focusObservation: NSKeyValueObservation?
    private var subjectObserver: NSObjectProtocol?
    private var sessionObservers: [NSObjectProtocol] = []

    // Main queue state.
    private var onFaceDetected: (([FaceDetectionPayload]) -> Void)?
    private var scannerFrame: CGRect?
    private var orientationObserver: NSObjectProtocol?
    private var motionSubscription: UUID?

    // Vision queue state.
    private var visionOrientation: CGImagePropertyOrientation = .right

    override init() {
        super.init()
        // Assign before any session work starts: assigning a preview session changes its connections.
        cameraPreview.session = session
        cameraPreview.previewLayer.videoGravity = .resizeAspect
        let center = NotificationCenter.default
        sessionObservers = [
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in self?.handleRuntimeError(notification)
            },
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in
                    self?.cancelCaptures(message: "The camera session was interrupted.")
                    self?.report("The camera session was interrupted.")
                }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
                self?.sessionQueue.async { [weak self] in self?.startSessionIfNeeded() }
            }
        ]
    }

    deinit {
        sessionObservers.forEach(NotificationCenter.default.removeObserver)
        if let subjectObserver { NotificationCenter.default.removeObserver(subjectObserver) }
        let orientationObserver = orientationObserver
        let motionSubscription = motionSubscription
        DispatchQueue.main.async {
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            if let motionSubscription { MotionOrientationSource.shared.remove(motionSubscription) }
        }
        captureDelegates.values.forEach { $0.cancel(message: "The camera was released before capture completed.") }
        focusObservation?.invalidate()
        let session = session
        sessionQueue.async { if session.isRunning { session.stopRunning() } }
    }

    func setup(cameraType: CameraType, supportedBarcodeType: [CodeFormat]) {
        sessionQueue.async {
            guard self.setupResult != .success else { return }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                self.setupResult = .cameraNotAuthorized
                self.report("Camera access is not authorized.")
                return
            }
            self.barcodeFormats = supportedBarcodeType
            self.setupResult = self.configureSession(cameraType: cameraType)
            guard self.setupResult == .success else {
                self.report("The camera session could not be configured.")
                return
            }
            self.observeFocus()
            self.applyBarcodeConfiguration()
            self.applyFaceDetectionConfiguration()
            self.startSessionIfNeeded()
            DispatchQueue.main.async { self.updatePreviewOrientation() }
        }
    }

    func start() {
        startOrientationUpdates()
        sessionQueue.async { self.wantsRunning = true; self.startSessionIfNeeded() }
    }

    func stop() {
        stopOrientationUpdates()
        sessionQueue.async {
            self.wantsRunning = false
            self.cancelCaptures(message: "The camera stopped before capture completed.")
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func cameraRemovedFromSuperview() { stop() }

    private func startSessionIfNeeded() {
        guard wantsRunning, setupResult == .success, !session.isRunning, !session.isInterrupted else { return }
        session.startRunning()
        if let device = input?.device { configure(device) { self.applyTorch(device) } }
        if !session.isRunning { report("The camera session could not start.") }
        DispatchQueue.main.async { self.updatePreviewOrientation() }
    }

    func update(onOrientationChange: ((Orientation) -> Void)?) {
        sessionQueue.async { self.onOrientationChange = onOrientationChange }
    }

    func update(onZoom: ((Double) -> Void)?) { sessionQueue.async { self.onZoom = onZoom } }

    func update(flashMode: FlashMode) { sessionQueue.async { self.flashMode = flashMode } }

    func update(torchMode: TorchMode) {
        sessionQueue.async {
            self.torchMode = torchMode
            guard let device = self.input?.device else { return }
            self.configure(device) { self.applyTorch(device) }
        }
    }

    func update(maxPhotoQualityPrioritization: MaxPhotoQualityPrioritization?) {
        sessionQueue.async {
            let quality = maxPhotoQualityPrioritization ?? .balanced
            guard quality != self.quality else { return }
            self.quality = quality
            self.cancelCaptures(message: "Photo quality changed before capture completed.")
            self.session.beginConfiguration()
            self.photoOutput.maxPhotoQualityPrioritization = self.quality.avQualityPrioritization
            self.session.commitConfiguration()
        }
    }

    func update(iOsDeferredStartEnabled: Bool?) {
        sessionQueue.async {
            self.deferredStartEnabled = iOsDeferredStartEnabled ?? true
            self.applyDeferredStart()
        }
    }

    func update(resizeMode: ResizeMode) {
        cameraPreview.previewLayer.videoGravity = resizeMode == .cover ? .resizeAspectFill : .resizeAspect
        applyScannerFrame()
    }

    func update(cameraType: CameraType) {
        sessionQueue.async {
            guard self.setupResult == .success, let oldInput = self.input,
                  oldInput.device.position != cameraType.avPosition else { return }
            guard let device = self.bestDevice(for: cameraType),
                  let newInput = try? AVCaptureDeviceInput(device: device) else {
                self.report("The selected camera is not available.")
                return
            }
            self.cancelCaptures(message: "The selected camera changed before capture completed.")
            self.session.beginConfiguration()
            self.session.removeInput(oldInput)
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
            } else {
                self.session.addInput(oldInput)
                self.report("The selected camera could not be connected.")
            }
            self.session.commitConfiguration()
            self.observeFocus()
            self.updateVisionOrientation()
            if let currentDevice = self.input?.device { self.resetZoom(currentDevice) }
            self.applyBarcodeConfiguration()
            DispatchQueue.main.async { self.updatePreviewOrientation() }
        }
    }

    func update(zoom: Double?) {
        sessionQueue.async {
            self.zoom = zoom.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            guard let device = self.input?.device, let desired = self.zoom else { return }
            self.setZoom(self.validZoom(desired, for: device), on: device)
        }
    }

    func update(maxZoom: Double?) {
        sessionQueue.async {
            self.maxZoom = maxZoom.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            guard let device = self.input?.device else { return }
            self.setZoom(self.validZoom(self.zoom ?? self.normalizedZoom(device), for: device), on: device)
        }
    }

    func zoomPinchStart() {
        sessionQueue.async { if let device = self.input?.device { self.zoomStartedAt = self.normalizedZoom(device) } }
    }

    func zoomPinchChange(pinchScale: CGFloat) {
        guard pinchScale.isFinite, pinchScale > 0 else { return }
        sessionQueue.async {
            guard let device = self.input?.device else { return }
            let desired = self.validZoom(self.zoomStartedAt * pinchScale, for: device)
            guard desired != self.normalizedZoom(device) else { return }
            if self.zoom == nil { self.setZoom(desired, on: device) }
            self.emitZoom(desired)
        }
    }

    func focus(at touchPoint: CGPoint, focusBehavior: FocusBehavior) {
        let devicePoint = cameraPreview.previewLayer.captureDevicePointConverted(fromLayerPoint: touchPoint)
        sessionQueue.async {
            guard let device = self.input?.device else { return }
            if case .customFocus(_, let reset, let finished) = focusBehavior {
                self.resetFocus = reset
                self.focusFinished = finished
            } else {
                self.resetFocus = nil
                self.focusFinished = nil
            }
            self.configure(device) {
                self.applyTorch(device)
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusBehavior.avFocusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusBehavior.avFocusMode
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(focusBehavior.exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = focusBehavior.exposureMode
                }
                device.isSubjectAreaChangeMonitoringEnabled = focusBehavior.isSubjectAreaChangeMonitoringEnabled
            }
        }
    }

    func capturePicture(onWillCapture: @escaping () -> Void,
                        onSuccess: @escaping (Data, Data?, CMVideoDimensions) -> Void,
                        onError: @escaping (String) -> Void) {
        sessionQueue.async {
            guard self.captureDelegates.isEmpty else {
                DispatchQueue.main.async { onError("A photo capture is already in progress.") }
                return
            }
            guard self.setupResult == .success, self.wantsRunning, self.session.isRunning,
                  !self.session.isInterrupted,
                  let connection = self.photoOutput.connection(with: .video), connection.isEnabled else {
                DispatchQueue.main.async { onError("The camera is not ready to capture a photo.") }
                return
            }
            if connection.isVideoRotationAngleSupported(self.captureRotationAngle) {
                connection.videoRotationAngle = self.captureRotationAngle
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
            if self.input?.device.isFlashAvailable == true,
               self.photoOutput.supportedFlashModes.contains(self.flashMode.avFlashMode) {
                settings.flashMode = self.flashMode.avFlashMode
            }
            if let pixelFormat = settings.availablePreviewPhotoPixelFormatTypes.first {
                settings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                                               kCVPixelBufferWidthKey as String: 160,
                                               kCVPixelBufferHeightKey as String: 160]
            }
            let delegate = PhotoCaptureDelegate(with: settings, onWillCapture: onWillCapture,
                onCaptureSuccess: { _, data, thumbnail, dimensions in
                    onSuccess(data, thumbnail, dimensions)
                }, onCaptureError: { _, message in
                    onError(message)
                }, onFinished: { [weak self] id in
                    self?.sessionQueue.async { [weak self] in self?.captureDelegates[id] = nil }
                })
            self.captureDelegates[settings.uniqueID] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func cancelCaptures(message: String) {
        captureDelegates.values.forEach { $0.cancel(message: message) }
        // Keep delegates alive until AVFoundation ends their capture transactions.
    }

    func isBarcodeScannerEnabled(_ isEnabled: Bool, supportedBarcodeTypes: [CodeFormat],
                                 onBarcodeRead: ((String, CodeFormat) -> Void)?) {
        sessionQueue.async {
            self.barcodeEnabled = isEnabled
            self.barcodeFormats = supportedBarcodeTypes
            self.onBarcodeRead = onBarcodeRead
            self.applyBarcodeConfiguration()
        }
    }

    private func applyBarcodeConfiguration() {
        guard setupResult == .success else { return }
        let available = metadataOutput.availableMetadataObjectTypes
        let requested = barcodeFormats.map { $0.toAVMetadataObjectType() }
        metadataOutput.metadataObjectTypes = barcodeEnabled ? Array(Set(requested.filter(available.contains))) : []
    }

    func update(barcodeFrameSize: CGSize?) {
        // The public view uses this size to calculate scannerFrameSize.
    }

    func update(scannerFrameSize: CGRect?) {
        scannerFrame = scannerFrameSize
        applyScannerFrame()
    }

    private func applyScannerFrame() {
        let region: CGRect
        if let scannerFrame, !scannerFrame.isEmpty, cameraPreview.bounds.width > 0, cameraPreview.bounds.height > 0 {
            region = cameraPreview.previewLayer.metadataOutputRectConverted(fromLayerRect: scannerFrame)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        } else {
            region = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        guard !region.isNull, region.origin.x.isFinite, region.origin.y.isFinite,
              region.width.isFinite, region.height.isFinite else { return }
        sessionQueue.async { self.metadataOutput.rectOfInterest = region }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard barcodeEnabled, let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = code.stringValue, let callback = onBarcodeRead else { return }
        let format = CodeFormat.fromAVMetadataObjectType(code.type)
        DispatchQueue.main.async { callback(value, format) }
    }

    func isFaceDetectionEnabled(_ isEnabled: Bool, onFaceDetected: (([FaceDetectionPayload]) -> Void)?) {
        self.onFaceDetected = isEnabled ? onFaceDetected : nil
        sessionQueue.async {
            self.faceDetectionEnabled = isEnabled && onFaceDetected != nil
            self.applyFaceDetectionConfiguration()
        }
    }

    func update(faceDetectionThrottleMs: Int) {
        visionQueue.async { self.faceDetector.update(throttleMs: faceDetectionThrottleMs) }
    }

    private func applyFaceDetectionConfiguration() {
        guard setupResult == .success, faceDetectionEnabled != videoDataAttached else { return }
        cancelCaptures(message: "Face detection changed before capture completed.")
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if faceDetectionEnabled {
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if session.canAddOutput(videoDataOutput) {
                session.addOutput(videoDataOutput)
                if let connection = videoDataOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                }
                videoDataOutput.setSampleBufferDelegate(self, queue: visionQueue)
                videoDataAttached = true
            } else {
                report("Face detection is not available for this camera configuration.")
            }
        } else {
            videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(videoDataOutput)
            videoDataAttached = false
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let faces = faceDetector.process(pixelBuffer: pixelBuffer, orientation: visionOrientation) else { return }
        DispatchQueue.main.async {
            let layer = self.cameraPreview.previewLayer
            let size = layer.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let frame = layer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            guard frame.width > 0, frame.height > 0 else { return }
            let converted = faces.map { face in
                FaceDetectionPayload(id: face.id, yaw: face.yaw, pitch: face.pitch, roll: face.roll,
                    boundsX: (frame.minX + face.boundsX * frame.width) / size.width,
                    boundsY: (frame.minY + face.boundsY * frame.height) / size.height,
                    boundsWidth: face.boundsWidth * frame.width / size.width,
                    boundsHeight: face.boundsHeight * frame.height / size.height)
            }
            self.onFaceDetected?(converted)
        }
    }

    private func configureSession(cameraType: CameraType) -> SetupResult {
        guard let device = bestDevice(for: cameraType), let input = try? AVCaptureDeviceInput(device: device) else {
            return .sessionConfigurationFailed
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { return .sessionConfigurationFailed }
        session.addInput(input)
        self.input = input
        guard session.canAddOutput(photoOutput), session.canAddOutput(metadataOutput) else {
            session.removeInput(input)
            self.input = nil
            return .sessionConfigurationFailed
        }
        session.addOutput(photoOutput)
        session.addOutput(metadataOutput)
        photoOutput.maxPhotoQualityPrioritization = quality.avQualityPrioritization
        metadataOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)
        metadataOutput.metadataObjectTypes = []
        applyDeferredStart()
        resetZoom(device)
        updateVisionOrientation()
        return .success
    }

    private func bestDevice(for type: CameraType) -> AVCaptureDevice? {
        for deviceType: AVCaptureDevice.DeviceType in [.builtInTripleCamera, .builtInDualWideCamera,
                                                       .builtInDualCamera, .builtInWideAngleCamera] {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: type.avPosition) { return device }
        }
        return nil
    }

    private func applyDeferredStart() {
        if #available(iOS 26.0, *) {
            if photoOutput.isDeferredStartSupported { photoOutput.isDeferredStartEnabled = deferredStartEnabled }
            if metadataOutput.isDeferredStartSupported { metadataOutput.isDeferredStartEnabled = deferredStartEnabled }
        }
    }

    private func defaultZoom(_ device: AVCaptureDevice) -> Double {
        guard let index = device.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }),
              index > 0, index - 1 < device.virtualDeviceSwitchOverVideoZoomFactors.count else { return 1 }
        return device.virtualDeviceSwitchOverVideoZoomFactors[index - 1].doubleValue
    }

    private func normalizedZoom(_ device: AVCaptureDevice) -> Double { device.videoZoomFactor / defaultZoom(device) }
    private func validZoom(_ value: Double, for device: AVCaptureDevice) -> Double {
        let base = defaultZoom(device)
        let minimum = device.minAvailableVideoZoomFactor / base
        let maximum = min(device.maxAvailableVideoZoomFactor / base, maxZoom ?? .greatestFiniteMagnitude)
        return max(minimum, min(value, maximum))
    }

    private func setZoom(_ value: Double, on device: AVCaptureDevice) {
        configure(device) { self.applyTorch(device); device.videoZoomFactor = value * self.defaultZoom(device) }
    }

    private func resetZoom(_ device: AVCaptureDevice) {
        let value = validZoom(zoom ?? 1, for: device)
        setZoom(value, on: device)
        emitZoom(value)
    }

    private func emitZoom(_ value: Double) {
        guard value != lastZoom else { return }
        lastZoom = value
        if let callback = onZoom { DispatchQueue.main.async { callback(value) } }
    }

    private func applyTorch(_ device: AVCaptureDevice) {
        if device.hasTorch && device.isTorchModeSupported(torchMode.avTorchMode) { device.torchMode = torchMode.avTorchMode }
    }

    private func configure(_ device: AVCaptureDevice, changes: () -> Void) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            changes()
        } catch { report(error.localizedDescription) }
    }

    private func observeFocus() {
        focusObservation?.invalidate()
        if let subjectObserver { NotificationCenter.default.removeObserver(subjectObserver) }
        focusObservation = input?.device.observe(\.isAdjustingFocus, options: .new) { [weak self] _, change in
            guard change.newValue == false else { return }
            self?.sessionQueue.async { [weak self] in
                if let finished = self?.focusFinished { DispatchQueue.main.async(execute: finished) }
            }
        }
        subjectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: input?.device, queue: nil
        ) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in
                if let reset = self?.resetFocus { DispatchQueue.main.async(execute: reset) }
            }
        }
    }

    private func handleRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
        sessionQueue.async {
            self.cancelCaptures(message: error?.localizedDescription ?? "The camera session failed.")
            self.report(error?.localizedDescription ?? "The camera session failed.")
            if error?.code == .mediaServicesWereReset { self.startSessionIfNeeded() }
        }
    }

    private func report(_ message: String) { DispatchQueue.main.async { self.onError?(message) } }

    private var captureRotationAngle: CGFloat {
        switch deviceOrientation {
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }

    private func updateVisionOrientation() {
        let front = input?.device.position == .front
        let orientation: CGImagePropertyOrientation
        switch interfaceOrientation {
        case .landscapeRight: orientation = front ? .downMirrored : .up
        case .landscapeLeft: orientation = front ? .upMirrored : .down
        case .portraitUpsideDown: orientation = front ? .rightMirrored : .left
        case .portrait: orientation = front ? .leftMirrored : .right
        }
        visionQueue.async { self.visionOrientation = orientation }
    }

    private func updatePreviewOrientation() {
        let orientation = Orientation(from: cameraPreview.window?.windowScene?.interfaceOrientation ?? .portrait) ?? .portrait
        let connection = cameraPreview.previewLayer.connection
        sessionQueue.async {
            if connection?.isVideoRotationAngleSupported(orientation.videoRotationAngle) == true {
                connection?.videoRotationAngle = orientation.videoRotationAngle
            }
            self.interfaceOrientation = orientation
            self.updateVisionOrientation()
            DispatchQueue.main.async { self.applyScannerFrame() }
        }
    }

    private func startOrientationUpdates() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: UIDevice.current, queue: .main
        ) { [weak self] _ in self?.updatePreviewOrientation() }
        updatePreviewOrientation()
        motionSubscription = MotionOrientationSource.shared.add { [weak self] orientation in
            self?.sessionQueue.async { [weak self] in
                guard let self, self.deviceOrientation != orientation else { return }
                self.deviceOrientation = orientation
                if let event = Orientation(from: orientation), let callback = self.onOrientationChange {
                    DispatchQueue.main.async { callback(event) }
                }
            }
        }
    }

    private func stopOrientationUpdates() {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
            self.orientationObserver = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        if let motionSubscription { MotionOrientationSource.shared.remove(motionSubscription); self.motionSubscription = nil }
    }
}

/// One retained motion manager avoids CoreMotion teardown races and supports multiple camera views.
private final class MotionOrientationSource {
    static let shared = MotionOrientationSource()
    private let manager = CMMotionManager()
    private var callbacks: [UUID: (UIDeviceOrientation) -> Void] = [:]

    func add(_ callback: @escaping (UIDeviceOrientation) -> Void) -> UUID {
        let id = UUID()
        callbacks[id] = callback
        if callbacks.count == 1, manager.isAccelerometerAvailable {
            manager.accelerometerUpdateInterval = 0.2
            manager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                let acceleration = data.acceleration
                let orientation: UIDeviceOrientation
                if acceleration.x >= 0.75 { orientation = .landscapeRight }
                else if acceleration.x <= -0.75 { orientation = .landscapeLeft }
                else if acceleration.y <= -0.75 { orientation = .portrait }
                else if acceleration.y >= 0.75 { orientation = .portraitUpsideDown }
                else { return }
                self?.callbacks.values.forEach { $0(orientation) }
            }
        }
        return id
    }

    func remove(_ id: UUID) {
        callbacks[id] = nil
        if callbacks.isEmpty { manager.stopAccelerometerUpdates() }
    }
}
