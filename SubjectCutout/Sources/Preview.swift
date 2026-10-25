//
//  Preview.swift
//  SubjectCutout
//
//  Created by YOOJUN PARK on 10/23/26.
//

import ImageIO
import SwiftUI

public struct CutoutPreview: View {
    private let cutout: Cutout

    public init(cutout: Cutout) {
        self.cutout = cutout
    }

    public var body: some View {
        GeometryReader { geometry in
            let rect = Self.fillRect(for: cutout, in: geometry.size)
            let subject = Self.subjectFrame(for: cutout, inside: rect)
            ZStack(alignment: .topLeading) {
                Thumbnail(url: cutout.cropURL)
                    .frame(width: rect.width, height: rect.height)
                    .blur(radius: 6)
                    .overlay(.black.opacity(0.55))
                    .clipped()
                    .position(x: rect.midX, y: rect.midY)

                Thumbnail(url: cutout.url)
                    .frame(width: subject.width, height: subject.height)
                    .position(x: subject.midX, y: subject.midY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .accessibilityLabel("배경을 흐리고 선택 영역을 선명하게 표시한 피사체 미리보기")
    }

    nonisolated static func fillRect(for cutout: Cutout, in size: CGSize) -> CGRect {
        let crop = cutout.cropBounds, bounds = cutout.bounds
        guard !crop.isEmpty, !bounds.isEmpty else { return .zero }
        let scale = min(
            max(size.width / crop.width, size.height / crop.height),
            min(size.width / bounds.width, size.height / bounds.height)
        )
        return CGRect(
            x: size.width / 2 - (bounds.midX - crop.minX) * scale,
            y: size.height / 2 - (bounds.midY - crop.minY) * scale,
            width: crop.width * scale, height: crop.height * scale
        )
    }

    nonisolated static func subjectFrame(for cutout: Cutout, inside rect: CGRect) -> CGRect {
        subjectFrame(for: cutout.bounds, source: cutout.cropBounds, inside: rect)
    }

    nonisolated static func subjectFrame(for bounds: CGRect, source: CGRect, inside rect: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return .zero }
        let scale = rect.width / source.width
        return CGRect(
            x: rect.minX + (bounds.minX - source.minX) * scale,
            y: rect.minY + (bounds.minY - source.minY) * scale,
            width: bounds.width * scale, height: bounds.height * scale
        )
    }
}

public struct CutoutPhoto: View {
    private let image: UIImage
    private let cutouts: [Cutout]
    public init(image: UIImage, cutouts: [Cutout]) {
        self.image = image
        self.cutouts = cutouts
    }

    public var body: some View {
        GeometryReader { geometry in
            let sourceSize = Self.sourceSize(for: image)
            let layout = ImageLayout(imageSize: sourceSize, availableSize: geometry.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: layout.rect.width, height: layout.rect.height)
                    .clipped()
                    .position(x: layout.rect.midX, y: layout.rect.midY)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)

                ForEach(cutouts) { cutout in
                    let subject = CutoutPreview.subjectFrame(
                        for: cutout.bounds, source: CGRect(origin: .zero, size: sourceSize), inside: layout.rect
                    )
                    Thumbnail(url: cutout.url, tint: .white, pixelSize: 1024)
                        .frame(width: subject.width, height: subject.height)
                        .position(x: subject.midX, y: subject.midY)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .accessibilityElement(children: .contain)
    }

    nonisolated static func sourceSize(for image: UIImage) -> CGSize {
        guard let source = image.cgImage else {
            return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        }
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: source.height, height: source.width)
        default:
            return CGSize(width: source.width, height: source.height)
        }
    }
}

public struct CutoutImage: View {
    private let cutout: Cutout

    public init(cutout: Cutout) {
        self.cutout = cutout
    }

    public var body: some View {
        Thumbnail(url: cutout.url)
    }

    public static func prefetch(_ cutouts: [Cutout]) async {
        for cutout in cutouts {
            guard !Task.isCancelled else { return }
            await Thumbnail.load(cutout.url, pixelSize: 512)
        }
    }
}

public struct CutoutExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var includesBackground: Bool? = true
    @State private var size = CGSize.zero
    private let cutout: Cutout

    public init(cutout: Cutout) {
        self.cutout = cutout
    }

    private var formats: [(includesBackground: Bool, name: String, url: URL)] {
        [(true, "음식과 주변배경", cutout.cropURL), (false, "음식만", cutout.url)]
    }

    public var body: some View {
        let format = formats.first { $0.includesBackground == includesBackground } ?? formats[0]
        let cardWidth = max(size.width - 80, 0)
        let cardHeight = min(cardWidth * cutout.cropBounds.height / max(cutout.cropBounds.width, 1), cardWidth * 1.25)
        VStack(spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("이미지 내보내기")
                        .font(.headline)
                    Text(format.includesBackground ? "PNG" : "투명 배경 PNG")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
            }
            .padding(.horizontal, 24)

            Picker("이미지 형식", selection: $includesBackground.animation()) {
                ForEach(formats, id: \.includesBackground) { Text($0.name).tag(Optional($0.includesBackground)) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(formats, id: \.includesBackground) { format in
                        Thumbnail(url: format.url, pixelSize: 1024)
                            .frame(width: cardWidth, height: cardHeight)
                            .background(.quaternary)
                            .clipShape(.rect(cornerRadius: 24))
                            .accessibilityLabel(format.name)
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: cardHeight)
            .scrollPosition(id: $includesBackground)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .safeAreaPadding(.horizontal, 40)

            ShareLink("PNG 공유", item: format.url)
                .buttonStyle(.glass(.regular.tint(.yellow)))
                .foregroundStyle(.black)
                .controlSize(.large)
        }
        .padding(.vertical, 24)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .presentationDetents(size == .zero ? [.medium] : [.height(size.height)])
        .presentationBackground(.background)
    }
}

private struct Thumbnail: View {
    private static let cache = NSCache<NSString, CGImage>()

    let url: URL
    var tint: Color?
    var pixelSize = 512
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image = image ?? Self.cache.object(forKey: Self.key(url, pixelSize)) {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .overlay {
                        if let tint {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .foregroundStyle(tint.opacity(0.18))
                        }
                    }
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            image = Self.cache.object(forKey: Self.key(url, pixelSize))
            let result = await Self.load(url, pixelSize: pixelSize)
            if !Task.isCancelled { image = result }
        }
    }

    private static func key(_ url: URL, _ pixelSize: Int) -> NSString {
        "\(url.path)#\(pixelSize)" as NSString
    }

    @discardableResult
    static func load(_ url: URL, pixelSize: Int) async -> CGImage? {
        if let image = cache.object(forKey: key(url, pixelSize)) { return image }
        let thumbnail = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }.value
        if let thumbnail { cache.setObject(thumbnail, forKey: key(url, pixelSize)) }
        return thumbnail
    }
}
