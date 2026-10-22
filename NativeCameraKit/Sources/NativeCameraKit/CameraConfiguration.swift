import Foundation
import UIKit

/// Native camera settings. Defaults match the upstream iOS component.
public struct CameraConfiguration: Equatable {
    public var cameraType: CameraType = .back
    public var resizeMode: ResizeMode = .contain
    public var flashMode: FlashMode = .auto
    public var torchMode: TorchMode = .off
    public var maxPhotoQualityPrioritization: MaxPhotoQualityPrioritization = .balanced
    /// A height:width guide, such as "16:9" for a portrait frame. Does not crop capture output.
    public var ratioOverlay: String?
    public var ratioOverlayColor: UIColor?
    public var scanBarcode = false
    public var showFrame = false
    public var scanThrottleDelay = 2_000
    public var frameColor: UIColor = .white
    public var laserColor: UIColor = .red
    public var barcodeFrameSize: CGSize?
    /// An empty list allows all formats supported by the camera.
    public var allowedBarcodeTypes: [CodeFormat] = []
    public var faceDetectionEnabled = false
    public var faceDetectionThrottleMs = 100
    public var resetFocusTimeout = 0
    public var resetFocusWhenMotionDetected = true
    public var focusMode: FocusMode = .on
    public var zoomMode: ZoomMode = .on
    public var zoom: Double?
    public var maxZoom: Double?
    public var iOsDeferredStart = true

    public init() {}

    var supportedBarcodeTypes: [CodeFormat] {
        allowedBarcodeTypes.isEmpty ? CodeFormat.allCases : allowedBarcodeTypes
    }
}

public struct Barcode: Equatable {
    public let codeStringValue: String
    public let codeFormat: CodeFormat
}

/// The caller owns the cache file and may move or remove it after use.
public struct CapturedPhoto: Equatable {
    public let url: URL
    public var uri: String { url.absoluteString }
    public var name: String { url.lastPathComponent }
    public let size: Int
    public let width: Int
    public let height: Int
    /// The upstream iOS implementation does not return a thumbnail.
    public var thumb: String { "" }
}

public enum CameraError: Error, LocalizedError, Equatable {
    case permissionDenied
    case missingUsageDescription
    case notRunning
    case captureInProgress
    case previewUnavailable
    case captureFailed(String)
    case fileWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera access is denied or restricted. Enable access in Settings."
        case .missingUsageDescription: return "Add NSCameraUsageDescription to the app Info.plist."
        case .captureInProgress: return "A photo capture is already in progress."
        case .notRunning: return "Start the camera before taking a photo."
        case .previewUnavailable: return "Attach a camera preview before taking a photo."
        case .captureFailed(let message): return message
        case .fileWriteFailed(let message): return "Could not save the photo: \(message)"
        }
    }
}

struct ScanThrottle {
    private var lastEmission: TimeInterval?

    mutating func shouldEmit(at now: TimeInterval, delayMilliseconds: Int) -> Bool {
        if let lastEmission, now - lastEmission <= Double(max(0, delayMilliseconds)) / 1_000 {
            return false
        }
        lastEmission = now
        return true
    }
}
