import AVFoundation
import Foundation

/// Camera permission access for apps that ask before presenting a camera view.
public enum CameraAuthorization {
    public static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Returns false for denied or restricted access. An app usage description is required to prompt.
    public static func requestAccess() async throws -> Bool {
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            guard let description = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String,
                  !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CameraError.missingUsageDescription
            }
            return await AVCaptureDevice.requestAccess(for: .video)
        @unknown default:
            return false
        }
    }
}
