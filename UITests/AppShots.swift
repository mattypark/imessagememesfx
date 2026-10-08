import XCTest

/// Screenshots the MemeFX app itself (not Messages): the soundboard tab, then the Rooms tab.
final class AppShots: XCTestCase {
    func testTabs() {
        let app = XCUIApplication()
        app.launch()
        snap(app, "app-board")
        app.tabBars.buttons["Rooms"].tap()
        sleep(2)
        snap(app, "app-rooms")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory())
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
