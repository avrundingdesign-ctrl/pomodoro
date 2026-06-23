import XCTest

extension XCUIApplication {
    /// Launch a fresh app instance with the given UI-test hooks.
    @discardableResult
    static func launch(arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        for (k, v) in environment { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }
}

extension XCTestCase {
    /// Assert an element appears within `timeout` and return it.
    @discardableResult
    func require(_ element: XCUIElement, _ message: String = "", timeout: TimeInterval = 8,
                 file: StaticString = #file, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      message.isEmpty ? "Expected element to exist" : message,
                      file: file, line: line)
        return element
    }

    /// Wait until a static text's label differs from `value` (e.g. the timer ticked).
    func waitForLabelChange(_ element: XCUIElement, from value: String,
                            timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label != value { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}
