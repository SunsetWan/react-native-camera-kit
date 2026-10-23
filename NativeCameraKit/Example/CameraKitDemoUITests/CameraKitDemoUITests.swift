import XCTest

final class CameraKitDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Camera access permission") { alert in
            let message = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
            let cameraPermissionPhrases = [
                "access the camera", "access your camera", "camera access",
                "访问您的相机", "访问相机", "使用相机", "取用相機"
            ]
            guard cameraPermissionPhrases.contains(where: { message.localizedCaseInsensitiveContains($0) }) else {
                return false
            }
            for title in ["Allow", "允许"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
    }

    func testCaptureAndReturnToCamera() {
        let app = XCUIApplication()
        app.launch()
        attachScreenshot("Examples", app: app)
        app.cells["open-camera"].tap()
        let shutter = app.buttons["capture"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        attachScreenshot("Camera", app: app)
        shutter.tap()

        let thumbnail = app.buttons["latest-photo"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: thumbnail)
        waitForExpectations(timeout: 45)
        XCTAssertEqual(app.staticTexts["capture-count"].label, "5 photos")
        XCTAssertTrue(app.staticTexts["camera-status"].label.contains("median capture"))
        thumbnail.tap()
        XCTAssertTrue(app.images["captured-image"].waitForExistence(timeout: 5))
        let dimensions = app.staticTexts["photo-details"].label
        XCTAssertNotNil(dimensions.range(of: #"^[1-9][0-9]* × [1-9][0-9]*"#, options: .regularExpression))
        attachScreenshot("Captured photo", app: app)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()
        let secondPhoto = NSPredicate(format: "label == '10 photos'")
        expectation(for: secondPhoto, evaluatedWith: app.staticTexts["capture-count"])
        waitForExpectations(timeout: 45)
    }

    func testSettingsPersistWhenReopened() {
        let app = XCUIApplication()
        app.launch()
        app.cells["open-camera"].tap()
        app.buttons["settings"].tap()
        let focus = app.switches["Tap to focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        focus.tap()
        XCTAssertEqual(focus.value as? String, "0")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["settings"].tap()
        XCTAssertEqual(app.switches["Tap to focus"].value as? String, "0")
    }

    func testScannerPresetAndReturnToExamples() {
        let app = XCUIApplication()
        app.launch()
        app.cells["open-scanner"].tap()
        XCTAssertTrue(app.staticTexts["camera-status"].label.contains("QR or EAN-13"))
        XCTAssertFalse(app.buttons["capture"].exists)
        attachScreenshot("Barcode Scanner", app: app)
        app.buttons["settings"].tap()
        let scanning = app.switches["Scan barcodes"]
        for _ in 0..<5 where !scanning.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertEqual(scanning.value as? String, "1")
        XCTAssertEqual(app.switches["Show scan frame"].value as? String, "1")
        XCTAssertTrue(app.staticTexts["2 selected"].exists)
        app.navigationBars.buttons["Done"].tap()
        app.navigationBars.buttons["Examples"].tap()
        XCTAssertTrue(app.cells["open-camera"].waitForExistence(timeout: 5))
    }

    func testMountStressStopsAndReleasesCamera() {
        let app = XCUIApplication()
        app.launch()
        app.cells["open-stress-test"].tap()
        let interval = app.textFields["stress-interval"]
        interval.tap()
        interval.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "500")
        app.buttons["start-stress-test"].tap()
        app.alerts.buttons["Start"].tap()
        let status = app.staticTexts["stress-status"]
        expectation(for: NSPredicate(format: "label MATCHES '[2-9] mounts.*'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        attachScreenshot("Mount Stress Test", app: app)
        app.buttons["stop-stress-test"].tap()
        XCTAssertTrue(status.label.hasPrefix("Stopped"))
        XCTAssertFalse(app.otherElements["camera-preview"].exists)
        let stopped = status.label
        let remainsStopped = expectation(for: NSPredicate(format: "label != %@", stopped), evaluatedWith: status)
        remainsStopped.isInverted = true
        waitForExpectations(timeout: 1.5)
        app.navigationBars.buttons["Examples"].tap()
        app.cells["open-camera"].tap()
        XCTAssertTrue(app.buttons["capture"].waitForExistence(timeout: 5))
    }

    func testCameraUsesSourceFaceThrottle() {
        let app = XCUIApplication()
        app.launch()
        app.cells["open-camera"].tap()
        app.buttons["settings"].tap()
        let throttle = app.cells.containing(.staticText, identifier: "Face throttle").firstMatch
        for _ in 0..<8 where !throttle.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertTrue(throttle.isHittable)
        XCTAssertTrue(throttle.staticTexts["50 ms"].exists)
        attachScreenshot("Source face throttle", app: app)
    }

    func testMountStressAcceptsShortPositiveInterval() {
        let app = XCUIApplication()
        app.launch()
        app.cells["open-stress-test"].tap()
        let interval = app.textFields["stress-interval"]
        interval.tap()
        interval.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "50")
        app.buttons["start-stress-test"].tap()
        XCTAssertTrue(app.alerts.buttons["Start"].waitForExistence(timeout: 3))
        app.alerts.buttons["Cancel"].tap()
    }

    func testExplicitUncontrolledZoomSurvivesPinch() {
        let app = XCUIApplication()
        app.launch()
        app.cells["open-camera"].tap()
        app.buttons["settings"].tap()
        let controlled = app.switches["Controlled zoom"]
        for _ in 0..<4 where !controlled.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertEqual(controlled.value as? String, "1")
        controlled.tap()
        app.navigationBars.buttons["Done"].tap()
        app.otherElements["camera-preview"].pinch(withScale: 2, velocity: 1)
        app.buttons["settings"].tap()
        for _ in 0..<4 where !controlled.isHittable { app.tables.firstMatch.swipeUp() }
        XCTAssertEqual(controlled.value as? String, "0")
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
