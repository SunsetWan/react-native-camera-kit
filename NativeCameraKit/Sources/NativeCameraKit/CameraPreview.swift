import Observation
import SwiftUI

/// Retain one controller for each SwiftUI preview.
@MainActor
@Observable
public final class CameraController {
    public var configuration: CameraConfiguration {
        didSet { cameraView?.configuration = configuration }
    }
    public var onReadCode: ((Barcode) -> Void)? {
        didSet { updateDetectionCallbacks() }
    }
    public var onFaceDetected: (([FaceDetectionPayload]) -> Void)? {
        didSet { updateDetectionCallbacks() }
    }
    public var onOrientationChange: ((Orientation) -> Void)?
    public var onZoom: ((Double) -> Void)?
    public var onCaptureButtonPressIn: (() -> Void)?
    public var onCaptureButtonPressOut: (() -> Void)?
    public var onError: ((CameraError) -> Void)?
    @ObservationIgnored private weak var cameraView: CameraView?

    public init(configuration: CameraConfiguration = .init()) {
        self.configuration = configuration
    }

    public func start() { cameraView?.start() }
    public func stop() { cameraView?.stop() }

    public func capture() async throws -> CapturedPhoto {
        guard let cameraView else { throw CameraError.previewUnavailable }
        return try await cameraView.capture()
    }

    func attach(_ view: CameraView) {
        cameraView = view
        view.configuration = configuration
        updateDetectionCallbacks()
        view.onOrientationChange = { [weak self] in self?.onOrientationChange?($0) }
        view.onZoom = { [weak self] in self?.onZoom?($0) }
        view.onCaptureButtonPressIn = { [weak self] in self?.onCaptureButtonPressIn?() }
        view.onCaptureButtonPressOut = { [weak self] in self?.onCaptureButtonPressOut?() }
        view.onError = { [weak self] in self?.onError?($0) }
    }

    private func updateDetectionCallbacks() {
        cameraView?.onReadCode = onReadCode == nil ? nil : { [weak self] in self?.onReadCode?($0) }
        cameraView?.onFaceDetected = onFaceDetected == nil ? nil : { [weak self] in self?.onFaceDetected?($0) }
    }

    func detach(_ view: CameraView) {
        guard cameraView === view else { return }
        view.stop()
        cameraView = nil
    }
}

/// An optional SwiftUI adapter for the UIKit camera view.
@MainActor
public struct CameraPreview: UIViewRepresentable {
    private let controller: CameraController

    public init(controller: CameraController) { self.controller = controller }

    public func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    public func makeUIView(context: Context) -> CameraView {
        let view = CameraView(configuration: controller.configuration)
        controller.attach(view)
        return view
    }

    public func updateUIView(_ view: CameraView, context: Context) {
        if context.coordinator.controller !== controller {
            context.coordinator.controller.detach(view)
            context.coordinator.controller = controller
            controller.attach(view)
            view.start()
        }
    }

    public static func dismantleUIView(_ view: CameraView, coordinator: Coordinator) {
        coordinator.controller.detach(view)
    }

    public final class Coordinator {
        fileprivate var controller: CameraController
        fileprivate init(controller: CameraController) { self.controller = controller }
    }
}
