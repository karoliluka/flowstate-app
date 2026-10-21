import XCTest

/// Drives the real Screen Time flow: grant access, start a focus session, and look at other
/// apps during it and after it. Every step attaches a screenshot and the visible text,
/// so the result can be checked by eye.
///
/// Granting Screen Time access needs the device passcode or Apple Account password, which a test
/// can't type. So once per simulator, by hand: sign in to an Apple Account in the simulator's
/// Settings, open flowstate, tap Allow and finish Apple's prompt. Until then the test skips.
///
/// Run it on its own simulator, not the one you use day to day:
/// `xcodebuild test -scheme Flowstate -only-testing:FlowstateUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
final class BlockingUITests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    override func setUp() {
        continueAfterFailure = true
    }

    func testFocusBlocksAppsUntilTheSessionEnds() throws {
        app.launchArguments = ["-selectedTab", "0"]
        app.launch()

        guard screenTimeAccessGranted() else {
            throw XCTSkip("Screen Time access isn't granted on this simulator. Sign in to an Apple Account in its Settings, open flowstate, tap Allow and finish Apple's passcode prompt by hand, then run again.")
        }

        app.buttons["Start focus"].tap()
        XCTAssertTrue(app.staticTexts["Distracting apps are blocked"].waitForExistence(timeout: 5))
        capture(app, "1 focus · flowstate")

        // Focus: Safari should be shielded.
        safari.activate()
        sleep(3)
        capture(safari, "2 focus · Safari")

        // Settings must stay usable (it's how Screen Time access is revoked), and Date & Time should be locked.
        settings.activate()
        sleep(2)
        capture(settings, "3 focus · Settings")
        if settings.staticTexts["General"].waitForExistence(timeout: 3) {
            settings.staticTexts["General"].tap()
            if settings.staticTexts["Date & Time"].waitForExistence(timeout: 3) {
                settings.staticTexts["Date & Time"].tap()
                sleep(1)
                capture(settings, "4 focus · Date & Time")
            }
        }

        // flowstate itself must not be shielded, or the session couldn't be ended.
        app.activate()
        sleep(2)
        capture(app, "5 focus · back in flowstate")
        XCTAssertTrue(app.staticTexts["Distracting apps are blocked"].exists, "flowstate's session screen isn't reachable")

        // End the session with the hold-to-end button.
        app.activate()
        let endButton = app.descendants(matching: .any)["End session"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.press(forDuration: 2.5)
        XCTAssertTrue(app.buttons["Start focus"].waitForExistence(timeout: 5), "Session didn't end")
        capture(app, "6 ended")

        // After the session: Safari should open normally.
        safari.activate()
        sleep(3)
        capture(safari, "7 after session · Safari")
    }

    // MARK: - Helpers

    /// Taps Allow on the home screen and Continue on Apple's prompt. Access only comes through
    /// if the passcode step was already done by hand on this simulator.
    private func screenTimeAccessGranted() -> Bool {
        let allow = app.buttons["Allow"]
        guard allow.waitForExistence(timeout: 5) else { return true } // already granted
        allow.tap()
        let continueButton = springboard.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 10) {
            continueButton.tap()
        }
        // Granting access opens Allowed apps.
        let done = app.buttons["Done"]
        guard done.waitForExistence(timeout: 15) else {
            capture(app, "0 Screen Time access not granted")
            return false
        }
        capture(app, "0 allowed apps after granting access")
        done.tap()
        return true
    }

    private func capture(_ target: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let texts = target.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        let visibleText = XCTAttachment(string: texts.joined(separator: "\n"))
        visibleText.name = name + " (text)"
        visibleText.lifetime = .keepAlways
        add(visibleText)
    }
}
