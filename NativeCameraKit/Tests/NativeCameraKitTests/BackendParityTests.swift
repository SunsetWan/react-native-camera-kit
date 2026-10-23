import ImageIO
import UIKit
import XCTest
@testable import NativeCameraKit

final class BackendParityTests: XCTestCase {
    func testRealCameraMaximumZeroCapsZoomAtTheNormalizedHardwareMinimum() {
        for minimum in [0.5, 1.0] {
            let range = CameraZoomRange(minimum: minimum, maximum: 75, maxZoom: 0)
            XCTAssertEqual(range.clamp(4), minimum)
            XCTAssertEqual(range.clamp(0), minimum)
        }
        XCTAssertEqual(CameraZoomRange(minimum: 0.5, maximum: 75, maxZoom: 3).clamp(4), 3)
        XCTAssertEqual(CameraZoomRange(minimum: 0.5, maximum: 75, maxZoom: -2).clamp(4), 0.5)
    }

    func testRealCameraUnsetMaximumAndMinusOneKeepHardwareBounds() {
        for maximum in [nil, -1, Double.nan, .infinity, -.infinity] as [Double?] {
            let range = CameraZoomRange(minimum: 0.5, maximum: 75, maxZoom: maximum)
            XCTAssertEqual(range.clamp(4), 4)
            XCTAssertEqual(range.clamp(100), 75)
            XCTAssertEqual(range.clamp(0), 0.5)
        }
    }

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
    func testSimulatorControlledZoomEmitsEveryGestureTargetWithoutApplyingIt() throws {
        let camera = SimulatorCamera()
        var events: [Double] = []
        camera.update(onZoom: { events.append($0) })
        camera.update(maxZoom: 4)
        camera.update(zoom: 3)
        camera.setup(cameraType: .back, supportedBarcodeType: [])
        let preview = try XCTUnwrap(camera.previewView as? SimulatorPreviewView)
        XCTAssertTrue(events.isEmpty)
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 2)
        camera.zoomPinchChange(pinchScale: 3)
        XCTAssertEqual(events, [4, 4])
        XCTAssertEqual(preview.zoomLabel.text, "Zoom start")
        camera.update(zoom: 4)
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 0.75)
        XCTAssertEqual(events, [4, 4, 3])
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
        XCTAssertEqual(events, [4, 4])
    }

    @MainActor
    func testSimulatorCameraSwitchKeepsUncontrolledZoomWithoutEmitting() throws {
        let camera = SimulatorCamera()
        var events: [Double] = []
        camera.update(onZoom: { events.append($0) })
        camera.setup(cameraType: .back, supportedBarcodeType: [])
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 3)
        let preview = try XCTUnwrap(camera.previewView as? SimulatorPreviewView)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 3.0")
        camera.update(cameraType: .front)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 3.0")
        camera.update(cameraType: .back)
        XCTAssertEqual(events, [3])
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 2)
        XCTAssertEqual(events, [3, 6])
    }

    @MainActor
    func testSimulatorNilAndZeroZoomResetToRawWideAngleAndAlwaysNotify() throws {
        let camera = SimulatorCamera()
        var events: [Double] = []
        camera.update(onZoom: { events.append($0) })
        camera.setup(cameraType: .back, supportedBarcodeType: [])
        camera.update(zoom: 3)
        camera.update(zoom: nil)
        camera.update(zoom: nil)
        let preview = try XCTUnwrap(camera.previewView as? SimulatorPreviewView)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 2.0")
        XCTAssertEqual(events, [2, 2])
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 2)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 4.0")
        camera.update(zoom: 0)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 2.0")
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 2)
        camera.zoomPinchChange(pinchScale: 2)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom start", "Zero remains a controlled zoom value")
        XCTAssertEqual(events, [2, 2, 4, 2, 4, 4])
    }

    @MainActor
    func testSimulatorUsesRawOneToOneHundredFiftyZoomRangeForBothCameras() throws {
        let camera = SimulatorCamera()
        var events: [Double] = []
        camera.update(onZoom: { events.append($0) })
        let preview = try XCTUnwrap(camera.previewView as? SimulatorPreviewView)
        for type in [CameraType.back, .front] {
            camera.update(cameraType: type)
            camera.update(zoom: 0.5)
            XCTAssertEqual(preview.zoomLabel.text, "Zoom: 1.0")
            camera.update(zoom: 200)
            XCTAssertEqual(preview.zoomLabel.text, "Zoom: 150.0")
        }
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testSimulatorMaxZoomAppliesToNextPropertyOrGestureWithoutResettingCurrentZoom() throws {
        let camera = SimulatorCamera()
        var events: [Double] = []
        camera.update(onZoom: { events.append($0) })
        camera.update(zoom: nil)
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 3)
        let preview = try XCTUnwrap(camera.previewView as? SimulatorPreviewView)
        camera.update(maxZoom: 3)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 6.0")
        camera.zoomPinchStart()
        camera.zoomPinchChange(pinchScale: 2)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 3.0")
        camera.update(maxZoom: 0)
        camera.update(zoom: nil)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 1.0")
        camera.update(maxZoom: nil)
        camera.update(zoom: 0)
        XCTAssertEqual(preview.zoomLabel.text, "Zoom: 2.0")
        XCTAssertEqual(events, [2, 6, 3, 1, 2])
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

    func testVisionOrientationUsesActualSensorRotationAndPreviewMirroring() {
        XCTAssertEqual(CGImagePropertyOrientation(cameraRotationAngle: 0, mirrored: false), .up)
        XCTAssertEqual(CGImagePropertyOrientation(cameraRotationAngle: 0, mirrored: true), .upMirrored)
        XCTAssertEqual(CGImagePropertyOrientation(cameraRotationAngle: 90, mirrored: false), .right)
        XCTAssertEqual(CGImagePropertyOrientation(cameraRotationAngle: 90, mirrored: true), .leftMirrored)
        XCTAssertEqual(CGImagePropertyOrientation(cameraRotationAngle: 180, mirrored: false), .down)
        XCTAssertEqual(CGImagePropertyOrientation(cameraRotationAngle: 180, mirrored: true), .downMirrored)
        XCTAssertEqual(CGImagePropertyOrientation(cameraRotationAngle: 270, mirrored: false), .left)
        XCTAssertEqual(CGImagePropertyOrientation(cameraRotationAngle: 270, mirrored: true), .rightMirrored)
    }
}
