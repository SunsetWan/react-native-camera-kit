import XCTest

final class CameraKitDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSimulatorCaptureAndReturnToCamera() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This test validates the simulator JPEG path.")
        #endif
        let app = XCUIApplication()
        app.launch()
        let shutter = app.buttons["capture"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()

        let thumbnail = app.buttons["latest-photo"]
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: thumbnail)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.staticTexts["capture-count"].label, "1 photo")
        thumbnail.tap()
        XCTAssertTrue(app.images["captured-image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["photo-details"].label.contains("480 × 640"))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(shutter.waitForExistence(timeout: 5))
        shutter.tap()
        let secondPhoto = NSPredicate(format: "label == '2 photos'")
        expectation(for: secondPhoto, evaluatedWith: app.staticTexts["capture-count"])
        waitForExpectations(timeout: 10)
    }

    func testSettingsPersistWhenReopened() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["settings"].tap()
        let focus = app.switches["Tap to focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        focus.tap()
        XCTAssertEqual(focus.value as? String, "0")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["settings"].tap()
        XCTAssertEqual(app.switches["Tap to focus"].value as? String, "0")
    }
}
