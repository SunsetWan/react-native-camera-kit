import ImageIO
import UIKit
import XCTest
@testable import NativeCameraKit

final class BackendParityTests: XCTestCase {
    func testConfigurationWaitsForEveryNativeCaptureAndRunsInOrder() {
        let gate = CaptureConfigurationGate()
        var events: [String] = []
        gate.performWhenIdle { events.append("initial") }
        gate.beginCapture(id: 1)
        gate.beginCapture(id: 2)
        gate.performWhenIdle { events.append("front") }
        gate.performWhenIdle { events.append("back") }
        gate.endCapture(id: 1)
        XCTAssertEqual(events, ["initial"])
        gate.endCapture(id: 1)
        XCTAssertEqual(events, ["initial"])
        gate.endCapture(id: 2)
        XCTAssertEqual(events, ["initial", "front", "back"])
        gate.endCapture(id: 2)
        gate.performWhenIdle { events.append("quality") }
        XCTAssertEqual(events, ["initial", "front", "back", "quality"])
    }

    @MainActor
    func testSimulatorKeepsInitialControlledZoomAtSetup() {
        let camera = SimulatorCamera()
        var events: [Double] = []
        camera.update(onZoom: { events.append($0) })
        camera.update(maxZoom: 4)
        camera.update(zoom: 3)
        camera.setup(cameraType: .back, supportedBarcodeType: [])
        XCTAssertEqual(events, [3])
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 2)
        camera.zoomPinchChange(pinchScale: 3)
        XCTAssertEqual(events, [3, 4], "A controlled gesture should emit its capped target once")
        camera.update(zoom: 4)
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 0.75)
        XCTAssertEqual(events, [3, 4, 3])
    }

    @MainActor
    func testControlledZoomTargetCanRepeatInAnotherGesture() {
        let camera = SimulatorCamera()
        var events: [Double] = []
        camera.update(onZoom: { events.append($0) })
        camera.update(zoom: 2)
        camera.setup(cameraType: .back, supportedBarcodeType: [])
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 2)
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 2)
        XCTAssertEqual(events, [2, 4, 4])
    }

    @MainActor
    func testCameraSwitchRestoresWideAngleAndKeepsControlledZoom() {
        let camera = SimulatorCamera()
        var events: [Double] = []
        camera.update(onZoom: { events.append($0) })
        camera.setup(cameraType: .back, supportedBarcodeType: [])
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 3)
        camera.update(cameraType: .front)
        camera.update(zoom: 2)
        camera.update(cameraType: .back)
        XCTAssertEqual(events, [1, 3, 1, 2])
    }

    func testFaceProjectionAccountsForLetterboxWithoutChangingAngles() {
        let face = FaceDetectionPayload(id: 2, yaw: -10, pitch: 5, roll: 7,
                                        boundsX: 0.25, boundsY: 0.25, boundsWidth: 0.5, boundsHeight: 0.5)
        let result = face.projected(in: CGRect(x: 0, y: 100, width: 400, height: 200),
                                    previewSize: CGSize(width: 400, height: 400))
        XCTAssertEqual(result.bounds, CGRect(x: 0.25, y: 0.375, width: 0.5, height: 0.25))
        XCTAssertEqual(result.id, face.id)
        XCTAssertEqual(result.yaw, face.yaw)
        XCTAssertEqual(result.pitch, face.pitch)
        XCTAssertEqual(result.roll, face.roll)
    }

    func testFaceProjectionKeepsCroppedCoordinatesForCover() {
        let face = FaceDetectionPayload(id: 0, yaw: 0, pitch: 0, roll: 0,
                                        boundsX: 0, boundsY: 0.25, boundsWidth: 0.5, boundsHeight: 0.5)
        let result = face.projected(in: CGRect(x: -200, y: 0, width: 800, height: 400),
                                    previewSize: CGSize(width: 400, height: 400))
        XCTAssertEqual(result.bounds, CGRect(x: -0.5, y: 0.25, width: 1, height: 0.5))
    }

    func testVisionOrientationUsesPreviewAxesAndFrontMirroring() {
        XCTAssertEqual(Orientation.portrait.visionOrientation(cameraType: .back), .right)
        XCTAssertEqual(Orientation.portrait.visionOrientation(cameraType: .front), .leftMirrored)
        XCTAssertEqual(Orientation.portraitUpsideDown.visionOrientation(cameraType: .back), .left)
        XCTAssertEqual(Orientation.portraitUpsideDown.visionOrientation(cameraType: .front), .rightMirrored)
        XCTAssertEqual(Orientation.landscapeLeft.visionOrientation(cameraType: .back), .down)
        XCTAssertEqual(Orientation.landscapeLeft.visionOrientation(cameraType: .front), .upMirrored)
        XCTAssertEqual(Orientation.landscapeRight.visionOrientation(cameraType: .back), .up)
        XCTAssertEqual(Orientation.landscapeRight.visionOrientation(cameraType: .front), .downMirrored)
    }
}
