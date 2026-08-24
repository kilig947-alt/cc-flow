import Foundation
import Testing

/// Giflow 屏幕录制与 GIF 生成功能逻辑测试
@Suite struct GiflowFeatureTests {

    struct TestClickEvent: Equatable {
        let x: Double
        let y: Double
        let timestamp: Double
        let isRightClick: Bool
    }

    struct TestKeyEvent: Equatable {
        let text: String
        let timestamp: Double
    }

    struct TestKeyWindow: Equatable {
        let startTime: Double
        let endTime: Double
        let displayText: String
    }

    /// 镜像 `GiflowExporter.buildKeyWindows` 2秒窗口聚合逻辑
    func buildKeyWindows(keys: [TestKeyEvent]) -> [TestKeyWindow] {
        guard !keys.isEmpty else { return [] }

        var windows: [TestKeyWindow] = []
        var currentSlot: Int? = nil
        var currentTokens: [String] = []

        for key in keys {
            let slot = Int(key.timestamp / 2.0)
            if currentSlot == nil {
                currentSlot = slot
            }

            if currentSlot != slot {
                if let slotVal = currentSlot, !currentTokens.isEmpty {
                    let text = currentTokens.joined(separator: " ")
                    windows.append(TestKeyWindow(
                        startTime: Double(slotVal) * 2.0,
                        endTime: Double(slotVal + 1) * 2.0,
                        displayText: text
                    ))
                }
                currentSlot = slot
                currentTokens = []
            }
            currentTokens.append(key.text)
        }

        if let slotVal = currentSlot, !currentTokens.isEmpty {
            let text = currentTokens.joined(separator: " ")
            windows.append(TestKeyWindow(
                startTime: Double(slotVal) * 2.0,
                endTime: Double(slotVal + 1) * 2.0,
                displayText: text
            ))
        }

        return windows
    }

    @Test
    func test_按键每2秒聚合为一个HUD气泡() {
        let keys = [
            TestKeyEvent(text: "⌘", timestamp: 0.2),
            TestKeyEvent(text: "C", timestamp: 0.5),
            TestKeyEvent(text: "⌘", timestamp: 2.1),
            TestKeyEvent(text: "V", timestamp: 2.4),
            TestKeyEvent(text: "Enter", timestamp: 4.8)
        ]

        let windows = buildKeyWindows(keys: keys)
        XCTAssertEqual(windows.count, 3)

        XCTAssertEqual(windows[0].startTime, 0.0)
        XCTAssertEqual(windows[0].endTime, 2.0)
        XCTAssertEqual(windows[0].displayText, "⌘ C")

        XCTAssertEqual(windows[1].startTime, 2.0)
        XCTAssertEqual(windows[1].endTime, 4.0)
        XCTAssertEqual(windows[1].displayText, "⌘ V")

        XCTAssertEqual(windows[2].startTime, 4.0)
        XCTAssertEqual(windows[2].endTime, 6.0)
        XCTAssertEqual(windows[2].displayText, "Enter")
    }

    @Test
    func test_鼠标涟漪生命周期判断() {
        let rippleDuration = 0.45
        let click = TestClickEvent(x: 100, y: 100, timestamp: 1.0, isRightClick: false)

        // 帧时间在生命周期内
        let sampleTimeWithin = 1.2
        let deltaWithin = sampleTimeWithin - click.timestamp
        XCTAssertTrue(deltaWithin >= 0 && deltaWithin <= rippleDuration)

        // 帧时间在生命周期外
        let sampleTimeAfter = 1.5
        let deltaAfter = sampleTimeAfter - click.timestamp
        XCTAssertFalse(deltaAfter >= 0 && deltaAfter <= rippleDuration)
    }

    @Test
    func test_格式化时长与文件大小() {
        let duration: TimeInterval = 68.0 // 1分8秒
        let totalSeconds = Int(duration.rounded())
        let formatted = String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
        XCTAssertEqual(formatted, "01:08")

        let bytes: Int64 = 1_572_864 // 1.5 MB
        let formattedSize = String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        XCTAssertEqual(formattedSize, "1.5 MB")
    }
}
