import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import CC_FLOW

final class GiflowActionTests: XCTestCase {
    func testCopyMissingFilePreservesClipboard() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep previous clipboard", forType: .string)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")

        XCTAssertThrowsError(try GiflowClipboard.write(fileURL: url, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep previous clipboard")
    }

    func testCopyGIFIncludesOriginalAnimationAndFileReference() throws {
        let url = try makeGIF()
        defer { try? FileManager.default.removeItem(at: url) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        try GiflowClipboard.write(fileURL: url, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .fileURL), url.absoluteString)
        XCTAssertEqual(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.gif.identifier)), try Data(contentsOf: url))
        XCTAssertEqual(pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String], [url.path])
    }

    func testConversionCreatesPlayableVideoForOddGIFDimensions() async throws {
        let url = try makeGIF()
        let output = url.deletingPathExtension().appendingPathExtension("mp4")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: output)
        }
        let item = try await GiflowExporter.convertGIFToMP4(gifURL: url, outputURL: output) { _ in }
        XCTAssertEqual(item.width, 16)
        XCTAssertEqual(item.height, 18)
        XCTAssertGreaterThan(item.fileSize, 0)
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(CMTimeGetSeconds(duration), 0)
    }

    private func makeGIF() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        let context = try XCTUnwrap(CGContext(data: nil, width: 17, height: 19, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
        for value in [0.2, 0.8] {
            context.setFillColor(CGColor(gray: value, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 17, height: 19))
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
