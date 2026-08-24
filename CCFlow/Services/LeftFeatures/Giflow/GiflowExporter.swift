import Foundation
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

/// GIF & MP4 特效渲染与后台编码导出器
final class GiflowExporter: Sendable {

    // MARK: - GIF 导出

    /// 导出 GIF 任务
    static func exportGIF(
        samples: [GiflowCapturedSample],
        clicks: [GiflowClickEvent],
        keys: [GiflowKeyEvent],
        captureBounds: CGRect,
        outputURL: URL,
        settings: GiflowSettings,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> GiflowRecordingItem {
        guard !samples.isEmpty else {
            throw NSError(domain: "GiflowExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "无可导出的录制帧"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let item = try renderAndEncodeGIF(
                        samples: samples,
                        clicks: clicks,
                        keys: keys,
                        captureBounds: captureBounds,
                        outputURL: outputURL,
                        settings: settings,
                        onProgress: onProgress
                    )
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func renderAndEncodeGIF(
        samples: [GiflowCapturedSample],
        clicks: [GiflowClickEvent],
        keys: [GiflowKeyEvent],
        captureBounds: CGRect,
        outputURL: URL,
        settings: GiflowSettings,
        onProgress: @escaping (Double) -> Void
    ) throws -> GiflowRecordingItem {
        let totalSamples = samples.count
        guard let firstImage = samples.first?.image else {
            throw NSError(domain: "GiflowExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "帧解析失败"])
        }

        let width = firstImage.width
        let height = firstImage.height
        let fps = max(5, min(30, settings.targetFPS))
        let frameDelay = 1.0 / Double(fps)

        // 准备输出目录
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            totalSamples,
            nil
        ) else {
            throw NSError(domain: "GiflowExporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "创建 GIF 导出目标失败"])
        }

        // 全局 GIF 属性：无限循环 (LoopCount = 0)
        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        // 预处理键盘事件按 2 秒窗口归类
        let keyWindows = buildKeyWindows(keys: keys)

        for (index, sample) in samples.enumerated() {
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            ) else { continue }

            // 1. 绘制基础画面
            context.draw(sample.image, in: CGRect(x: 0, y: 0, width: width, height: height))

            // 2. 绘制鼠标红点与扩散涟漪 (0.45 秒生命周期)
            if settings.showClickRipple {
                drawMouseRipples(
                    context: context,
                    timestamp: sample.timestamp,
                    clicks: clicks,
                    captureBounds: captureBounds,
                    frameWidth: width,
                    frameHeight: height
                )
            }

            // 3. 绘制底部键盘 HUD 按键气泡 (每 2 秒平滑轮替)
            if settings.showKeycast {
                drawKeycastHUD(
                    context: context,
                    timestamp: sample.timestamp,
                    keyWindows: keyWindows,
                    frameWidth: width,
                    frameHeight: height
                )
            }

            if let compositedImage = context.makeImage() {
                let frameProperties: [CFString: Any] = [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: frameDelay,
                        kCGImagePropertyGIFUnclampedDelayTime: frameDelay
                    ]
                ]
                CGImageDestinationAddImage(destination, compositedImage, frameProperties as CFDictionary)
            }

            // 更新进度
            let progress = Double(index + 1) / Double(totalSamples)
            onProgress(progress)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "GiflowExporter", code: -3, userInfo: [NSLocalizedDescriptionKey: "GIF 编码文件写入失败"])
        }

        let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let duration = Double(totalSamples) * frameDelay

        return GiflowRecordingItem(
            id: UUID().uuidString,
            name: outputURL.deletingPathExtension().lastPathComponent,
            fileURL: outputURL,
            createdAt: Date(),
            fileSize: Int64(fileSize),
            duration: duration,
            width: width,
            height: height,
            fps: fps
        )
    }

    // MARK: - MP4 导出与转换

    /// 导出 MP4 视频任务
    static func exportMP4(
        samples: [GiflowCapturedSample],
        clicks: [GiflowClickEvent],
        keys: [GiflowKeyEvent],
        captureBounds: CGRect,
        outputURL: URL,
        settings: GiflowSettings,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> GiflowRecordingItem {
        guard !samples.isEmpty else {
            throw NSError(domain: "GiflowExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "无可导出的录制帧"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let item = try renderAndEncodeMP4(
                        samples: samples,
                        clicks: clicks,
                        keys: keys,
                        captureBounds: captureBounds,
                        outputURL: outputURL,
                        settings: settings,
                        onProgress: onProgress
                    )
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func renderAndEncodeMP4(
        samples: [GiflowCapturedSample],
        clicks: [GiflowClickEvent],
        keys: [GiflowKeyEvent],
        captureBounds: CGRect,
        outputURL: URL,
        settings: GiflowSettings,
        onProgress: @escaping (Double) -> Void
    ) throws -> GiflowRecordingItem {
        let totalSamples = samples.count
        guard let firstImage = samples.first?.image else {
            throw NSError(domain: "GiflowExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "帧解析失败"])
        }

        let rawWidth = firstImage.width
        let rawHeight = firstImage.height
        let width = max(2, (rawWidth / 2) * 2)
        let height = max(2, (rawHeight / 2) * 2)

        let fps = max(5, min(60, settings.targetFPS))
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(2_000_000, width * height * fps / 3),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "GiflowExporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法添加视频写入轨道"])
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "GiflowExporter", code: -3, userInfo: [NSLocalizedDescriptionKey: "启动视频写入失败"])
        }

        writer.startSession(atSourceTime: .zero)

        let keyWindows = buildKeyWindows(keys: keys)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        for (index, sample) in samples.enumerated() {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }

            guard let pixelBuffer = createPixelBuffer(width: width, height: height, adaptor: adaptor) else {
                continue
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                if let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue
                ) {
                    context.draw(sample.image, in: CGRect(x: 0, y: 0, width: width, height: height))

                    if settings.showClickRipple {
                        drawMouseRipples(
                            context: context,
                            timestamp: sample.timestamp,
                            clicks: clicks,
                            captureBounds: captureBounds,
                            frameWidth: width,
                            frameHeight: height
                        )
                    }

                    if settings.showKeycast {
                        drawKeycastHUD(
                            context: context,
                            timestamp: sample.timestamp,
                            keyWindows: keyWindows,
                            frameWidth: width,
                            frameHeight: height
                        )
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let frameTime = CMTimeMultiply(frameDuration, multiplier: Int32(index))
            adaptor.append(pixelBuffer, withPresentationTime: frameTime)

            let progress = Double(index + 1) / Double(totalSamples)
            onProgress(progress)
        }

        writerInput.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        var finishError: Error?
        writer.finishWriting {
            finishError = writer.error
            semaphore.signal()
        }
        semaphore.wait()

        if let finishError {
            throw finishError
        }

        let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let duration = Double(totalSamples) / Double(fps)

        return GiflowRecordingItem(
            id: UUID().uuidString,
            name: outputURL.deletingPathExtension().lastPathComponent,
            fileURL: outputURL,
            createdAt: Date(),
            fileSize: Int64(fileSize),
            duration: duration,
            width: width,
            height: height,
            fps: fps
        )
    }

    /// 将已有的 GIF 文件另存/转存为 MP4 文件任务（作为全新独立任务）
    static func convertGIFToMP4(
        gifURL: URL,
        outputURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> GiflowRecordingItem {
        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else {
            throw NSError(domain: "GiflowExporter", code: -4, userInfo: [NSLocalizedDescriptionKey: "无法解析 GIF 文件"])
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw NSError(domain: "GiflowExporter", code: -5, userInfo: [NSLocalizedDescriptionKey: "GIF 不包含有效帧"])
        }

        guard let firstCGImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "GiflowExporter", code: -6, userInfo: [NSLocalizedDescriptionKey: "无法解析首帧"])
        }

        let rawWidth = firstCGImage.width
        let rawHeight = firstCGImage.height
        let width = max(2, (rawWidth / 2) * 2)
        let height = max(2, (rawHeight / 2) * 2)

        var fps: Int = 15
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let gifDict = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            let delay = (gifDict[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gifDict[kCGImagePropertyGIFDelayTime] as? Double)
                ?? 0.066
            if delay > 0.001 {
                fps = max(5, min(60, Int((1.0 / delay).rounded())))
            }
        }

        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(2_000_000, width * height * fps / 3),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "GiflowExporter", code: -7, userInfo: [NSLocalizedDescriptionKey: "无法添加视频轨道"])
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "GiflowExporter", code: -8, userInfo: [NSLocalizedDescriptionKey: "启动写入失败"])
        }
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        for i in 0..<frameCount {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }

            guard let frameImage = CGImageSourceCreateImageAtIndex(source, i, nil),
                  let pixelBuffer = createPixelBuffer(width: width, height: height, adaptor: adaptor) else {
                continue
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                if let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo.rawValue
                ) {
                    context.draw(frameImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let frameTime = CMTimeMultiply(frameDuration, multiplier: Int32(i))
            adaptor.append(pixelBuffer, withPresentationTime: frameTime)

            let progress = Double(i + 1) / Double(frameCount)
            onProgress(progress)
        }

        writerInput.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        var finishError: Error?
        writer.finishWriting {
            finishError = writer.error
            semaphore.signal()
        }
        semaphore.wait()

        if let finishError {
            throw finishError
        }

        let fileSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let duration = Double(frameCount) / Double(fps)

        return GiflowRecordingItem(
            id: UUID().uuidString,
            name: outputURL.deletingPathExtension().lastPathComponent,
            fileURL: outputURL,
            createdAt: Date(),
            fileSize: Int64(fileSize),
            duration: duration,
            width: width,
            height: height,
            fps: fps
        )
    }

    private static func createPixelBuffer(
        width: Int,
        height: Int,
        adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        }
        if pixelBuffer == nil {
            let options: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                options as CFDictionary,
                &pixelBuffer
            )
        }
        return pixelBuffer
    }

    // MARK: - 鼠标点击红点涟漪绘制

    private static func drawMouseRipples(
        context: CGContext,
        timestamp: TimeInterval,
        clicks: [GiflowClickEvent],
        captureBounds: CGRect,
        frameWidth: Int,
        frameHeight: Int
    ) {
        let rippleDuration: TimeInterval = 0.45

        for click in clicks {
            let delta = timestamp - click.timestamp
            guard delta >= 0, delta <= rippleDuration else { continue }

            let progress = delta / rippleDuration // 0.0 -> 1.0

            let scaleX = Double(frameWidth) / Double(captureBounds.width)
            let scaleY = Double(frameHeight) / Double(captureBounds.height)

            let relX = (click.screenPoint.x - captureBounds.minX) * scaleX
            let relY = (click.screenPoint.y - captureBounds.minY) * scaleY

            guard relX >= 0, relX <= Double(frameWidth), relY >= 0, relY <= Double(frameHeight) else { continue }

            context.saveGState()

            // 1. 中心红点
            let dotAlpha = CGFloat(max(0, 1.0 - progress * 0.8))
            let dotRadius: CGFloat = CGFloat(5.0 * (1.0 - progress * 0.2))
            let dotRect = CGRect(x: relX - dotRadius, y: relY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)

            context.setFillColor(click.isRightClick ? NSColor.systemBlue.withAlphaComponent(dotAlpha).cgColor : NSColor.systemRed.withAlphaComponent(dotAlpha).cgColor)
            context.fillEllipse(in: dotRect)

            // 2. 扩散涟漪外环
            let ringAlpha = CGFloat(max(0, 0.85 * (1.0 - progress)))
            let ringRadius: CGFloat = CGFloat(6.0 + 20.0 * progress)
            let ringWidth: CGFloat = CGFloat(max(1.0, 2.5 * (1.0 - progress * 0.4)))
            let ringRect = CGRect(x: relX - ringRadius, y: relY - ringRadius, width: ringRadius * 2, height: ringRadius * 2)

            context.setStrokeColor(click.isRightClick ? NSColor.systemCyan.withAlphaComponent(ringAlpha).cgColor : NSColor.systemRed.withAlphaComponent(ringAlpha).cgColor)
            context.setLineWidth(ringWidth)
            context.strokeEllipse(in: ringRect)

            context.restoreGState()
        }
    }

    // MARK: - 键盘操作 HUD 绘制 (每 2 秒更新)

    private struct KeyWindow {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let displayText: String
    }

    private static func buildKeyWindows(keys: [GiflowKeyEvent]) -> [KeyWindow] {
        guard !keys.isEmpty else { return [] }

        var windows: [KeyWindow] = []
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
                    windows.append(KeyWindow(
                        startTime: Double(slotVal) * 2.0,
                        endTime: Double(slotVal + 1) * 2.0,
                        displayText: text
                    ))
                }
                currentSlot = slot
                currentTokens = []
            }
            currentTokens.append(key.displayText)
        }

        if let slotVal = currentSlot, !currentTokens.isEmpty {
            let text = currentTokens.joined(separator: " ")
            windows.append(KeyWindow(
                startTime: Double(slotVal) * 2.0,
                endTime: Double(slotVal + 1) * 2.0,
                displayText: text
            ))
        }

        return windows
    }

    private static func drawKeycastHUD(
        context: CGContext,
        timestamp: TimeInterval,
        keyWindows: [KeyWindow],
        frameWidth: Int,
        frameHeight: Int
    ) {
        guard let activeWindow = keyWindows.first(where: { timestamp >= $0.startTime && timestamp < $0.endTime }) else {
            return
        }

        let text = activeWindow.displayText
        guard !text.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext

        let fontSize: CGFloat = max(12, min(20, CGFloat(frameWidth) * 0.03))
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let attrString = NSAttributedString(string: text, attributes: textAttrs)
        let textSize = attrString.size()

        let hPadding: CGFloat = 16
        let vPadding: CGFloat = 8
        let badgeWidth = textSize.width + hPadding * 2
        let badgeHeight = textSize.height + vPadding * 2

        let badgeX = (CGFloat(frameWidth) - badgeWidth) / 2.0
        let badgeY: CGFloat = 20.0 // 底部居中，距离底部 20pt

        let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)

        let bgPath = NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8)
        NSColor(white: 0.1, alpha: 0.88).setFill()
        bgPath.fill()

        NSColor(white: 1.0, alpha: 0.25).setStroke()
        bgPath.lineWidth = 1.2
        bgPath.stroke()

        let textRect = CGRect(
            x: badgeX + hPadding,
            y: badgeY + vPadding,
            width: textSize.width,
            height: textSize.height
        )
        attrString.draw(in: textRect)

        NSGraphicsContext.restoreGraphicsState()
    }
}
