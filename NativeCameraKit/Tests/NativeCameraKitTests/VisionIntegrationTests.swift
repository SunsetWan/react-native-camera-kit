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
