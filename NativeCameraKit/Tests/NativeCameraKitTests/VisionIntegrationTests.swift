import CoreML
import CoreVideo
import ImageIO
import UIKit
import Vision
import XCTest
@testable import NativeCameraKit

final class VisionIntegrationTests: XCTestCase {
    func testVisionDetectsFaceInPublicDomainFixture() throws {
        let image = try fixtureImage()
        let buffer = try pixelBuffer(image: image)
        let detector = try detector()
        detector.update(throttleMs: 0)
        let faces = try XCTUnwrap(detector.process(pixelBuffer: buffer, orientation: .up))
        XCTAssertEqual(faces.count, 1)
        let face = try XCTUnwrap(faces.first)
        // The portrait face is near the upper center, not the lower half of the image.
        XCTAssertEqual(face.boundsX, 0.35, accuracy: 0.08)
        XCTAssertEqual(face.boundsY, 0.12, accuracy: 0.08)
        XCTAssertEqual(face.boundsWidth, 0.18, accuracy: 0.06)
        XCTAssertEqual(face.boundsHeight, 0.22, accuracy: 0.08)
        XCTAssertTrue(face.yaw.isFinite)
        XCTAssertTrue(face.pitch.isFinite)
        XCTAssertTrue(face.roll.isFinite)
    }

    func testEmptyImageClearsFaceResults() throws {
        let detector = try detector()
        detector.update(throttleMs: 0)
        let portrait = try pixelBuffer(image: fixtureImage())
        XCTAssertFalse(try XCTUnwrap(detector.process(pixelBuffer: portrait, orientation: .up)).isEmpty)
        let blank = try pixelBuffer(image: nil)
        XCTAssertEqual(try XCTUnwrap(detector.process(pixelBuffer: blank, orientation: .up)).count, 0)
    }

    func testMirroredInputKeepsNormalizedTopLeftBounds() throws {
        let image = try fixtureImage()
        let buffer = try pixelBuffer(image: image)
        let detector = try detector()
        detector.update(throttleMs: 0)
        let normal = try XCTUnwrap(detector.process(pixelBuffer: buffer, orientation: .up)?.first)
        let orientation = CGImagePropertyOrientation(cameraRotationAngle: 0, mirrored: true)
        let mirrored = try XCTUnwrap(detector.process(pixelBuffer: buffer, orientation: orientation)?.first)
        XCTAssertEqual(mirrored.boundsX, 1 - normal.boundsX - normal.boundsWidth, accuracy: 0.035)
        XCTAssertEqual(mirrored.boundsY, normal.boundsY, accuracy: 0.035)
        XCTAssertEqual(mirrored.boundsWidth, normal.boundsWidth, accuracy: 0.035)
        XCTAssertEqual(mirrored.boundsHeight, normal.boundsHeight, accuracy: 0.035)
    }

    func testSensorRotationAndMirroringKeepOffCenterFaceAligned() throws {
        let image = try offCenterFixtureImage()
        let detector = try detector()
        detector.update(throttleMs: 0)
        let baseline = try XCTUnwrap(detector.process(pixelBuffer: pixelBuffer(image: image), orientation: .up)?.first)
        let mirroredBaseline = try XCTUnwrap(detector.process(pixelBuffer: pixelBuffer(image: image), orientation: .upMirrored)?.first)

        for angle in [0, 90, 180, 270] {
            // Encode the sensor image with the inverse rotation of the preview connection.
            let sensorImage = try rotatedImage(image, clockwiseDegrees: -angle)
            let buffer = try pixelBuffer(image: sensorImage)
            for mirrored in [false, true] {
                try XCTContext.runActivity(named: "Sensor angle \(angle), mirrored \(mirrored)") { activity in
                    let orientation = CGImagePropertyOrientation(cameraRotationAngle: CGFloat(angle), mirrored: mirrored)
                    let faces = try XCTUnwrap(detector.process(pixelBuffer: buffer, orientation: orientation))
                    record(faces, scenario: "sensor angle=\(angle) mirrored=\(mirrored)")
                    XCTAssertEqual(faces.count, 1)
                    guard let face = faces.first else {
                        attach(sensorImage, to: activity)
                        return
                    }
                    let expected = mirrored ? horizontallyMirrored(baseline.bounds) : baseline.bounds
                    assertBounds(face.bounds, equalTo: expected)
                    let expectedPose = mirrored ? mirroredBaseline : baseline
                    XCTAssertEqual(face.yaw, expectedPose.yaw, accuracy: 5)
                    XCTAssertEqual(face.pitch, expectedPose.pitch, accuracy: 5)
                    assertAngle(face.roll, equalTo: expectedPose.roll)
                }
            }
        }
    }

    func testLockedPreviewDetectsRotatedFacesInPreviewCoordinates() throws {
        let image = try offCenterFixtureImage()
        let detector = try detector()
        detector.update(throttleMs: 0)
        let baseline = try XCTUnwrap(detector.process(pixelBuffer: pixelBuffer(image: image), orientation: .up)?.first)
        let mirroredBaseline = try XCTUnwrap(detector.process(pixelBuffer: pixelBuffer(image: image), orientation: .upMirrored)?.first)

        for angle in [0, 90, 180, 270] {
            // A locked portrait preview does not counter-rotate a face when the device turns.
            let sensorImage = try rotatedImage(image, clockwiseDegrees: angle)
            let buffer = try pixelBuffer(image: sensorImage)
            for mirrored in [false, true] {
                try XCTContext.runActivity(named: "Locked preview, face angle \(angle), mirrored \(mirrored)") { activity in
                    let orientation = CGImagePropertyOrientation(cameraRotationAngle: 0, mirrored: mirrored)
                    let faces = try XCTUnwrap(detector.process(pixelBuffer: buffer, orientation: orientation))
                    record(faces, scenario: "locked angle=\(angle) mirrored=\(mirrored)")
                    XCTAssertEqual(faces.count, 1)
                    guard let face = faces.first else {
                        attach(sensorImage, to: activity)
                        return
                    }
                    var expected = rotatedBounds(baseline.bounds, clockwiseDegrees: angle)
                    if mirrored { expected = horizontallyMirrored(expected) }
                    assertBounds(face.bounds, equalTo: expected, accuracy: 0.05)
                    XCTAssertTrue(face.yaw.isFinite && face.pitch.isFinite && face.roll.isFinite)
                    let expectedRoll = mirrored ? mirroredBaseline.roll + Double(angle) : baseline.roll - Double(angle)
                    assertAngle(face.roll, equalTo: expectedRoll)
                }
            }
        }
    }

    func testLongThrottleSkipsRepeatedFrameInsteadOfClearingFaces() throws {
        let detector = try detector()
        detector.update(throttleMs: 60_000)
        let buffer = try pixelBuffer(image: fixtureImage())
        XCTAssertFalse(try XCTUnwrap(detector.process(pixelBuffer: buffer, orientation: .up)).isEmpty)
        XCTAssertNil(detector.process(pixelBuffer: buffer, orientation: .up))
    }

    private func detector() throws -> FaceDetector {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        // Simulator acceleration is not always available. Exercise the same model on its supported CPU.
        for (stage, devices) in try request.supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                request.setComputeDevice(cpu, for: stage)
            }
        }
        return FaceDetector(request: request)
    }

    private func fixtureImage() throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "astronaut", withExtension: "png", subdirectory: "Fixtures"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func offCenterFixtureImage() throws -> CGImage {
        let context = try imageContext(width: 768, height: 640)
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 768, height: 640))
        context.draw(try fixtureImage(), in: CGRect(x: 32, y: 96, width: 512, height: 512))
        return try XCTUnwrap(context.makeImage())
    }

    private func rotatedImage(_ image: CGImage, clockwiseDegrees: Int) throws -> CGImage {
        let angle = (clockwiseDegrees % 360 + 360) % 360
        let swapsAxes = angle == 90 || angle == 270
        let width = swapsAxes ? image.height : image.width
        let height = swapsAxes ? image.width : image.height
        let context = try imageContext(width: width, height: height)
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(angle) * .pi / 180)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return try XCTUnwrap(context.makeImage())
    }

    private func imageContext(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    }

    private func horizontallyMirrored(_ bounds: CGRect) -> CGRect {
        CGRect(x: 1 - bounds.maxX, y: bounds.minY, width: bounds.width, height: bounds.height)
    }

    private func rotatedBounds(_ bounds: CGRect, clockwiseDegrees: Int) -> CGRect {
        switch clockwiseDegrees {
        case 90: return CGRect(x: 1 - bounds.maxY, y: bounds.minX, width: bounds.height, height: bounds.width)
        case 180: return CGRect(x: 1 - bounds.maxX, y: 1 - bounds.maxY, width: bounds.width, height: bounds.height)
        case 270: return CGRect(x: bounds.minY, y: 1 - bounds.maxX, width: bounds.height, height: bounds.width)
        default: return bounds
        }
    }

    private func assertBounds(_ actual: CGRect, equalTo expected: CGRect, accuracy: CGFloat = 0.035,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    private func record(_ faces: [FaceDetectionPayload], scenario: String) {
        let values = faces.map { "bounds=\($0.bounds) yaw=\($0.yaw) pitch=\($0.pitch) roll=\($0.roll)" }
        print("VISION_ORIENTATION \(scenario) count=\(faces.count) \(values.joined(separator: "; "))")
    }

    private func assertAngle(_ actual: Double, equalTo expected: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        let difference = abs((actual - expected).truncatingRemainder(dividingBy: 360))
        XCTAssertLessThanOrEqual(min(difference, 360 - difference), 5, file: file, line: line)
    }

    private func attach(_ image: CGImage, to activity: XCTActivity) {
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.lifetime = .keepAlways
        activity.add(attachment)
    }

    private func pixelBuffer(image: CGImage?) throws -> CVPixelBuffer {
        let width = image?.width ?? 512
        let height = image?.height ?? 512
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &optionalBuffer)
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let context = try XCTUnwrap(CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ))
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let image { context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        return buffer
    }
}
