import Foundation
import CoreGraphics
import AppKit

/// 选区模式
enum GiflowSelectionKind: String, Codable, CaseIterable, Identifiable {
    case area
    case fullScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .area: return "区域截取"
        case .fullScreen: return "全屏截取"
        }
    }
}

/// 媒体导出格式
enum GiflowMediaFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case gif
    case mp4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gif: return "GIF"
        case .mp4: return "MP4"
        }
    }

    var fileExtension: String {
        rawValue
    }
}

/// 录制捕获模式与几何区域
enum GiflowCaptureMode: Equatable {
    case selection(CGRect) // 屏幕绝对坐标 (Cocoa / NSScreen 坐标系)
    case fullScreen(displayID: CGDirectDisplayID, bounds: CGRect)

    var bounds: CGRect {
        switch self {
        case .selection(let rect): return rect
        case .fullScreen(_, let bounds): return bounds
        }
    }
}

/// 录制过程中的鼠标点击事件
struct GiflowClickEvent: Equatable, Sendable {
    let screenPoint: CGPoint // 屏幕绝对坐标
    let timestamp: TimeInterval // 相对录制开始的时间（秒）
    let isRightClick: Bool
}

/// 录制过程中的键盘按键事件
struct GiflowKeyEvent: Equatable, Sendable {
    let displayText: String // 如 "⌘ C", "Enter", "Space" 等
    let timestamp: TimeInterval // 相对录制开始的时间（秒）
}

/// 录制捕获的单帧（内存缓冲区）
struct GiflowCapturedSample: Sendable {
    let image: CGImage
    let timestamp: TimeInterval
}

/// 已保存的 GIF / MP4 录制记录模型
struct GiflowRecordingItem: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var name: String
    let fileURL: URL
    let createdAt: Date
    var fileSize: Int64
    var duration: TimeInterval
    var width: Int
    var height: Int
    var fps: Int

    var format: GiflowMediaFormat {
        if fileURL.pathExtension.lowercased() == "mp4" {
            return .mp4
        }
        return .gif
    }

    var formattedDuration: String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var formattedFileSize: String {
        let bytes = Double(fileSize)
        if bytes < 1024 {
            return "\(fileSize) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", bytes / 1024)
        } else {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        }
    }

    var formattedResolution: String {
        "\(width) × \(height)"
    }
}

/// 录制偏好配置
struct GiflowSettings: Codable, Equatable {
    var targetFPS: Int = 15
    var showClickRipple: Bool = true
    var showKeycast: Bool = true
    var maxScaleFactor: Double = 1.0 // 1.0 = 标准 1x 像素以保持较小体积，2.0 = Retina 2x

    static let `default` = GiflowSettings()
}
