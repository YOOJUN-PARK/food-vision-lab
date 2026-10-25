//
//  Session.swift
//  SubjectCutout
//
//  Created by YOOJUN PARK on 10/23/26.
//

import CoreImage
import Observation
import UIKit
import Vision

@MainActor @Observable
public final class CutoutSession {
    enum Mode: Hashable {
        case selecting, editing(UUID)
    }

    struct Subject: Identifiable {
        let id: UUID
        let number: Int
        var mask: Mask
        var correctionCount = 0
    }

    var image: UIImage
    var subjects: [Subject] = []
    var mode = Mode.selecting
    var isExcluding = false
    var isReady = false
    var isBusy = false
    private(set) var isSaving = false
    var status = "사진을 준비하고 있습니다…"
    var error: String?
    private(set) var changeCount = 0
    private(set) var nextNumber = 1
    private var history: [[Subject]] = []
    @ObservationIgnored private let segmenter: Segmenter
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(image: UIImage, quality: GenerateIterativeSegmentationRequest.QualityLevel = .balanced) {
        self.image = image
        segmenter = Segmenter(quality: quality)
    }

    public func setQuality(_ quality: GenerateIterativeSegmentationRequest.QualityLevel) async {
        while isBusy, let task { await task.value }
        await segmenter.setQuality(quality)
    }

    func prepare() async {
        while isBusy, let task { await task.value }
        guard !Task.isCancelled, !isReady else { return }
        run(status: "사진을 준비하고 있습니다…") {
            guard let source = self.image.cgImage else { throw CutoutError.invalidImage }
            let image = try await self.segmenter.prepare(source, orientation: self.image.imageOrientation.exif)
            try Task.checkCancellation()
            self.image = UIImage(cgImage: image)
            self.isReady = true
        }
    }

    func tap(_ point: CGPoint) {
        guard isReady, !isBusy else { return }
        if case let .editing(id) = mode {
            guard let subject = subjects.first(where: { $0.id == id }) else { return }
            run(status: "음식 범위를 편집하고 있습니다…") {
                try await self.segmenter.restoreCorrections([id: subject.correctionCount])
                let mask = try await self.segmenter.refine(id, at: point, excluding: self.isExcluding)
                try Task.checkCancellation()
                if let index = self.subjects.firstIndex(where: { $0.id == id }) {
                    self.recordChange()
                    self.subjects[index].mask = mask
                    self.subjects[index].correctionCount += 1
                    self.changeCount += 1
                    await self.prune()
                }
            }
            return
        }

        if let index = subjects.lastIndex(where: { $0.mask.contains(point) }) {
            remove(subjects[index].id)
        } else if mode == .selecting {
            add(.point(point))
        }
    }

    func scribble(_ points: [CGPoint]) {
        guard mode == .selecting, isReady, !isBusy, points.count > 1 else { return }
        guard !points.allSatisfy({ point in subjects.contains { $0.mask.contains(point) } }) else { return }
        add(.scribble(points))
    }

    func edit(_ id: UUID) {
        guard isReady, !isBusy, subjects.contains(where: { $0.id == id }) else { return }
        mode = .editing(id)
        isExcluding = false
    }

    func remove(_ id: UUID) {
        guard isReady, !isBusy, let index = subjects.firstIndex(where: { $0.id == id }) else { return }
        if mode == .editing(id) { mode = .selecting }
        recordChange()
        subjects.remove(at: index)
        changeCount += 1
        run(status: "선택을 해제하고 있습니다…") { await self.prune() }
    }

    var canUndo: Bool { !history.isEmpty && isReady && !isBusy }

    func undo() {
        guard canUndo, let previous = history.last else { return }
        run(status: "이전 선택으로 되돌리고 있습니다…") {
            try await self.segmenter.restoreCorrections(
                Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0.correctionCount) })
            )
            self.subjects = previous
            self.history.removeLast()
            if case let .editing(id) = self.mode, !previous.contains(where: { $0.id == id }) {
                self.mode = .selecting
            }
            self.changeCount += 1
            await self.prune()
        }
    }

    func save(to directory: URL, completion: @escaping ([Cutout]) -> Void) {
        guard isReady, !isSaving else { return }
        guard isBusy || !subjects.isEmpty else { completion([]); return }
        isSaving = true
        status = "선택한 음식을 저장하고 있습니다…"
        saveTask = Task {
            defer { isSaving = false }
            while isBusy, let task { await task.value }
            guard !Task.isCancelled else { return }
            guard !subjects.isEmpty else { completion([]); return }
            let selected = subjects.map { (id: $0.id, mask: $0.mask) }
            let numbers = Dictionary(uniqueKeysWithValues: subjects.map { ($0.id, $0.number) })
            run(status: status) {
                var cutouts = try await self.segmenter.save(selected, to: directory)
                for index in cutouts.indices {
                    if let number = numbers[cutouts[index].id] { cutouts[index].number = number }
                }
                if Task.isCancelled {
                    await self.segmenter.discard(cutouts)
                    throw CancellationError()
                }
                completion(cutouts)
            }
            await task?.value
        }
    }

    func cancel() {
        saveTask?.cancel()
        task?.cancel()
    }

    private func add(_ seed: Segmenter.Seed) {
        run(status: "음식을 구분하고 있습니다…") {
            guard let (id, mask) = try await self.segmenter.add(seed, avoiding: self.subjects.map(\.mask)) else {
                return
            }
            guard !Task.isCancelled else {
                await self.segmenter.remove(id)
                throw CancellationError()
            }
            self.recordChange()
            self.subjects.append(Subject(id: id, number: self.nextNumber, mask: mask))
            self.nextNumber += 1
            self.changeCount += 1
            await self.prune()
        }
    }

    private func recordChange() {
        history.append(subjects)
        if history.count > 20 { history.removeFirst() }
    }

    private func prune() async {
        let active = Set(subjects.map(\.id))
        let retained = active.union(history.flatMap { $0.map(\.id) })
        await segmenter.retain(active, preserving: retained)
    }

    private func run(status: String, action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        self.status = status
        task = Task {
            defer { self.isBusy = false }
            do {
                try Task.checkCancellation()
                try await action()
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}

actor Segmenter {
    enum Seed: Sendable {
        case point(CGPoint), scribble([CGPoint])
    }

    struct Entry {
        var request: GenerateIterativeSegmentationRequest?
        var handler: ImageRequestHandler?
        let seed: Seed
        var corrections: [(point: CGPoint, excluding: Bool)] = []
    }

    private let context = CIContext()
    private var quality: GenerateIterativeSegmentationRequest.QualityLevel
    private var image: CGImage?
    private var entries: [UUID: Entry] = [:]

    init(quality: GenerateIterativeSegmentationRequest.QualityLevel = .balanced) {
        self.quality = quality
    }

    func setQuality(_ quality: GenerateIterativeSegmentationRequest.QualityLevel) {
        self.quality = quality
        for entry in entries.values { entry.request?.qualityLevel = quality }
    }

    func prepare(_ source: CGImage, orientation: CGImagePropertyOrientation) async throws -> CGImage {
        let image: CGImage
        if orientation == .up {
            image = source
        } else {
            let oriented = CIImage(cgImage: source).oriented(orientation)
            guard let upright = context.createCGImage(oriented, from: oriented.extent) else {
                throw CutoutError.invalidImage
            }
            image = upright
        }
        self.image = image

        let request = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
        if await request.assetStatus != .ready { try await request.downloadAssets() }
        guard await request.assetStatus == .ready else { throw CutoutError.modelNotReady }
        try Task.checkCancellation()
        return image
    }

    func add(_ seed: Seed, avoiding selected: [Mask]) async throws -> (UUID, Mask)? {
        guard let image else { throw CutoutError.invalidImage }
        let request = try makeRequest(seed)
        let handler = ImageRequestHandler(image, orientation: .up)
        let mask = try await perform(request, with: handler)
        try Task.checkCancellation()
        guard !mask.isCovered(by: selected) else { return nil }
        let id = UUID()
        entries[id] = Entry(request: request, handler: handler, seed: seed)
        return (id, mask)
    }

    func refine(_ id: UUID, at point: CGPoint, excluding: Bool) async throws -> Mask {
        guard var entry = entries[id], let image else { throw CutoutError.noSubject }
        let limit: Int
        switch entry.seed {
        case .point: limit = 12
        case .scribble: limit = 13
        }
        guard entry.corrections.count < limit else { throw CutoutError.refinementLimit }
        do {
            let request: GenerateIterativeSegmentationRequest
            if let existing = entry.request { request = existing }
            else { request = try restoredRequest(for: entry) }
            let handler = entry.handler ?? ImageRequestHandler(image, orientation: .up)
            try apply(point, excluding: excluding, to: request)
            let mask = try await perform(request, with: handler)
            try Task.checkCancellation()
            entry.request = request
            entry.handler = handler
            entry.corrections.append((point, excluding))
            entries[id] = entry
            return mask
        } catch {
            entry.request = nil
            entry.handler = nil
            entries[id] = entry
            throw error
        }
    }

    func remove(_ id: UUID) { entries[id] = nil }

    func retain(_ active: Set<UUID>, preserving retained: Set<UUID>) {
        for id in Array(entries.keys) {
            if !retained.contains(id) { entries[id] = nil }
            else if !active.contains(id) {
                entries[id]?.request = nil
                entries[id]?.handler = nil
            }
        }
    }

    func restoreCorrections(_ counts: [UUID: Int]) throws {
        for (id, count) in counts {
            guard var entry = entries[id], count != entry.corrections.count else { continue }
            guard count <= entry.corrections.count else { throw CutoutError.noSubject }
            entry.corrections = Array(entry.corrections.prefix(count))
            entry.request = nil
            entry.handler = nil
            entries[id] = entry
        }
    }

    private func restoredRequest(for entry: Entry) throws -> GenerateIterativeSegmentationRequest {
        let request = try makeRequest(entry.seed)
        for correction in entry.corrections {
            try apply(correction.point, excluding: correction.excluding, to: request)
        }
        return request
    }

    func save(_ subjects: [(id: UUID, mask: Mask)], to directory: URL) throws -> [Cutout] {
        guard let image else { throw CutoutError.invalidImage }
        return try Cutout.save(subjects, image: image, directory: directory, context: context)
    }

    func discard(_ cutouts: [Cutout]) {
        guard let folder = cutouts.first?.url.deletingLastPathComponent() else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    private func perform(
        _ request: GenerateIterativeSegmentationRequest, with handler: ImageRequestHandler
    ) async throws -> Mask {
        guard let observation = try await handler.perform(request) else { throw CutoutError.noSubject }
        try Task.checkCancellation()
        return try Mask(observation.cgImage)
    }

    private func apply(_ point: CGPoint, excluding: Bool, to request: GenerateIterativeSegmentationRequest) throws {
        let normalized = NormalizedPoint(x: point.x, y: 1 - point.y)
        if excluding { try request.addExcludedPoint(normalized) }
        else { try request.addIncludedPoint(normalized) }
    }

    private func makeRequest(_ seed: Seed) throws -> GenerateIterativeSegmentationRequest {
        let request: GenerateIterativeSegmentationRequest
        switch seed {
        case let .point(point):
            request = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: point.x, y: 1 - point.y))
        case let .scribble(points):
            guard let image else { throw CutoutError.invalidImage }
            let scale = min(1, 1024 / CGFloat(max(image.width, image.height)))
            let width = max(1, Int(CGFloat(image.width) * scale))
            let height = max(1, Int(CGFloat(image.height) * scale))
            let buffer = try Self.scribbleBuffer(points, width: width, height: height)
            request = GenerateIterativeSegmentationRequest(seedScribbleBuffer: buffer)
        }
        request.qualityLevel = quality
        return request
    }

    nonisolated static func scribbleBuffer(
        _ points: [CGPoint], width: Int, height: Int
    ) throws -> CVReadOnlyPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, nil, &pixelBuffer
        ) == kCVReturnSuccess, let buffer = pixelBuffer else { throw CutoutError.renderingFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        do {
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let address = CVPixelBufferGetBaseAddress(buffer),
                  let context = CGContext(
                    data: address, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { throw CutoutError.renderingFailed }
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setStrokeColor(gray: 1, alpha: 1)
            context.setLineWidth(max(3, CGFloat(width) * 0.015))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addLines(between: points.map {
                CGPoint(x: $0.x * CGFloat(width), y: (1 - $0.y) * CGFloat(height))
            })
            context.strokePath()
        }
        return CVReadOnlyPixelBuffer(unsafeBuffer: buffer)
    }
}

private extension UIImage.Orientation {
    var exif: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
