//
//  Types.swift
//  NativeCameraKit
//

import AVFoundation
import UIKit

public enum CameraType: Int, CustomStringConvertible {
    case back
    case front

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back: return .back
        case .front: return .front
        }
    }

    public var description: String {
        switch self {
        case .back: return "back"
        case .front: return "front"
        }
    }
}

public enum FlashMode: Int, CustomStringConvertible {
    case on
    case off
    case auto

    var avFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .on: return .on
        case .off: return .off
        case .auto: return .auto
        }
    }

    public var description: String {
        switch self {
        case .on: return "on"
        case .off: return "off"
        case .auto: return "auto"
        }
    }
}

public enum MaxPhotoQualityPrioritization: Int, CustomStringConvertible {
    case speed
    case balanced
    case quality

    var avQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        switch self {
        case .speed: return .speed
        case .balanced: return .balanced
        case .quality: return .quality
        }
    }

    public var description: String {
        switch self {
        case .speed: return "speed"
        case .balanced: return "balanced"
        case .quality: return "quality"
        }
    }
}

public enum TorchMode: Int, CustomStringConvertible {
    case on
    case off

    init(from string: String) {
        switch string {
        case "on": self = .on
        default: self = .off
        }
    }

    var avTorchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .on: return .on
        case .off: return .off
        }
    }

    public var description: String {
        switch self {
        case .on: return "on"
        case .off: return "off"
        }
    }
}

public enum FocusMode: Int, CustomStringConvertible {
    case on
    case off

    public var description: String {
        switch self {
        case .on: return "on"
        case .off: return "off"
        }
    }
}

public enum ZoomMode: Int, CustomStringConvertible {
    case on
    case off

    public var description: String {
        switch self {
        case .on: return "on"
        case .off: return "off"
        }
    }
}

public enum ResizeMode: Int, CustomStringConvertible {
    case cover
    case contain

    public var description: String {
        switch self {
        case .cover: return "cover"
        case .contain: return "contain"
        }
    }
}

enum SetupResult: Int {
    case notStarted
    case success
    case cameraNotAuthorized
    case sessionConfigurationFailed
}

public enum Orientation: Int, CaseIterable {
    case portrait = 0 // ⬆️
    case landscapeLeft = 1 // ⬅️
    case portraitUpsideDown = 2 // ⬇️
    case landscapeRight = 3 // ➡️

    public init?(from orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait: self = .portrait
        case .landscapeLeft: self = .landscapeLeft
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }

    public init?(from orientation: UIInterfaceOrientation) {
        switch orientation {
        case .portrait: self = .portrait
        case .landscapeLeft: self = .landscapeLeft
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }

    var videoRotationAngle: CGFloat {
        switch self {
        case .portrait: return 90
        case .landscapeLeft: return 180
        case .portraitUpsideDown: return 270
        case .landscapeRight: return 0
        }
    }
}
