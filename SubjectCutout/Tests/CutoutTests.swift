//
//  CutoutTests.swift
//  SubjectCutout
//
//  Created by YOOJUN PARK on 10/23/26.
//

import CoreImage
import CoreVideo
import ImageIO
import SwiftUI
import UIKit
import XCTest
@testable import SubjectCutout

final class CutoutTests: XCTestCase {
    @MainActor
    func testTapDeselectsAndUndoRestoresTheSubject() async throws {
        let session = CutoutSession(image: UIImage())
        let subject = CutoutSession.Subject(id: UUID(), number: 1, mask: try sampleMask())
        session.subjects = [subject]
        session.isReady = true

        session.tap(CGPoint(x: 0.2, y: 0.1))
        await session.setQuality(.balanced)
        XCTAssertTrue(session.subjects.isEmpty)
        XCTAssertTrue(session.canUndo)

        session.undo()
        await session.setQuality(.balanced)
        XCTAssertEqual(session.subjects.map(\.id), [subject.id])
        XCTAssertTrue(session.subjects[0].mask.contains(CGPoint(x: 0.2, y: 0.1)))
        XCTAssertFalse(session.canUndo)

        session.scribble([CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.3, y: 0.1)])
        XCTAssertFalse(session.isBusy)
        XCTAssertEqual(session.subjects.count, 1)
    }

    func testDuplicateDetectionUsesMaskPixelsRatherThanBounds() throws {
        let first = try Mask(grayscaleImage(width: 4, height: 4, pixels: [
            255, 0, 255, 0, 0, 255, 0, 255, 255, 0, 255, 0, 0, 255, 0, 255
        ]))
        let second = try Mask(grayscaleImage(width: 4, height: 4, pixels: [
            0, 255, 0, 255, 255, 0, 255, 0, 0, 255, 0, 255, 255, 0, 255, 0
        ]))
        let both = try Mask(grayscaleImage(width: 4, height: 4, pixels: Array(repeating: 255, count: 16)))
        XCTAssertEqual(first.bounds, second.bounds)
        XCTAssertTrue(first.isCovered(by: [first]))
        XCTAssertFalse(first.isCovered(by: []))
        XCTAssertFalse(first.isCovered(by: [second]))
        XCTAssertFalse(both.isCovered(by: [first]))
        XCTAssertTrue(both.isCovered(by: [first, second]))
    }

    func testSelectionOutlinePreservesHolesAndTheOriginalMask() async throws {
        var pixels = [UInt8](repeating: 0, count: 81)
        for y in 1...7 {
            for x in 1...7 { pixels[y * 9 + x] = 255 }
        }
        pixels[4 * 9 + 4] = 0
        let mask = try Mask(grayscaleImage(width: 9, height: 9, pixels: pixels))
        let outline = try await mask.makeOutline()
        let alpha = try alphaValues(outline)
        XCTAssertEqual(alpha[0], 0)
        XCTAssertEqual(alpha[4 * 9 + 1], 255)
        XCTAssertEqual(alpha[2 * 9 + 2], 0)
        XCTAssertEqual(alpha[4 * 9 + 4], 255)
        XCTAssertTrue(mask.contains(CGPoint(x: 2.5 / 9, y: 2.5 / 9)))
        XCTAssertFalse(mask.contains(CGPoint(x: 4.5 / 9, y: 4.5 / 9)))
    }

    func testDeferredThumbnailPreservesPositionColorAndTransparency() async throws {
        let source = try sourceImage(width: 4, height: 4)
        let mask = try Mask(grayscaleImage(width: 4, height: 4, pixels: [
            0, 0, 0, 0,
            0, 255, 255, 0,
            0, 255, 0, 0,
            0, 0, 0, 0
        ]))
        let thumbnail = try await mask.makeThumbnail(from: source)
        XCTAssertEqual(thumbnail.width, 2)
        XCTAssertEqual(thumbnail.height, 2)
        XCTAssertEqual(try alphaValues(thumbnail), [255, 255, 255, 0])
        let pixels = try rgbaValues(thumbnail)
        XCTAssertEqual(Array(pixels[0..<4]), [255, 255, 0, 255])
        XCTAssertEqual(Array(pixels[4..<8]), [0, 255, 0, 255])
        XCTAssertEqual(Array(pixels[8..<12]), [255, 0, 0, 255])
    }

    @MainActor
    func testDeferredRenderingCanBeCancelled() async throws {
        let mask = try sampleMask()
        let source = try sourceImage(width: 16, height: 12)
        let tasks = [
            Task { try await mask.makeOutline() },
            Task { try await mask.makeThumbnail(from: source) }
        ]
        for task in tasks { task.cancel() }
        for task in tasks {
            switch await task.result {
            case .success: XCTFail("Expected cancellation")
            case let .failure(error): XCTAssertTrue(error is CancellationError)
            }
        }
    }

    @MainActor
    func testPhotoCanvasKeepsCoordinatesAlignedAfterZoomAndPan() throws {
        let canvas = PhotoCanvas(content: AnyView(Color.clear), contentSize: CGSize(width: 300, height: 150),
                                 isEnabled: true, allowsDrawing: true,
                                 onTap: { _ in }, onStroke: { _, _ in })
        let controller = PhotoCanvas.Controller(canvas: canvas)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 300, height: 500)
        controller.viewDidLayoutSubviews()
        XCTAssertEqual(controller.scrollView.panGestureRecognizer.minimumNumberOfTouches, 2)
        XCTAssertEqual(controller.drawing.maximumNumberOfTouches, 1)
        XCTAssertEqual(controller.host.view.bounds.size, canvas.contentSize)
        XCTAssertEqual(controller.scrollView.contentInset.top, 175)
        let layout = ImageLayout(imageSize: CGSize(width: 400, height: 200),
                                 availableSize: canvas.contentSize)
        controller.scrollView.setZoomScale(3, animated: false)
        controller.scrollView.contentOffset = CGPoint(x: 120, y: 160)
        let expected = CGPoint(x: 0.6, y: 0.4)
        let visible = controller.scrollView.convert(layout.displayPoint(expected), from: controller.host.view)
        let content = controller.host.view.convert(visible, from: controller.scrollView)
        let actual = try XCTUnwrap(layout.normalizedPoint(content))
        XCTAssertEqual(controller.scrollView.zoomScale, 3)
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001)
    }

    @MainActor
    func testEmptySelectionCanFinish() async {
        let session = CutoutSession(image: UIImage())
        session.isReady = true
        var result: [Cutout]?

        session.save(to: FileManager.default.temporaryDirectory) { result = $0 }

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isEmpty == true)
    }

    func testPhotoUsesUprightPixelSizeForRotatedImages() throws {
        let source = try grayscaleImage(width: 4, height: 2, pixels: Array(repeating: 255, count: 8))
        for orientation in [UIImage.Orientation.left, .leftMirrored, .right, .rightMirrored] {
            let image = UIImage(cgImage: source, scale: 2, orientation: orientation)
            XCTAssertEqual(CutoutPhoto.sourceSize(for: image), CGSize(width: 2, height: 4))
        }
        for orientation in [UIImage.Orientation.up, .upMirrored, .down, .downMirrored] {
            let image = UIImage(cgImage: source, scale: 2, orientation: orientation)
            XCTAssertEqual(CutoutPhoto.sourceSize(for: image), CGSize(width: 4, height: 2))
        }
    }

    func testPreviewAlignsSubjectWithinPaddedCrop() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("subject.png")
        let cutout = Cutout(
            id: UUID(), url: url, cropURL: url,
            bounds: CGRect(x: 30, y: 50, width: 40, height: 20),
            cropBounds: CGRect(x: 20, y: 40, width: 80, height: 40)
        )
        let layout = ImageLayout(
            imageSize: cutout.cropBounds.size, availableSize: CGSize(width: 320, height: 240)
        )

        XCTAssertEqual(layout.rect, CGRect(x: 0, y: 40, width: 320, height: 160))
        XCTAssertEqual(
            CutoutPreview.subjectFrame(for: cutout, inside: layout.rect),
            CGRect(x: 40, y: 80, width: 160, height: 80)
        )
    }

    func testImageLayoutRejectsLetterboxingAndConvertsPoints() throws {
        let layout = ImageLayout(
            imageSize: CGSize(width: 400, height: 200),
            availableSize: CGSize(width: 300, height: 300)
        )

        XCTAssertEqual(layout.rect, CGRect(x: 0, y: 75, width: 300, height: 150))
        XCTAssertNil(layout.normalizedPoint(CGPoint(x: 150, y: 74)))
        XCTAssertNil(layout.normalizedPoint(CGPoint(x: 150, y: 226)))

        let point = CGPoint(x: 0.25, y: 0.75)
        let converted = try XCTUnwrap(layout.normalizedPoint(layout.displayPoint(point)))
        XCTAssertEqual(converted.x, point.x, accuracy: 0.0001)
        XCTAssertEqual(converted.y, point.y, accuracy: 0.0001)

        let portrait = ImageLayout(
            imageSize: CGSize(width: 200, height: 400),
            availableSize: CGSize(width: 300, height: 300)
        )
        XCTAssertEqual(portrait.rect, CGRect(x: 75, y: 0, width: 150, height: 300))
        XCTAssertNil(portrait.normalizedPoint(CGPoint(x: 74, y: 150)))
        XCTAssertNil(ImageLayout(imageSize: .zero, availableSize: CGSize(width: 100, height: 100))
            .normalizedPoint(.zero))
    }

    func testMaskUsesTopLeftCoordinates() throws {
        let image = try grayscaleImage(width: 4, height: 3, pixels: [
            255, 255, 0, 0,
            255,   0, 0, 0,
              0,   0, 0, 0
        ])
        let mask = try Mask(image)

        XCTAssertEqual(mask.bounds, CGRect(x: 0, y: 0, width: 0.5, height: 2.0 / 3.0))
        XCTAssertTrue(mask.contains(CGPoint(x: 0.125, y: 1.0 / 6.0)))
        XCTAssertTrue(mask.contains(CGPoint(x: 0.375, y: 1.0 / 6.0)))
        XCTAssertFalse(mask.contains(CGPoint(x: 0.375, y: 0.5)))
        XCTAssertFalse(mask.contains(CGPoint(x: 0.125, y: 5.0 / 6.0)))
        XCTAssertFalse(mask.contains(CGPoint(x: -0.1, y: 0)))
        XCTAssertFalse(mask.contains(CGPoint(x: 0, y: 1.1)))
    }

    func testMaskBoundsMatchReferenceScan() throws {
        let width = 17
        let height = 11
        var singlePixel = [UInt8](repeating: 0, count: width * height)
        singlePixel[5 * width + 8] = 9
        var edges = [UInt8](repeating: 8, count: width * height)
        edges[width - 1] = 255
        edges[(height - 1) * width] = 9
        let levels: [UInt8] = [0, 8, 9, 127, 128, 255]
        let fixtures = [
            [UInt8](repeating: 0, count: width * height),
            [UInt8](repeating: 8, count: width * height),
            [UInt8](repeating: 9, count: width * height),
            singlePixel,
            edges,
            (0..<(width * height)).map { levels[($0 * 13 + $0 / width * 7) % levels.count] }
        ]

        for pixels in fixtures {
            let image = try grayscaleImage(width: width, height: height, pixels: pixels)
            let indices = pixels.indices.filter { pixels[$0] > 8 }
            guard let first = indices.first else {
                XCTAssertThrowsError(try Mask(image)) {
                    guard let error = $0 as? CutoutError, case .noSubject = error else {
                        return XCTFail("Expected noSubject, received \($0)")
                    }
                }
                continue
            }
            let expected = indices.dropFirst().reduce(
                CGRect(x: first % width, y: first / width, width: 1, height: 1)
            ) { bounds, index in
                bounds.union(CGRect(x: index % width, y: index / width, width: 1, height: 1))
            }
            let mask = try Mask(image)
            XCTAssertEqual(mask.bounds, CGRect(
                x: expected.minX / CGFloat(width), y: expected.minY / CGFloat(height),
                width: expected.width / CGFloat(width), height: expected.height / CGFloat(height)
            ))
        }

        let single = try Mask(grayscaleImage(width: 1, height: 1, pixels: [9]))
        XCTAssertEqual(single.bounds, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testMaskOverlayPreservesAlphaValues() throws {
        let pixels: [UInt8] = [0, 8, 9, 127, 128, 192, 254, 255]
        let mask = try Mask(grayscaleImage(width: 4, height: 2, pixels: pixels))

        XCTAssertEqual(mask.overlay.width, mask.image.width)
        XCTAssertEqual(mask.overlay.height, mask.image.height)
        XCTAssertNil(mask.overlay.colorSpace)
        XCTAssertEqual(try alphaValues(mask.overlay), pixels)
    }

    func testScribbleUsesTopLeftCoordinates() throws {
        let scribble = try Segmenter.scribbleBuffer(
            [CGPoint(x: 0.25, y: 0.2), CGPoint(x: 0.75, y: 0.2)], width: 64, height: 64
        )
        let samples = try scribble.withUnsafeBuffer { buffer in
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
                .assumingMemoryBound(to: UInt8.self)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            return (0..<64).map { address[$0 * bytesPerRow + 32] }
        }

        XCTAssertTrue(samples[10...15].contains { $0 > 200 })
        XCTAssertTrue(samples[48...54].allSatisfy { $0 == 0 })
    }

    func testSavePreservesPixelBoundsAndTransparency() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try sourceImage(width: 16, height: 12)
        let mask = try sampleMask()
        let id = UUID()
        let results = try Cutout.save(
            [(id, mask)], image: source, directory: directory, context: CIContext()
        )

        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(result.id, id)
        XCTAssertEqual(result.number, 1)
        XCTAssertEqual(result.bounds, CGRect(x: 2, y: 0, width: 12, height: 8))
        XCTAssertEqual(result.cropBounds, CGRect(x: 0, y: 0, width: 16, height: 10))
        XCTAssertEqual(result.url.pathExtension, "png")
        XCTAssertEqual(result.cropURL.lastPathComponent, "\(id.uuidString)-crop.png")
        XCTAssertEqual(result.url.deletingLastPathComponent().deletingLastPathComponent(), directory)
        XCTAssertEqual(result.cropURL.deletingLastPathComponent(), result.url.deletingLastPathComponent())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            atPath: result.url.deletingLastPathComponent().path
        ).count, 2)

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(result.url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(image.width, 12)
        XCTAssertEqual(image.height, 8)
        let alpha = try alphaValues(image)
        XCTAssertTrue(alpha.contains { $0 < 8 })
        XCTAssertTrue(alpha.contains { $0 > 247 })
    }

    func testOriginalCropPreservesPixelsAndClipsToPhoto() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try sourceImage(width: 20, height: 20)
        let context = CIContext()
        let fixtures = [
            (5, CGRect(x: 4, y: 4, width: 7, height: 7)),
            (15, CGRect(x: 14, y: 14, width: 6, height: 6))
        ]

        for (index, expectedBounds) in fixtures {
            var pixels = [UInt8](repeating: 0, count: 16)
            pixels[index] = 255
            let mask = try Mask(grayscaleImage(width: 4, height: 4, pixels: pixels))
            let results = try Cutout.save(
                [(UUID(), mask)], image: source, directory: directory, context: context
            )
            let result = try XCTUnwrap(results.first)
            XCTAssertEqual(result.cropBounds, expectedBounds)
            let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(result.cropURL as CFURL, nil))
            let crop = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            let expected = try XCTUnwrap(source.cropping(to: expectedBounds))
            XCTAssertEqual(crop.width, expected.width)
            XCTAssertEqual(crop.height, expected.height)
            XCTAssertEqual(try rgbaValues(crop), try rgbaValues(expected))
            XCTAssertTrue(try alphaValues(crop).allSatisfy { $0 == 255 })
        }
    }

    func testSaveRejectsNoSelectionAndNonFileDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try sourceImage(width: 16, height: 12)
        let context = CIContext()

        XCTAssertThrowsError(try Cutout.save([], image: image, directory: directory, context: context)) {
            guard let error = $0 as? CutoutError, case .noSelection = error else {
                return XCTFail("Expected noSelection, received \($0)")
            }
        }
        let remote = try XCTUnwrap(URL(string: "https://example.com/cutouts"))
        let mask = try sampleMask()
        XCTAssertThrowsError(try Cutout.save(
            [(UUID(), mask)], image: image, directory: remote, context: context
        )) {
            guard let error = $0 as? CutoutError, case .invalidDirectory = error else {
                return XCTFail("Expected invalidDirectory, received \($0)")
            }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testSaveFailureRemovesOnlyItsBatch() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = FileManager.default
        let existing = directory.appendingPathComponent("existing", isDirectory: true)
        try files.createDirectory(at: existing, withIntermediateDirectories: false)
        let marker = existing.appendingPathComponent("keep.txt")
        let contents = Data("keep".utf8)
        try contents.write(to: marker)
        let other = directory.appendingPathComponent("unrelated.txt")
        try contents.write(to: other)

        let context = FailingContext()
        context.failureOnWrite = 4
        let image = try sourceImage(width: 16, height: 12)
        let mask = try sampleMask()
        XCTAssertThrowsError(try Cutout.save(
            [(UUID(), mask), (UUID(), mask)], image: image, directory: directory, context: context
        ))

        XCTAssertEqual(context.writes, 4)
        XCTAssertEqual(Set(try files.contentsOfDirectory(atPath: directory.path)), ["existing", "unrelated.txt"])
        XCTAssertEqual(try Data(contentsOf: marker), contents)
        XCTAssertEqual(try Data(contentsOf: other), contents)
    }

    func testCancelledSaveRemovesItsBatch() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try sourceImage(width: 16, height: 12)
        let mask = try sampleMask()

        let context = FailingContext()
        context.cancelsAfterWrite = true

        let task = Task {
            return try Cutout.save(
                [(UUID(), mask)], image: source, directory: directory, context: context
            )
        }
        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
        }
        XCTAssertEqual(context.writes, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func sampleMask() throws -> Mask {
        try Mask(grayscaleImage(width: 8, height: 6, pixels: [
            0, 255, 255, 0, 0, 0, 255, 0,
            0, 255, 255, 0, 0, 0,   0, 0,
            0, 255, 0, 0, 0, 0,   0, 0,
            0, 255, 0, 0, 0, 0, 255, 0,
            0,   0, 0, 0, 0, 0,   0, 0,
            0,   0, 0, 0, 0, 0,   0, 0
        ]))
    }

    private func grayscaleImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func sourceImage(width: Int, height: Int) throws -> CGImage {
        let pixels = (0..<height).flatMap { y in
            (0..<width).flatMap { x -> [UInt8] in
                [x < width / 2 ? 255 : 0, y < height / 2 ? 255 : 0, 0, 255]
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    private func alphaValues(_ image: CGImage) throws -> [UInt8] {
        let pixels = try rgbaValues(image)
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    private func rgbaValues(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drawn)
        return pixels
    }
}

private final class FailingContext: CIContext, @unchecked Sendable {
    private(set) var writes = 0
    var failureOnWrite = 2
    var cancelsAfterWrite = false

    override func writePNGRepresentation(
        of image: CIImage, to url: URL, format: CIFormat, colorSpace: CGColorSpace,
        options: [CIImageRepresentationOption: Any] = [:]
    ) throws {
        writes += 1
        if writes == failureOnWrite { throw CocoaError(.fileWriteUnknown) }
        try super.writePNGRepresentation(
            of: image, to: url, format: format, colorSpace: colorSpace, options: options
        )
        if cancelsAfterWrite { withUnsafeCurrentTask { $0?.cancel() } }
    }
}
