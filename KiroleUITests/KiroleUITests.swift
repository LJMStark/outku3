import XCTest

final class KiroleUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertTrue(true)
    }

    @MainActor
    func testScrollToTopButtonAppearsAfterScrollingHome() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSkipOnboarding")
        app.launch()

        let scrollView = app.scrollViews["home.timelineScrollView"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))

        let scrollToTopButton = app.buttons["home.scrollToTopButton"]
        XCTAssertFalse(scrollToTopButton.exists)

        scrollView.swipeUp()
        scrollView.swipeUp()

        XCTAssertTrue(scrollToTopButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testHardwareAndFocusDebugControlsAreReachable() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-uiTestSkipOnboarding")
        app.launch()

        let settingsTab = app.buttons["appHeader.settingsTab"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let settingsScrollView = app.scrollViews["settings.scrollView"]
        XCTAssertTrue(settingsScrollView.waitForExistence(timeout: 5))

        let wifiDebugCard = app.otherElements["Settings_WiFiPCDebugCard"]
        let wifiDebugToggle = app.switches["Settings_WiFiPCDebugToggle"]
        scrollUntilHittable(wifiDebugToggle, in: settingsScrollView)
        XCTAssertTrue(wifiDebugCard.exists)
        XCTAssertTrue(wifiDebugToggle.exists)
        XCTAssertFalse(wifiDebugToggle.isEnabled)

        let testFocusButton = app.buttons["Debug_TestFocusSession"]
        scrollUntilHittable(testFocusButton, in: settingsScrollView)
        XCTAssertTrue(testFocusButton.exists)
        testFocusButton.tap()

        let focusScrollView = app.scrollViews["focus.scrollView"]
        XCTAssertTrue(focusScrollView.waitForExistence(timeout: 5))

        let accelerationToggle = app.switches["focus.debug.accelerationToggle"]
        scrollUntilHittable(accelerationToggle, in: focusScrollView)
        XCTAssertTrue(accelerationToggle.isHittable)
        accelerationToggle.tap()

        let addThirtyMinutes = app.buttons["focus.debug.addThirtyMinutes"]
        scrollUntilHittable(addThirtyMinutes, in: focusScrollView)
        XCTAssertTrue(addThirtyMinutes.isHittable)
        addThirtyMinutes.tap()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        maximumAttempts: Int = 12
    ) {
        for _ in 0..<maximumAttempts where !element.isHittable {
            scrollView.swipeUp()
        }
    }
}
