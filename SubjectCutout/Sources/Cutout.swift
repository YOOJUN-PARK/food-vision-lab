//
//  Cutout.swift
//  SubjectCutout
//
//  Created by YOOJUN PARK on 10/23/26.
//

import CoreImage.CIFilterBuiltins
import Foundation

public struct Cutout: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let cropURL: URL
    /// Bounds in upright image pixels, with the origin at the top-left corner.
    public let bounds: CGRect
    public let cropBounds: CGRect
    public internal(set) var number = 1
}

extension Cutout {
    public init(id: UUID, number: Int, bounds: CGRect, cropBounds: CGRect, directory: URL) {
        self.init(
            id: id,
            url: directory.appendingPathComponent(id.uuidString).appendingPathExtension("png"),
            cropURL: directory.appendingPathComponent("\(id.uuidString)-crop.png"),
            bounds: bounds, cropBounds: cropBounds, number: number
        )
    }

    static func save(
        _ subjects: [(id: UUID, mask: Mask)],
        image: CGImage,
        directory: URL,
        context: CIContext
    ) throws -> [Cutout] {
        guard !subjects.isEmpty else { throw CutoutError.noSelection }
        guard directory.isFileURL else { throw CutoutError.invalidDirectory }

        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let batch = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: batch, withIntermediateDirectories: false)

        do {
            let source = CIImage(cgImage: image)
            let background = CIImage(color: .clear).cropped(to: source.extent)
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                throw CutoutError.renderingFailed
            }

            let cutouts = try subjects.enumerated().map { index, subject in
                try Task.checkCancellation()
                let mask = CIImage(cgImage: subject.mask.image).transformed(by: CGAffineTransform(
                    scaleX: source.extent.width / CGFloat(subject.mask.image.width),
                    y: source.extent.height / CGFloat(subject.mask.image.height)
                ))
                let filter = CIFilter.blendWithMask()
                filter.inputImage = source
                filter.backgroundImage = background
                filter.maskImage = mask

                let normalized = subject.mask.bounds
                let bounds = CGRect(
                    x: normalized.minX * source.extent.width,
                    y: normalized.minY * source.extent.height,
                    width: normalized.width * source.extent.width,
                    height: normalized.height * source.extent.height
                ).integral.intersection(source.extent)
                let cropBounds = bounds.insetBy(
                    dx: -bounds.width * 0.15, dy: -bounds.height * 0.15
                ).integral.intersection(source.extent)
                guard let output = filter.outputImage, !bounds.isEmpty else {
                    throw CutoutError.renderingFailed
                }

                let cutout = Cutout(
                    id: subject.id, number: index + 1, bounds: bounds, cropBounds: cropBounds, directory: batch
                )
                for (destination, image, bounds) in [
                    (cutout.url, output, bounds), (cutout.cropURL, source, cropBounds)
                ] {
                    try Task.checkCancellation()
                    let crop = CGRect(
                        x: bounds.minX, y: source.extent.height - bounds.maxY,
                        width: bounds.width, height: bounds.height
                    )
                    try context.writePNGRepresentation(
                        of: image.cropped(to: crop), to: destination, format: .RGBA8, colorSpace: colorSpace
                    )
                }
                return cutout
            }
            try Task.checkCancellation()
            return cutouts
        } catch {
            try? files.removeItem(at: batch)
            throw error
        }
    }
}

struct Mask: Sendable {
    static let outlineScale = 180

    let image: CGImage
    let overlay: CGImage
    let bounds: CGRect
    private let pixels: Data

    init(_ image: CGImage) throws {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        let overlay = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: nil, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.alphaOnly.rawValue)
            )?.makeImage()
        }
        guard let overlay else { throw CutoutError.renderingFailed }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            let row = y * width
            var left = 0
            while left < width, bytes[row + left] <= 8 { left += 1 }
            guard left < width else { continue }
            var right = width - 1
            while right > left, bytes[row + right] <= 8 { right -= 1 }
            minX = min(minX, left)
            minY = min(minY, y)
            maxX = max(maxX, right)
            maxY = y
        }
        guard maxX >= minX, maxY >= minY else { throw CutoutError.noSubject }

        let pixels = Data(bytes)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let mask = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { throw CutoutError.renderingFailed }

        self.image = mask
        self.overlay = overlay
        self.pixels = pixels
        self.bounds = CGRect(
            x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
    }

    @concurrent
    func makeOutline() async throws -> CGImage {
        try Task.checkCancellation()
        let width = image.width
        let height = image.height
        let radius = max(1, min(width, height) / Self.outlineScale)
        let outline = try pixels.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var edges = [UInt8](repeating: 0, count: bytes.count)
            func isInside(_ x: Int, _ y: Int) -> Bool {
                x >= 0 && x < width && y >= 0 && y < height && bytes[y * width + x] >= 128
            }
            for y in 0..<height {
                try Task.checkCancellation()
                for x in 0..<width {
                    let inside = bytes[y * width + x] >= 128
                    if isInside(x - radius, y) != inside || isInside(x + radius, y) != inside
                        || isInside(x, y - radius) != inside || isInside(x, y + radius) != inside {
                        edges[y * width + x] = 255
                    }
                }
            }
            return edges.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width, space: nil,
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.alphaOnly.rawValue))?.makeImage()
            }
        }
        guard let outline else { throw CutoutError.renderingFailed }
        return outline
    }

    @concurrent
    func makeThumbnail(from source: CGImage) async throws -> CGImage {
        try Task.checkCancellation()
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let crop = CGRect(x: bounds.minX * rect.width, y: bounds.minY * rect.height,
                          width: bounds.width * rect.width, height: bounds.height * rect.height)
            .integral.intersection(rect)
        let scale = min(1, 144 / max(crop.width, crop.height))
        let width = max(1, Int(ceil(crop.width * scale)))
        let height = max(1, Int(ceil(crop.height * scale)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { throw CutoutError.renderingFailed }
        context.interpolationQuality = .medium
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -crop.minX, y: -(rect.height - crop.maxY))
        context.clip(to: rect, mask: overlay)
        context.draw(source, in: rect)
        try Task.checkCancellation()
        guard let image = context.makeImage() else { throw CutoutError.renderingFailed }
        return image
    }

    func contains(_ point: CGPoint) -> Bool {
        guard (0...1).contains(point.x), (0...1).contains(point.y) else { return false }
        let x = min(Int(point.x * CGFloat(image.width)), image.width - 1)
        let y = min(Int(point.y * CGFloat(image.height)), image.height - 1)
        return pixels[y * image.width + x] >= 128
    }

    func isCovered(by masks: [Mask]) -> Bool {
        guard !masks.isEmpty else { return false }
        let width = image.width
        let height = image.height
        let step = max(1, Int(max(bounds.width * CGFloat(width), bounds.height * CGFloat(height))) / 128)
        var selected = 0
        var covered = 0
        let rect = CGRect(x: bounds.minX * CGFloat(width), y: bounds.minY * CGFloat(height),
                          width: bounds.width * CGFloat(width), height: bounds.height * CGFloat(height)).integral
        for y in stride(from: max(0, Int(rect.minY)), to: min(height, Int(rect.maxY)), by: step) {
            for x in stride(from: max(0, Int(rect.minX)), to: min(width, Int(rect.maxX)), by: step) {
                guard pixels[y * width + x] >= 128 else { continue }
                selected += 1
                let point = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(width),
                                    y: (CGFloat(y) + 0.5) / CGFloat(height))
                if masks.contains(where: { $0.contains(point) }) { covered += 1 }
            }
        }
        return selected > 0 && Double(covered) / Double(selected) >= 0.9
    }
}

enum CutoutError: LocalizedError {
    case invalidImage, invalidDirectory, noSubject, noSelection, renderingFailed, modelNotReady, refinementLimit

    var errorDescription: String? {
        switch self {
        case .invalidImage: "사진을 불러올 수 없습니다. 다른 사진을 선택해 주세요."
        case .invalidDirectory: "저장할 폴더를 확인해 주세요."
        case .noSubject: "피사체를 찾지 못했습니다. 안쪽을 탭하거나 선을 그려 주세요."
        case .noSelection: "저장할 피사체를 선택해 주세요."
        case .renderingFailed: "이미지를 만들지 못했습니다. 다시 시도해 주세요."
        case .modelNotReady: "분할 모델을 준비하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요."
        case .refinementLimit: "이 피사체의 보정 한도에 도달했습니다. 삭제한 뒤 다시 선택해 주세요."
        }
    }
}
