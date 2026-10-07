import XCTest

/// Drives the real Messages app in the Simulator: opens a chat, opens the MemeFX drawer, picks
/// a pad and sends it both ways (A audio, B card), screenshotting each step into SHOTS_DIR.
final class MessagesShots: XCTestCase {
    private let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")

    private var shotsDir: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory())
    }

    override func setUp() {
        continueAfterFailure = false
    }

    func testSendBothWays() throws {
        messages.launch()
        messages.cells.firstMatch.tap()
        openDrawer()
        snap("1-drawer")

        try sendBoom(as: "A · Audio", step: "a")
        try sendBoom(as: "B · Card", step: "b")
        try slashCommand()
    }

    /// Type "/fa" in the command bar: suggestions show, return sends the top one (/fah).
    private func slashCommand() throws {
        let field = messages.textFields["Sound command"]
        if !field.waitForExistence(timeout: 3) { openDrawer() }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "command bar not found")
        messages.buttons["A · Audio"].tap()
        field.tap()
        sleep(2)
        field.typeText("fa")
        sleep(1)
        snap("5-command")
        field.typeText("\n")
        sleep(4)
        snap("6-command-staged")
        let send = messages.buttons["sendButton"]
        if send.exists && send.isHittable {
            send.tap()
            sleep(4)
        }
        snap("7-command-sent")
    }

    private func sendBoom(as variant: String, step: String) throws {
        let toggle = messages.buttons[variant]
        if !toggle.waitForExistence(timeout: 3) { openDrawer() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "A/B toggle \(variant) not found")
        toggle.tap()

        let pad = messages.buttons["Vine Boom"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5), "Vine Boom pad not found")
        pad.tap()
        sleep(1)
        snap("2\(step)-picked")

        messages.buttons["Send Vine Boom"].tap()
        sleep(4)
        snap("3\(step)-staged")

        // The Simulator has no iMessage account, so MemeFX stages it; send it like a person would.
        let send = messages.buttons["sendButton"]
        if send.exists && send.isHittable {
            send.tap()
            sleep(4)
        }
        snap("4\(step)-sent")
    }

    private func openDrawer() {
        messages.buttons["add"].tap()
        let memefx = messages.cells.matching(NSPredicate(format: "identifier CONTAINS 'com.matthewpark.memefx'")).firstMatch
        var swipes = 0
        while !memefx.isHittable && swipes < 6 {
            messages.cells["Camera"].firstMatch.exists ? messages.cells.element(boundBy: 2).swipeUp() : messages.swipeUp()
            swipes += 1
        }
        if !memefx.isHittable {
            snap("0-no-memefx")
            XCTFail("MemeFX isn't in the app list")
        }
        memefx.tap()
        sleep(3)
    }

    private func snap(_ name: String) {
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: shotsDir.appendingPathComponent("\(name).png"))
        try? messages.debugDescription
            .write(to: shotsDir.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }
}
