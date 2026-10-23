import AVFoundation
import ImageIO
import NativeCameraKit
import UIKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class HardwareCaptureIntegrationTests: XCTestCase {
    func testConcurrentCapturesProduceIndependentJPEGs() async throws {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        let requiresPhysicalDevice = true
        #else
        let requiresPhysicalDevice = false
        #endif
        try XCTSkipIf(requiresPhysicalDevice, "This test requires an iPhone or iPad camera.")
        try XCTSkipUnless(CameraAuthorization.status == .authorized, "Grant camera access before this hardware test.")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }, "The test app must be in the foreground.")
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let controller = UIViewController()
        window.rootViewController = controller
        controller.view.frame = window.bounds

        var configuration = CameraConfiguration()
        configuration.flashMode = .off
        configuration.maxPhotoQualityPrioritization = .speed
        configuration.iOsDeferredStart = false
        let camera = CameraView(configuration: configuration)
        camera.frame = controller.view.bounds
        camera.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let started = expectation(forNotification: AVCaptureSession.didStartRunningNotification, object: nil)
        var requests: [CaptureRequest] = []
        defer {
            camera.stop()
            camera.removeFromSuperview()
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
            attachEvidence(requests)
            for request in requests {
                if let photo = try? request.result?.get() { try? FileManager.default.removeItem(at: photo.url) }
            }
        }

        controller.view.addSubview(camera)
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        camera.start()
        guard await XCTWaiter.fulfillment(of: [started], timeout: 15) == .completed else {
            XCTFail("The camera session did not start within 15 seconds.")
            return
        }

        // A real JPEG confirms capture readiness beyond the session-start notification.
        let warmup = CaptureRequest(name: "Warmup", camera: camera)
        requests.append(warmup)
        guard await finish([warmup], camera: camera) else { return }
        try validateJPEG(try XCTUnwrap(warmup.result).get())

        let first = CaptureRequest(name: "Concurrent 1", camera: camera)
        let second = CaptureRequest(name: "Concurrent 2", camera: camera)
        requests += [first, second]
        guard await finish([first, second], camera: camera) else { return }
        let firstPhoto = try XCTUnwrap(first.result).get()
        let secondPhoto = try XCTUnwrap(second.result).get()
        XCTAssertNotEqual(firstPhoto.url, secondPhoto.url)
        try validateJPEG(firstPhoto)
        try validateJPEG(secondPhoto)
        let latestStart = max(try XCTUnwrap(first.startedAt), try XCTUnwrap(second.startedAt))
        let earliestFinish = min(try XCTUnwrap(first.finishedAt), try XCTUnwrap(second.finishedAt))
        XCTAssertLessThan(latestStart, earliestFinish, "Both public capture calls must be in flight at the same time.")
    }

    private func finish(_ requests: [CaptureRequest], camera: CameraView) async -> Bool {
        let result = await XCTWaiter.fulfillment(of: requests.map(\.completed), timeout: 20)
        guard result != .completed else { return true }
        // Task cancellation does not cancel an AVFoundation capture. Stop the session instead.
        camera.stop()
        let cleanup = await XCTWaiter.fulfillment(of: requests.map(\.settled), timeout: 5)
        XCTAssertEqual(cleanup, .completed, "Capture requests did not settle after stopping the camera.")
        XCTFail("Capture requests did not finish within 20 seconds: \(requests.map(\.name).joined(separator: ", ")).")
        return false
    }

    private func validateJPEG(_ photo: CapturedPhoto) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: photo.url.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(size, 0)
        XCTAssertEqual(size, photo.size)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(photo.url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary))
        XCTAssertEqual(image.width, photo.width)
        XCTAssertEqual(image.height, photo.height)
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
    }

    private func attachEvidence(_ requests: [CaptureRequest]) {
        let epoch = requests.first?.startedAt ?? 0
        var rows: [[String: Any]] = []
        for request in requests {
            var row: [String: Any] = ["request": request.name]
            if let start = request.startedAt { row["startedSeconds"] = start - epoch }
            if let finish = request.finishedAt { row["finishedSeconds"] = finish - epoch }
            if let result = request.result {
                switch result {
                case .success(let photo):
                    row["uri"] = photo.uri
                    row["width"] = photo.width
                    row["height"] = photo.height
                    row["bytes"] = photo.size
                    let attachment = XCTAttachment(contentsOfFile: photo.url)
                    attachment.name = "\(request.name).jpg"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                case .failure(let error):
                    row["error"] = String(describing: error)
                }
            }
            rows.append(row)
        }
        let report: [String: Any] = [
            "device": UIDevice.current.name,
            "model": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "recordedAt": ISO8601DateFormatter().string(from: Date()),
            "flash": "off", "quality": "speed", "deferredStart": false,
            "requests": rows
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.json.identifier)
        attachment.name = "Hardware capture timeline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class CaptureRequest {
    let name: String
    let completed: XCTestExpectation
    let settled: XCTestExpectation
    private(set) var startedAt: TimeInterval?
    private(set) var finishedAt: TimeInterval?
    private(set) var result: Result<CapturedPhoto, Error>?

    init(name: String, camera: CameraView) {
        self.name = name
        completed = XCTestExpectation(description: "\(name) completed")
        settled = XCTestExpectation(description: "\(name) settled")
        completed.assertForOverFulfill = true
        settled.assertForOverFulfill = true
        Task { @MainActor in
            startedAt = ProcessInfo.processInfo.systemUptime
            do { result = .success(try await camera.capture()) } catch { result = .failure(error) }
            finishedAt = ProcessInfo.processInfo.systemUptime
            completed.fulfill()
            settled.fulfill()
        }
    }
}
