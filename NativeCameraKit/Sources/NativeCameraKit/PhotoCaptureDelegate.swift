import AVFoundation
import UIKit

/// Retains photo data until the capture transaction finishes, then completes exactly once.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let requestedPhotoSettings: AVCapturePhotoSettings

    private let onWillCapture: () -> Void
    private let onCaptureSuccess: (Int64, Data, Data?, CMVideoDimensions) -> Void
    private let onCaptureError: (Int64, String) -> Void
    private let onFinished: ((Int64) -> Void)?
    private let lock = NSLock()
    private var completed = false
    private var cancelled = false
    private var result: (Data, Data?, CMVideoDimensions)?
    private var processingError: String?

    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         onWillCapture: @escaping () -> Void,
         onCaptureSuccess: @escaping (Int64, Data, Data?, CMVideoDimensions) -> Void,
         onCaptureError: @escaping (Int64, String) -> Void,
         onFinished: ((Int64) -> Void)? = nil) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.onWillCapture = onWillCapture
        self.onCaptureSuccess = onCaptureSuccess
        self.onCaptureError = onCaptureError
        self.onFinished = onFinished
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async {
            self.lock.lock()
            let wasCancelled = self.cancelled
            self.lock.unlock()
            if !wasCancelled { self.onWillCapture() }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        if let error {
            processingError = error.localizedDescription
            return
        }
        guard let imageData = photo.fileDataRepresentation() else {
            processingError = "The camera did not produce photo data."
            return
        }
        var thumbnail: Data?
        if let pixelBuffer = photo.previewPixelBuffer {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            if let image = CIContext().createCGImage(ciImage, from: ciImage.extent) {
                thumbnail = UIImage(cgImage: image).jpegData(compressionQuality: 0.7)
            }
        }
        result = (imageData, thumbnail, photo.resolvedSettings.photoDimensions)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        // Queue backend cleanup before the client can submit its next capture.
        onFinished?(requestedPhotoSettings.uniqueID)
        finish(error: error?.localizedDescription)
    }

    func cancel(message: String) { finish(error: message, cancelled: true) }

    private func finish(error: String?, cancelled: Bool = false) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        self.cancelled = cancelled
        let data = result
        let message = error ?? processingError
        lock.unlock()
        DispatchQueue.main.async {
            if let message {
                self.onCaptureError(self.requestedPhotoSettings.uniqueID, message)
            } else if let data {
                self.onCaptureSuccess(self.requestedPhotoSettings.uniqueID, data.0, data.1, data.2)
            } else {
                self.onCaptureError(self.requestedPhotoSettings.uniqueID, "The camera did not produce photo data.")
            }
        }
    }
}
