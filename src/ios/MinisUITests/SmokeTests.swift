import XCTest

/// 冒烟测试：在模拟器上验证 App 能启动、主界面正常、关键页面可进
final class SmokeTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// App 启动后应显示会话列表或主界面，不闪退
    func testAppLaunchesWithoutCrashing() throws {
        // 等待主界面出现（最多 30 秒）
        let exists = app.wait(for: .runningForeground, timeout: 30)
        XCTAssertTrue(exists, "App 未能进入前台运行状态")
    }

    /// 设置按钮可点，设置页能打开
    func testSettingsOpens() throws {
        // 找设置齿轮按钮
        let settingsButton = app.buttons["Settings"].firstMatch
        if settingsButton.waitForExistence(timeout: 10) {
            settingsButton.tap()
            // 设置页标题应出现
            let settingsTitle = app.navigationBars["设置"].firstMatch
            XCTAssertTrue(
                settingsTitle.waitForExistence(timeout: 10) ||
                app.navigationBars["Settings"].firstMatch.waitForExistence(timeout: 5),
                "设置页未能打开"
            )
        }
    }

    /// 会话列表有内容时，点击应能进入（不验证具体内容，只验证不崩）
    func testSessionListTappable() throws {
        // 等待列表加载
        sleep(3)
        let cells = app.cells
        if cells.count > 0 {
            cells.firstMatch.tap()
            // 点完不断言具体页面，只确保没崩
            XCTAssertTrue(app.state == .runningForeground, "点击会话后 App 异常")
        }
    }
}
