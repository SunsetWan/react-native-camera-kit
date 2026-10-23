import UniformTypeIdentifiers
import XCTest

@MainActor
final class HardwareAcceptanceTests: XCTestCase {
    func testCurrentCameraPreviewForManualReview() throws {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        throw XCTSkip("This check requires a physical iPhone or iPad.")
        #else
        let app = XCUIApplication(bundleIdentifier: "com.sunset.camera-kit.demo")
        try XCTSkipUnless(app.state == .runningForeground, "Open Camera Kit before collecting this evidence.")
        try XCTSkipUnless(app.otherElements["camera-preview"].exists, "Open the camera preview before collecting this evidence.")

        attachEvidence("Current camera for manual review", app: app, note: "Visual review is required. This test does not assert face alignment or orientation.")
        #endif
    }

    // If XCTest cannot launch the app on the host, use devicectl to launch it
    // and open the camera manually before running this test.
    func testHardwareShutterButtonsTriggerOneBurstEach() throws {
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        throw XCTSkip("Hardware shutter buttons require a physical iPhone or iPad.")
        #else
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let buttons: [(name: String, button: XCUIDevice.Button)] = [
            ("Volume up", .volumeUp),
            ("Volume down", .volumeDown),
            ("Camera Control", .camera)
        ]
        let unavailable = buttons.filter { !device.hasHardwareButton($0.button) }.map(\.name)
        try XCTSkipIf(!unavailable.isEmpty, "Required hardware buttons are unavailable: \(unavailable.joined(separator: ", ")).")

        let app = XCUIApplication(bundleIdentifier: "com.sunset.camera-kit.demo")
        if app.state != .runningForeground || !app.otherElements["camera-preview"].exists {
            app.launch()
            XCTAssertTrue(app.cells["open-camera"].waitForExistence(timeout: 5))
            app.cells["open-camera"].tap()
        }
        let shutter = app.buttons["capture"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["camera-preview"].exists)
        XCTAssertTrue(shutter.isEnabled)
        attachEvidence("Before synthesized hardware buttons", app: app, note: "No synthesized hardware button has been pressed yet.")

        for (name, button) in buttons {
            try XCTContext.runActivity(named: "Synthesized \(name) press") { _ in
                let count = app.staticTexts["capture-count"]
                let initialCount = try XCTUnwrap(photoCount(count.label), "The photo count must be readable before pressing \(name).")
                let expectedCount = initialCount + 5
                defer {
                    attachEvidence("After synthesized \(name) press", app: app, note: "Expected \(expectedCount) photos after one XCTest press. This is not a physical human press.")
                }

                device.press(button)
                let burstFinished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    app.state == .runningForeground
                        && (self.photoCount(count.label) ?? -1) >= expectedCount
                        && shutter.isEnabled
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [burstFinished], timeout: 45), .completed,
                               "\(name) must complete one burst and enable the shutter again. Status: \(app.staticTexts["camera-status"].label)")
                XCTAssertEqual(photoCount(count.label), expectedCount, "One \(name) press must save exactly five photos.")

                let extraBurst = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    self.photoCount(count.label) != expectedCount || !shutter.isEnabled
                }, object: nil)
                extraBurst.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [extraBurst], timeout: 1.5), .completed,
                               "One \(name) press must not start another burst after the shutter becomes ready.")
            }
        }
        #endif
    }

    private func photoCount(_ label: String) -> Int? {
        label.split(separator: " ").first.flatMap { Int($0) }
    }

    private func attachEvidence(_ name: String, app: XCUIApplication, note: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let image = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: UTType.png.identifier)
        image.name = "\(name).png"
        image.lifetime = .keepAlways
        add(image)

        let preview = app.otherElements["camera-preview"]
        let shutter = app.buttons["capture"]
        let report = """
        \(note)
        Recorded at: \(ISO8601DateFormatter().string(from: Date()))
        App state: \(app.state.rawValue)
        Device orientation: \(XCUIDevice.shared.orientation.rawValue)
        App frame: \(app.frame)
        Preview frame: \(preview.exists ? String(describing: preview.frame) : "unavailable")
        Shutter frame: \(shutter.exists ? String(describing: shutter.frame) : "unavailable")
        Shutter value: \(shutter.exists ? String(describing: shutter.value) : "unavailable")
        XCTest has no public accessibilityHint property. The hierarchy below is retained without alteration.

        \(app.debugDescription)
        """
        let hierarchy = XCTAttachment(string: report)
        hierarchy.name = "\(name) hierarchy.txt"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
