import AVFoundation
import Darwin
import ImageIO
import NativeCameraKit
import UIKit
import UniformTypeIdentifiers
import XCTest

@MainActor
final class HardwareCaptureIntegrationTests: XCTestCase {
    func testBackCameraSpeedProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .back, quality: .speed)
    }

    func testBackCameraBalancedProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .back, quality: .balanced)
    }

    func testBackCameraQualityProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .back, quality: .quality)
    }

    func testFrontCameraSpeedProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .front, quality: .speed)
    }

    func testFrontCameraBalancedProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .front, quality: .balanced)
    }

    func testFrontCameraQualityProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .front, quality: .quality)
    }

    func testBackCameraFlashAutoProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .back, quality: .balanced, flash: .auto, requiresFlashSupport: true)
    }

    func testBackCameraFlashOnFiresAndProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .back, quality: .balanced, flash: .on, requiresFlashSupport: true)
    }

    func testBackCameraFlashOffDoesNotFireAndProducesValidJPEG() async throws {
        try await captureFirstJPEG(cameraType: .back, quality: .balanced, flash: .off, requiresFlashSupport: true)
    }

    func testDeferredStartDisabledRecordsFirstJPEGLatency() async throws {
        try await captureFirstJPEG(cameraType: .back, quality: .speed, deferredStart: false,
                                   requiresDeferredStartSupport: true)
    }

    func testDeferredStartEnabledRecordsFirstJPEGLatency() async throws {
        try await captureFirstJPEG(cameraType: .back, quality: .speed, deferredStart: true,
                                   requiresDeferredStartSupport: true)
    }

    func testConcurrentCapturesProduceIndependentJPEGs() async throws {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        let requiresPhysicalDevice = true
        #else
        let requiresPhysicalDevice = false
        #endif
        try XCTSkipIf(requiresPhysicalDevice, "This test requires an iPhone or iPad camera.")
        try XCTSkipUnless(CameraAuthorization.status == .authorized, "Grant camera access before this hardware test.")
        let scene = try await waitForForegroundScene()
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
            attachEvidence(requests, configuration: configuration)
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
        warmup.jpegMetadata = try validateJPEG(try XCTUnwrap(warmup.result).get())

        let first = CaptureRequest(name: "Concurrent 1", camera: camera)
        let second = CaptureRequest(name: "Concurrent 2", camera: camera)
        requests += [first, second]
        guard await finish([first, second], camera: camera) else { return }
        let firstPhoto = try XCTUnwrap(first.result).get()
        let secondPhoto = try XCTUnwrap(second.result).get()
        XCTAssertNotEqual(firstPhoto.url, secondPhoto.url)
        first.jpegMetadata = try validateJPEG(firstPhoto)
        second.jpegMetadata = try validateJPEG(secondPhoto)
        let latestStart = max(try XCTUnwrap(first.startedAt), try XCTUnwrap(second.startedAt))
        let earliestFinish = min(try XCTUnwrap(first.finishedAt), try XCTUnwrap(second.finishedAt))
        XCTAssertLessThan(latestStart, earliestFinish, "Both public capture calls must be in flight at the same time.")
    }

    private func captureFirstJPEG(
        cameraType: CameraType,
        quality: MaxPhotoQualityPrioritization,
        flash: FlashMode = .off,
        requiresFlashSupport: Bool = false,
        deferredStart: Bool = false,
        requiresDeferredStartSupport: Bool = false
    ) async throws {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        throw XCTSkip("This test requires a physical iPhone or iPad camera.")
        #else
        try XCTSkipUnless(CameraAuthorization.status == .authorized, "Grant camera access before this hardware test.")
        if requiresDeferredStartSupport {
            guard #available(iOS 26.0, *) else {
                throw XCTSkip("Deferred output startup requires iOS 26 or later.")
            }
        }
        let position: AVCaptureDevice.Position = cameraType == .front ? .front : .back
        let available = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video, position: position
        ).devices
        try XCTSkipUnless(!available.isEmpty, "This device has no supported \(cameraType) camera.")
        let scene = try await waitForForegroundScene()
        var configuration = CameraConfiguration()
        configuration.cameraType = cameraType
        configuration.flashMode = flash
        configuration.maxPhotoQualityPrioritization = quality
        configuration.iOsDeferredStart = deferredStart
        let fixture = try HardwareCameraFixture(scene: scene, configuration: configuration)
        var requests: [CaptureRequest] = []
        var observations: [String: Any] = [:]
        var startupBeganAt: TimeInterval?
        defer {
            attachEvidence(requests, configuration: configuration, startupBeganAt: startupBeganAt,
                           observations: observations)
            for request in requests {
                if let photo = try? request.result?.get() { try? FileManager.default.removeItem(at: photo.url) }
            }
        }

        do {
            let started = XCTNSNotificationExpectation(name: AVCaptureSession.didStartRunningNotification,
                                                       object: fixture.session)
            startupBeganAt = ProcessInfo.processInfo.systemUptime
            fixture.start()
            let startResult = await XCTWaiter.fulfillment(of: [started], timeout: 15)
            XCTAssertEqual(startResult, .completed, "The camera session did not start within 15 seconds.")
            guard startResult == .completed else {
                await fixture.stop()
                return
            }
            let input = try XCTUnwrap(fixture.session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                .first { $0.device.hasMediaType(.video) })
            let output = try XCTUnwrap(fixture.session.outputs.compactMap { $0 as? AVCapturePhotoOutput }.first)
            XCTAssertEqual(input.device.position, position, "The JPEG must come from the requested camera.")
            let expectedQuality: AVCapturePhotoOutput.QualityPrioritization
            switch quality {
            case .speed: expectedQuality = .speed
            case .balanced: expectedQuality = .balanced
            case .quality: expectedQuality = .quality
            }
            XCTAssertEqual(output.maxPhotoQualityPrioritization, expectedQuality)
            observations = [
                "cameraName": input.device.localizedName,
                "cameraDeviceType": input.device.deviceType.rawValue,
                "cameraPosition": input.device.position.rawValue,
                "outputQuality": output.maxPhotoQualityPrioritization.rawValue,
                "deviceHasFlash": input.device.hasFlash,
                "deviceFlashAvailable": input.device.isFlashAvailable,
                "supportedFlashModes": output.supportedFlashModes.map(\.rawValue)
            ]
            if requiresFlashSupport {
                let requestedFlash: AVCaptureDevice.FlashMode
                switch flash {
                case .auto: requestedFlash = .auto
                case .on: requestedFlash = .on
                case .off: requestedFlash = .off
                }
                try XCTSkipUnless(input.device.hasFlash, "The active camera has no hardware flash.")
                try XCTSkipUnless(output.supportedFlashModes.contains(requestedFlash),
                                  "The active photo output does not support flash mode \(flash).")
                if flash != .off {
                    try XCTSkipUnless(input.device.isFlashAvailable,
                                      "The camera flash is not currently available; no fallback capture is accepted.")
                }
            }
            if #available(iOS 26.0, *) {
                observations["photoOutputDeferredStartSupported"] = output.isDeferredStartSupported
                observations["photoOutputDeferredStartEnabled"] = output.isDeferredStartEnabled
                if requiresDeferredStartSupport {
                    try XCTSkipUnless(output.isDeferredStartSupported,
                                      "The active photo output does not support deferred startup.")
                    XCTAssertEqual(output.isDeferredStartEnabled, deferredStart)
                }
            }

            let request = CaptureRequest(name: "\(cameraType) \(quality) flash=\(flash) deferred=\(deferredStart) first JPEG",
                                         camera: fixture.camera)
            requests.append(request)
            if await finish([request], camera: fixture.camera) {
                request.jpegMetadata = try validateJPEG(try XCTUnwrap(request.result).get())
                if requiresFlashSupport {
                    let flags = try XCTUnwrap(request.jpegMetadata?[kCGImagePropertyExifFlash as String] as? NSNumber,
                                             "The JPEG must report its EXIF Flash field.").uintValue
                    let fired = flags & 1 != 0
                    observations["capturedFlashFired"] = fired
                    if flash == .on { XCTAssertTrue(fired, "Flash On must set the EXIF Flash fired bit.") }
                    if flash == .off { XCTAssertFalse(fired, "Flash Off must leave the EXIF Flash fired bit clear.") }
                }
                let duration = try XCTUnwrap(request.finishedAt) - XCTUnwrap(startupBeganAt)
                XCTAssertGreaterThanOrEqual(duration, 0)
            }
        } catch {
            await fixture.stop()
            throw error
        }
        await fixture.stop()
        #endif
    }

    private func waitForForegroundScene() async throws -> UIWindowScene {
        // Register before checking state so activation cannot be missed between the two steps.
        let activated = XCTNSNotificationExpectation(name: UIScene.didActivateNotification, object: nil)
        activated.handler = { $0.object is UIWindowScene }
        if let scene = foregroundScene { return scene }
        let result = await XCTWaiter.fulfillment(of: [activated], timeout: 10)
        return try XCTUnwrap(result == .completed ? foregroundScene : nil,
                            "The test app did not reach a foreground window scene within 10 seconds (\(result)).")
    }

    private var foregroundScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
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

    private func validateJPEG(_ photo: CapturedPhoto) throws -> [String: Any] {
        let attributes = try FileManager.default.attributesOfItem(atPath: photo.url.path)
        let size = try XCTUnwrap(attributes[.size] as? NSNumber).intValue
        XCTAssertGreaterThan(size, 0)
        XCTAssertEqual(size, photo.size)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(photo.url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        XCTAssertEqual(CGImageSourceGetStatus(source), .statusComplete)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary))
        XCTAssertEqual(image.width, photo.width)
        XCTAssertEqual(image.height, photo.height)
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        var metadata: [String: Any] = ["decodedWidth": image.width, "decodedHeight": image.height]
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyOrientation] {
            metadata[key as String] = properties[key as String]
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware] {
                metadata[key as String] = tiff[key as String]
            }
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            for key in [kCGImagePropertyExifLensModel, kCGImagePropertyExifFocalLength,
                        kCGImagePropertyExifExposureTime, kCGImagePropertyExifISOSpeedRatings, kCGImagePropertyExifFlash] {
                metadata[key as String] = exif[key as String]
            }
        }
        return metadata
    }

    private func attachEvidence(
        _ requests: [CaptureRequest],
        configuration: CameraConfiguration,
        startupBeganAt: TimeInterval? = nil,
        observations: [String: Any] = [:]
    ) {
        let epoch = requests.first?.startedAt ?? 0
        var rows: [[String: Any]] = []
        for request in requests {
            var row: [String: Any] = ["request": request.name]
            if let start = request.startedAt { row["startedSeconds"] = start - epoch }
            if let finish = request.finishedAt { row["finishedSeconds"] = finish - epoch }
            if let start = request.startedAt, let finish = request.finishedAt {
                row["captureMilliseconds"] = (finish - start) * 1_000
            }
            if let start = startupBeganAt, let finish = request.finishedAt {
                row["startupToFirstJPEGMilliseconds"] = (finish - start) * 1_000
            }
            row["jpegMetadata"] = request.jpegMetadata
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
            "modelIdentifier": hardwareIdentifier(),
            "systemVersion": UIDevice.current.systemVersion,
            "recordedAt": ISO8601DateFormatter().string(from: Date()),
            "camera": configuration.cameraType.description,
            "flash": configuration.flashMode.description,
            "quality": configuration.maxPhotoQualityPrioritization.description,
            "deferredStart": configuration.iOsDeferredStart,
            "observedSession": observations,
            "measurement": "Startup is measured from attaching a new CameraView to its first JPEG completion. A single sample does not prove a speed improvement or image quality ranking.",
            "requests": rows
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.json.identifier)
        attachment.name = "Hardware capture timeline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func hardwareIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "unavailable" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &value, &size, nil, 0) == 0 else { return "unavailable" }
        return String(cString: value)
    }
}

@MainActor
private final class HardwareCameraFixture {
    let camera: CameraView
    let session: AVCaptureSession
    private let window: UIWindow
    private let previousWindow: UIWindow?
    private let controller = UIViewController()
    private var receivedStopNotification = false

    init(scene: UIWindowScene, configuration: CameraConfiguration) throws {
        previousWindow = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        controller.view.frame = window.bounds
        camera = CameraView(configuration: configuration)
        camera.frame = controller.view.bounds
        camera.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        session = try XCTUnwrap(Self.previewSession(in: camera.layer), "A real camera preview must expose its session.")
    }

    func start() {
        controller.view.addSubview(camera)
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        camera.start()
    }

    func stop() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let runningBefore = session.isRunning
        let interruptedBefore = session.isInterrupted
        receivedStopNotification = false
        let observer = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStopRunningNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.receivedStopNotification = true }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { [session] _, _ in
            !session.isRunning
        }, object: nil)
        camera.stop()
        camera.removeFromSuperview()
        let result = await XCTWaiter.fulfillment(of: [stopped], timeout: 5)
        let runningAfter = session.isRunning
        let interruptedAfter = session.isInterrupted
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        let report: [String: Any] = [
            "isRunningBefore": runningBefore,
            "isInterruptedBefore": interruptedBefore,
            "isRunningAfter": runningAfter,
            "isInterruptedAfter": interruptedAfter,
            "didStopNotificationReceived": receivedStopNotification,
            "elapsedMilliseconds": elapsedMilliseconds,
            "timeoutSeconds": 5,
            "waitResult": result.rawValue
        ]
        XCTContext.runActivity(named: "Camera session shutdown") { activity in
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.json.identifier)
                attachment.name = "Camera session shutdown.json"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
        XCTAssertTrue(result == .completed && !runningAfter,
                      "The camera session did not stop within 5 seconds. isRunning=\(runningAfter), isInterrupted=\(interruptedAfter), didStopNotificationReceived=\(receivedStopNotification), waitResult=\(result).")
        window.isHidden = true
        previousWindow?.makeKeyAndVisible()
    }

    private static func previewSession(in layer: CALayer) -> AVCaptureSession? {
        if let preview = layer as? AVCaptureVideoPreviewLayer { return preview.session }
        for child in layer.sublayers ?? [] {
            if let session = previewSession(in: child) { return session }
        }
        return nil
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
    var jpegMetadata: [String: Any]?

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
