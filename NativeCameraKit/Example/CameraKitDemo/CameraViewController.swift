import AudioToolbox
import NativeCameraKit
import UIKit

final class CameraViewController: UIViewController {
    enum Mode { case photo, scanner }

    private let mode: Mode
    private let stress: Bool
    private let camera = CameraView()
    private let faceOverlay = FaceOverlayView()
    private let faceStatsLabel = UILabel()
    private let statusLabel = UILabel()
    private let zoomLabel = UILabel()
    private let zoomSlider = UISlider()
    private let captureButton = UIButton(type: .system)
    private let photoButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private var toolbarButtons: [UIButton] = []
    private var photos: [CapturedPhoto] = []
    private var isCapturing = false
    private var zoomTimer: Timer?
    private var barcodeTimer: Timer?
    private var captureTask: Task<Void, Never>?
    private var photoOrientation = Orientation.portrait
    private var rotatingViews: [UIView] = []
    private var followsPhotoZoomEvents = true

    init(mode: Mode = .photo, stress: Bool = false) {
        self.mode = mode
        self.stress = stress
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        zoomTimer?.invalidate()
        barcodeTimer?.invalidate()
        captureTask?.cancel()
    }

    override var prefersStatusBarHidden: Bool { mode == .scanner }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.overrideUserInterfaceStyle = .dark
        title = mode == .photo ? "Camera" : "Barcode Scanner"
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = .black
        navigationAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = navigationAppearance
        navigationItem.scrollEdgeAppearance = navigationAppearance

        var configuration = camera.configuration
        configuration.resetFocusWhenMotionDetected = true
        if mode == .scanner {
            configuration.scanBarcode = true
            configuration.showFrame = true
            configuration.allowedBarcodeTypes = [.qr, .ean13]
            configuration.barcodeFrameSize = CGSize(width: 300, height: 150)
        } else {
            configuration.maxZoom = 10
            configuration.maxPhotoQualityPrioritization = .speed
            configuration.faceDetectionThrottleMs = 50
        }
        camera.configuration = configuration

        let toolbar = UIStackView()
        toolbar.axis = .horizontal
        toolbar.distribution = .equalSpacing
        toolbarButtons = [
            button("Flash: Auto", symbol: "bolt.badge.a", id: "flash", action: #selector(cycleFlash)),
            button("Switch camera", symbol: "arrow.triangle.2.circlepath.camera", id: "switch-camera", action: #selector(switchCamera)),
            button("Torch: Off", symbol: "flashlight.off.fill", id: "torch", action: #selector(toggleTorch)),
            button("Face detection", symbol: "face.dashed", id: "faces", action: #selector(toggleFaces)),
            button("Barcode scanning", symbol: "barcode.viewfinder", id: "scan", action: #selector(toggleScanning)),
            button("Camera settings", symbol: "slider.horizontal.3", id: "settings", action: #selector(showSettings))
        ]
        for (index, button) in toolbarButtons.enumerated() where mode == .photo || (index != 3 && index != 4) {
            toolbar.addArrangedSubview(button)
        }
        let preview = makePreview()
        camera.accessibilityIdentifier = "camera-preview"

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 3
        statusLabel.textAlignment = .center
        statusLabel.accessibilityIdentifier = "camera-status"
        #if targetEnvironment(simulator)
        statusLabel.text = "Simulator: test photo only. Scanning and faces require a device."
        #else
        statusLabel.text = "Tap to focus. Pinch to zoom."
        #endif
        if mode == .scanner { statusLabel.text = "Scan a QR or EAN-13 code inside the frame." }

        zoomSlider.minimumValue = 0.5
        zoomSlider.maximumValue = 10
        zoomSlider.value = 1
        zoomSlider.accessibilityLabel = "Zoom"
        zoomSlider.addTarget(self, action: #selector(changeZoom), for: .valueChanged)
        zoomLabel.text = "1.0×"
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        zoomLabel.textColor = .white
        zoomLabel.setContentHuggingPriority(.required, for: .horizontal)
        let resetButton = UIButton(type: .system)
        resetButton.setTitle("1×", for: .normal)
        resetButton.accessibilityLabel = "Reset zoom"
        resetButton.accessibilityIdentifier = "reset-zoom"
        resetButton.addTarget(self, action: #selector(resetZoom), for: .touchUpInside)
        rotatingViews = toolbarButtons.compactMap(\.imageView) + [zoomLabel]
        if let titleLabel = resetButton.titleLabel { rotatingViews.append(titleLabel) }
        let zoomRow = UIStackView(arrangedSubviews: [resetButton, zoomSlider, zoomLabel])
        zoomRow.spacing = 12

        let bottom = makeCaptureControls()

        let content = mode == .photo ? [toolbar, preview, statusLabel, zoomRow, bottom] : [toolbar, preview, statusLabel]
        let stack = UIStackView(arrangedSubviews: content)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            zoomRow.heightAnchor.constraint(equalToConstant: 32)
        ])
        connectEvents()
        updateControls()
    }

    private func makeCaptureControls() -> UIView {
        captureButton.setImage(UIImage(systemName: "circle.inset.filled"), for: .normal)
        captureButton.setPreferredSymbolConfiguration(.init(pointSize: 66), forImageIn: .normal)
        captureButton.tintColor = .white
        captureButton.accessibilityLabel = "Take five photos"
        captureButton.accessibilityIdentifier = "capture"
        captureButton.addTarget(self, action: #selector(capture), for: .touchUpInside)
        captureButton.widthAnchor.constraint(equalToConstant: 80).isActive = true
        captureButton.heightAnchor.constraint(equalToConstant: 80).isActive = true

        photoButton.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
        photoButton.tintColor = .white
        photoButton.isEnabled = false
        photoButton.accessibilityLabel = "Show latest photo"
        photoButton.accessibilityIdentifier = "latest-photo"
        photoButton.addTarget(self, action: #selector(showPhoto), for: .touchUpInside)
        photoButton.imageView?.contentMode = .scaleAspectFill
        photoButton.clipsToBounds = true
        photoButton.layer.cornerRadius = 8
        photoButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        photoButton.heightAnchor.constraint(equalToConstant: 52).isActive = true

        countLabel.text = "0 photos"
        countLabel.textColor = .white
        countLabel.font = .preferredFont(forTextStyle: .caption1)
        countLabel.textAlignment = .right
        countLabel.accessibilityIdentifier = "capture-count"

        let bottom = UIView()
        [photoButton, captureButton, countLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            bottom.addSubview($0)
        }
        NSLayoutConstraint.activate([
            bottom.heightAnchor.constraint(equalToConstant: 88),
            captureButton.centerXAnchor.constraint(equalTo: bottom.centerXAnchor),
            captureButton.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            photoButton.leadingAnchor.constraint(equalTo: bottom.leadingAnchor),
            photoButton.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: bottom.trailingAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: captureButton.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: bottom.centerYAnchor)
        ])

        return bottom
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        camera.start()
        if stress, zoomTimer == nil {
            zoomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, zoomTimer?.isValid == true else { return }
                    camera.configuration.zoom = Double.random(in: 0..<10)
                    updateControls()
                }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        camera.stop()
        zoomTimer?.invalidate()
        zoomTimer = nil
        barcodeTimer?.invalidate()
        captureTask?.cancel()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.rotateCameraIcons(animated: false)
        }, completion: { [weak self] _ in
            self?.rotateCameraIcons(animated: false)
        })
    }

    private func rotateCameraIcons(animated: Bool) {
        guard mode == .photo else { return }
        let rotation = Self.iconRotation(
            for: photoOrientation,
            interfaceOrientation: view.window?.windowScene?.interfaceOrientation ?? .portrait
        )
        let updates = { [self] in
            rotatingViews.forEach { $0.transform = CGAffineTransform(rotationAngle: rotation) }
        }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: updates)
        } else {
            updates()
        }
    }

    static func iconRotation(for orientation: Orientation, interfaceOrientation: UIInterfaceOrientation) -> CGFloat {
        let photoAngle: CGFloat
        switch orientation {
        case .portrait: photoAngle = 0
        case .landscapeLeft: photoAngle = .pi / 2
        case .portraitUpsideDown: photoAngle = .pi
        case .landscapeRight: photoAngle = -.pi / 2
        }
        // Interface landscape names use the opposite direction from device orientations.
        let interfaceAngle: CGFloat
        switch interfaceOrientation {
        case .landscapeRight: interfaceAngle = .pi / 2
        case .portraitUpsideDown: interfaceAngle = .pi
        case .landscapeLeft: interfaceAngle = -.pi / 2
        default: interfaceAngle = 0
        }
        return atan2(sin(photoAngle - interfaceAngle), cos(photoAngle - interfaceAngle))
    }

    private func makePreview() -> UIView {
        let container = UIView()
        let surface = UIView()
        surface.clipsToBounds = true
        surface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)
        if mode == .scanner {
            let width = surface.widthAnchor.constraint(equalTo: container.widthAnchor)
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                surface.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                surface.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                surface.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
                surface.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor),
                surface.heightAnchor.constraint(equalTo: surface.widthAnchor, multiplier: 4 / 3),
                width
            ])
        } else {
            pin(surface, to: container)
        }
        for overlay in [camera, faceOverlay] {
            surface.addSubview(overlay)
            pin(overlay, to: surface)
        }
        faceStatsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        faceStatsLabel.textColor = .white
        faceStatsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        faceStatsLabel.numberOfLines = 0
        faceStatsLabel.isUserInteractionEnabled = false
        faceStatsLabel.accessibilityIdentifier = "face-statistics"
        faceStatsLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(faceStatsLabel)
        NSLayoutConstraint.activate([
            faceStatsLabel.topAnchor.constraint(equalTo: surface.topAnchor, constant: 10),
            faceStatsLabel.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12),
            faceStatsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: surface.leadingAnchor, constant: 12)
        ])
        updateFaces([])
        return container
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    private func connectEvents() {
        camera.onReadCode = { [weak self] barcode in
            guard let self else { return }
            statusLabel.text = "\(barcode.codeFormat.rawValue): \(barcode.codeStringValue)"
            if mode == .scanner {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                barcodeTimer?.invalidate()
                barcodeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                    self?.statusLabel.text = "Scan a QR or EAN-13 code inside the frame."
                }
            }
        }
        camera.onFaceDetected = { [weak self] faces in
            self?.updateFaces(faces)
        }
        camera.onZoom = { [weak self] zoom in
            guard let self else { return }
            zoomSlider.value = Float(zoom)
            zoomLabel.text = String(format: "%.1f×", zoom)
            if (mode == .photo && followsPhotoZoomEvents) || camera.configuration.zoom != nil {
                camera.configuration.zoom = zoom
            }
        }
        camera.onOrientationChange = { [weak self] orientation in
            guard let self else { return }
            photoOrientation = orientation
            captureButton.accessibilityHint = "Photo orientation: \(orientation)"
            rotateCameraIcons(animated: true)
        }
        camera.onCaptureButtonPressIn = { [weak self] in
            self?.captureButton.alpha = 0.5
        }
        camera.onCaptureButtonPressOut = { [weak self] in
            self?.captureButton.alpha = 1
            self?.capture()
        }
        camera.onError = { [weak self] error in
            self?.statusLabel.text = error.localizedDescription
        }
    }

    private func updateFaces(_ faces: [FaceDetectionPayload]) {
        faceOverlay.faces = faces
        var lines = ["Faces: \(faces.count)"]
        if let face = faces.first {
            lines.append(String(format: "Yaw: %.1f°\nPitch: %.1f°\nRoll: %.1f°", face.yaw, face.pitch, face.roll))
            lines.append("Facing: \(FaceOverlayView.isFacingCamera(face) ? "yes" : "no")")
            lines.append(String(format: "Box: %.2f,%.2f %.2f×%.2f", face.boundsX, face.boundsY, face.boundsWidth, face.boundsHeight))
        }
        faceStatsLabel.text = lines.joined(separator: "\n")
        faceStatsLabel.isHidden = !camera.configuration.faceDetectionEnabled
    }

    private func button(_ title: String, symbol: String, id: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = title
        button.accessibilityIdentifier = id
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    @objc private func cycleFlash() {
        switch camera.configuration.flashMode {
        case .auto: camera.configuration.flashMode = .on
        case .on: camera.configuration.flashMode = .off
        case .off: camera.configuration.flashMode = .auto
        }
        updateControls()
    }

    @objc private func switchCamera() {
        var configuration = camera.configuration
        configuration.cameraType = configuration.cameraType == .back ? .front : .back
        if (mode == .photo && followsPhotoZoomEvents) || configuration.zoom != nil { configuration.zoom = 1 }
        camera.configuration = configuration
        updateFaces([])
        zoomSlider.value = 1
        zoomLabel.text = "1.0×"
    }

    @objc private func toggleTorch() {
        camera.configuration.torchMode = camera.configuration.torchMode == .on ? .off : .on
        updateControls()
    }

    @objc private func toggleFaces() {
        camera.configuration.faceDetectionEnabled.toggle()
        updateFaces([])
        updateControls()
    }

    @objc private func toggleScanning() {
        camera.configuration.scanBarcode.toggle()
        updateControls()
    }

    @objc private func changeZoom() {
        camera.configuration.zoom = Double(zoomSlider.value)
        zoomLabel.text = String(format: "%.1f×", zoomSlider.value)
    }

    @objc private func resetZoom() {
        camera.configuration.zoom = 1
        updateControls()
    }

    private func updateControls() {
        let configuration = camera.configuration
        let flashSymbol: String
        switch configuration.flashMode {
        case .auto: flashSymbol = "bolt.badge.a"
        case .on: flashSymbol = "bolt.fill"
        case .off: flashSymbol = "bolt.slash.fill"
        }
        toolbarButtons[0].setImage(UIImage(systemName: flashSymbol), for: .normal)
        toolbarButtons[0].accessibilityLabel = "Flash: \(configuration.flashMode)"
        toolbarButtons[2].setImage(UIImage(systemName: configuration.torchMode == .on ? "flashlight.on.fill" : "flashlight.off.fill"), for: .normal)
        toolbarButtons[2].accessibilityLabel = "Torch: \(configuration.torchMode)"
        toolbarButtons[3].tintColor = configuration.faceDetectionEnabled ? .systemYellow : .white
        toolbarButtons[4].tintColor = configuration.scanBarcode ? .systemYellow : .white
        toolbarButtons[3].accessibilityValue = configuration.faceDetectionEnabled ? "On" : "Off"
        toolbarButtons[4].accessibilityValue = configuration.scanBarcode ? "On" : "Off"
        zoomSlider.maximumValue = Float(configuration.maxZoom ?? 10)
        zoomSlider.value = Float(configuration.zoom ?? Double(zoomSlider.value))
        zoomLabel.text = String(format: "%.1f×", zoomSlider.value)
        if !configuration.faceDetectionEnabled { updateFaces([]) }
        faceStatsLabel.isHidden = !configuration.faceDetectionEnabled
    }

    @objc private func showSettings() {
        let settings = CameraSettingsViewController(configuration: camera.configuration) { [weak self] configuration in
            guard let self else { return }
            if configuration.zoom != camera.configuration.zoom {
                followsPhotoZoomEvents = configuration.zoom != nil
            }
            camera.configuration = configuration
            updateControls()
        }
        present(UINavigationController(rootViewController: settings), animated: true)
    }

    @objc private func capture() {
        guard mode == .photo, !isCapturing, presentedViewController == nil else { return }
        isCapturing = true
        captureButton.isEnabled = false
        photoButton.isEnabled = false
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isCapturing = false
                captureButton.isEnabled = true
                photoButton.isEnabled = !photos.isEmpty
            }
            do {
                var captureTimes: [Double] = []
                for _ in 0..<5 {
                    try Task.checkCancellation()
                    let start = CACurrentMediaTime()
                    let photo = try await camera.capture()
                    captureTimes.append((CACurrentMediaTime() - start) * 1000)
                    photos.append(photo)
                    countLabel.text = "\(photos.count) \(photos.count == 1 ? "photo" : "photos")"
                    photoButton.setImage(PhotoViewController.thumbnail(at: photo.url, maximumPixelSize: 160), for: .normal)
                }
                let median = captureTimes.sorted()[captureTimes.count / 2]
                statusLabel.text = String(format: "Saved five JPEGs · median capture %.0f ms", median)
            } catch is CancellationError {
                statusLabel.text = "Capture stopped."
            } catch {
                statusLabel.text = error.localizedDescription
            }
        }
    }

    @objc private func showPhoto() {
        guard let photo = photos.last else { return }
        let navigation = UINavigationController(rootViewController: PhotoViewController(photo: photo))
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }
}

private final class FaceOverlayView: UIView {
    var faces: [FaceDetectionPayload] = [] {
        didSet {
            accessibilityLabel = "\(faces.count) faces detected"
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func isFacingCamera(_ face: FaceDetectionPayload) -> Bool {
        let centered = abs(face.boundsX + face.boundsWidth / 2 - 0.5) < 0.2
            && abs(face.boundsY + face.boundsHeight / 2 - 0.5) < 0.2
        return abs(face.yaw) < 15 && abs(face.pitch) < 15 && centered
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for face in faces {
            let facing = Self.isFacingCamera(face)
            let color: UIColor = facing ? .systemGreen : .systemYellow
            let frame = CGRect(
                x: face.boundsX * bounds.width,
                y: face.boundsY * bounds.height,
                width: face.boundsWidth * bounds.width,
                height: face.boundsHeight * bounds.height
            )
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(3)
            context.stroke(frame)
            let label = String(format: "ID %d · yaw %.0f° · pitch %.0f° · roll %.0f°", face.id, face.yaw, face.pitch, face.roll)
            (label as NSString).draw(at: CGPoint(x: frame.minX, y: frame.maxY + 4), withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: color,
                .backgroundColor: UIColor.black.withAlphaComponent(0.7)
            ])
        }
    }
}
