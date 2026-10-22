import AVFoundation
import UIKit
import XCTest
@testable import NativeCameraKit

final class NativeTypesTests: XCTestCase {
    func testBarcodeFormatsRoundTripThroughAVFoundation() {
        for format in CodeFormat.allCases where format != .unknown {
            XCTAssertEqual(CodeFormat.fromAVMetadataObjectType(format.toAVMetadataObjectType()), format)
        }
        XCTAssertEqual(CodeFormat.fromAVMetadataObjectType(.init(rawValue: "unsupported")), .unknown)
    }

    func testSourceCompatibleDefaults() {
        let configuration = CameraConfiguration()
        XCTAssertEqual(configuration.cameraType, .back)
        XCTAssertEqual(configuration.flashMode, .auto)
        XCTAssertEqual(configuration.torchMode, .off)
        XCTAssertEqual(configuration.resizeMode, .contain)
        XCTAssertEqual(configuration.focusMode, .on)
        XCTAssertEqual(configuration.zoomMode, .on)
        XCTAssertEqual(configuration.maxPhotoQualityPrioritization, .balanced)
        XCTAssertNil(configuration.zoom)
        XCTAssertNil(configuration.maxZoom)
        XCTAssertFalse(configuration.scanBarcode)
        XCTAssertFalse(configuration.showFrame)
        XCTAssertEqual(configuration.scanThrottleDelay, 2000)
        XCTAssertFalse(configuration.faceDetectionEnabled)
        XCTAssertEqual(configuration.faceDetectionThrottleMs, 100)
        XCTAssertEqual(configuration.resetFocusTimeout, 0)
        XCTAssertTrue(configuration.resetFocusWhenMotionDetected)
        XCTAssertTrue(configuration.iOsDeferredStart)
    }

    func testRotationAnglesMatchPreviewAxes() {
        XCTAssertEqual(Orientation.portrait.videoRotationAngle, 90)
        XCTAssertEqual(Orientation.landscapeLeft.videoRotationAngle, 180)
        XCTAssertEqual(Orientation.portraitUpsideDown.videoRotationAngle, 270)
        XCTAssertEqual(Orientation.landscapeRight.videoRotationAngle, 0)
    }

    func testOnlyPhysicalOrientationsProduceEvents() {
        XCTAssertNil(Orientation(from: UIDeviceOrientation.faceUp))
        XCTAssertNil(Orientation(from: UIDeviceOrientation.faceDown))
        XCTAssertNil(Orientation(from: UIDeviceOrientation.unknown))
        XCTAssertEqual(Orientation(from: UIDeviceOrientation.portrait)?.rawValue, 0)
        XCTAssertEqual(Orientation(from: UIDeviceOrientation.landscapeLeft)?.rawValue, 1)
        XCTAssertEqual(Orientation(from: UIDeviceOrientation.portraitUpsideDown)?.rawValue, 2)
        XCTAssertEqual(Orientation(from: UIDeviceOrientation.landscapeRight)?.rawValue, 3)
    }
}
