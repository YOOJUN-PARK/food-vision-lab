//
//  Recognizer.swift
//  MenuRecognition
//
//  Created by YOOJUN PARK on 10/23/26.
//

import Foundation
import FoundationModels
import ImageIO

public actor MenuRecognizer {
    public struct Input: Identifiable, Sendable {
        public let id: UUID
        public let imageURL: URL

        public init(id: UUID, imageURL: URL) {
            self.id = id
            self.imageURL = imageURL
        }
    }

    private let model: any LanguageModel
    private let instructions: String
    private let namingInstructions: String
    private let options: GenerationOptions
    private let maximumImageSize: Int
    private var preparedSession: LanguageModelSession?
    private var preparedNamingSession: LanguageModelSession?

    public init(
        model: any LanguageModel = SystemLanguageModel.default,
        instructions: String = MenuPrompts.onDevice,
        namingInstructions: String = MenuPrompts.onDeviceNaming,
        options: GenerationOptions = GenerationOptions(samplingMode: .greedy),
        maximumImageSize: Int = 1024
    ) {
        self.model = model
        self.instructions = instructions
        self.namingInstructions = namingInstructions
        self.options = options
        self.maximumImageSize = maximumImageSize
    }

    public func prewarm() {
        guard preparedSession == nil, (try? validateModel()) != nil else { return }
        let session = LanguageModelSession(model: model, instructions: instructions)
        let naming = LanguageModelSession(model: model, instructions: namingInstructions)
        preparedSession = session
        preparedNamingSession = naming
        session.prewarm()
        naming.prewarm()
    }

    public func recognize(
        imageURL: URL,
        onName: @Sendable (String) async -> Void = { _ in }
    ) async throws -> (prediction: MenuPrediction, usage: LanguageModelSession.Usage) {
        try Task.checkCancellation()
        let image = try Self.image(at: imageURL, maximumSize: maximumImageSize)
        try validateModel()
        try Task.checkCancellation()

        let session = preparedSession ?? LanguageModelSession(model: model, instructions: instructions)
        let naming = preparedNamingSession ?? LanguageModelSession(model: model, instructions: namingInstructions)
        preparedSession = nil
        preparedNamingSession = nil
        prewarm()
        let identification = try await session.respond(generating: Identification.self, options: options) {
            Attachment(image, orientation: .up)
            "Name the dish, drink, or condiment at the center of this photo."
        }.content
        try Task.checkCancellation()
        guard identification.name.lowercased() != "unknown" else {
            return (.unidentified(reason: "사진만으로는 어떤 음식인지 알기 어렵습니다."), session.usage)
        }

        let stream = naming.streamResponse(generating: MenuPrediction.Match.self, options: options) {
            "Name: \(identification.name)"
            "Other names: \(identification.alternatives.joined(separator: ", "))"
        }
        var content: GeneratedContent?
        var lastName: String?
        for try await snapshot in stream {
            try Task.checkCancellation()
            content = snapshot.rawContent
            if let name = snapshot.content.name, !name.isEmpty, name != lastName {
                lastName = name
                await onName(name)
            }
        }
        try Task.checkCancellation()
        guard let content, content.isComplete else { throw Error.incompleteResponse }
        let prediction = MenuPrediction.identified(try MenuPrediction.Match(content))
        return (prediction.removingDuplicateAlternatives(), session.usage + naming.usage)
    }

    public func recognize(
        _ inputs: [Input],
        maximumResponseTokens: Int? = nil
    ) async throws -> (predictions: [UUID: MenuPrediction], usage: LanguageModelSession.Usage?) {
        try Task.checkCancellation()
        guard !inputs.isEmpty else { return ([:], nil) }
        let ids = Set(inputs.map(\.id))
        guard ids.count == inputs.count else { throw Error.duplicateInputs }
        let images = try inputs.map { input in
            (id: input.id.uuidString, image: try Self.image(at: input.imageURL, maximumSize: maximumImageSize))
        }
        try validateModel()
        try Task.checkCancellation()

        let session = preparedSession ?? LanguageModelSession(model: model, instructions: instructions)
        preparedSession = nil
        var requestOptions = options
        if let maximumResponseTokens { requestOptions.maximumResponseTokens = maximumResponseTokens }
        let response = try await session.respond(generating: BatchAnalysis.self, options: requestOptions) {
            for item in images {
                "Dish ID: \(item.id)"
                Attachment(item.image, orientation: .up).label(item.id)
            }
            "Name the main dish in each photo. Return exactly \(inputs.count) results, one per dish ID, with each ID copied verbatim."
        }
        try Task.checkCancellation()
        return (try response.content.predictions(for: ids), session.usage)
    }

    @Generable
    struct Identification {
        @Guide(description: "One short English sentence describing the visible color, shape, texture, and ingredients.")
        var observation: String

        @Guide(description: "The specific English menu name of the item, or unknown when you cannot tell what it is.")
        var name: String

        @Guide(description: "Up to two other plausible English menu names, most likely first.", .count(0...2))
        var alternatives: [String]
    }

    @Generable
    struct Analysis {
        @Guide(description: "One short English sentence describing the visible color, shape, texture, and ingredients.")
        var observation: String

        var prediction: MenuPrediction
    }

    @Generable
    struct BatchAnalysis {
        @Guide(description: "One result for every dish ID, each ID exactly once.")
        var items: [ItemAnalysis]

        func predictions(for expectedIDs: Set<UUID>) throws -> [UUID: MenuPrediction] {
            var predictions: [UUID: MenuPrediction] = [:]
            for item in items {
                guard let id = UUID(uuidString: item.id), expectedIDs.contains(id),
                      predictions[id] == nil else { throw Error.invalidResults }
                predictions[id] = item.analysis.prediction.removingDuplicateAlternatives()
            }
            guard predictions.count == expectedIDs.count else { throw Error.invalidResults }
            return predictions
        }
    }

    @Generable
    struct ItemAnalysis {
        @Guide(description: "The dish ID of the photo, copied verbatim.")
        var id: String

        var analysis: Analysis
    }

    static func image(at url: URL, maximumSize: Int = 1024) throws -> CGImage {
        try Task.checkCancellation()
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumSize
              ] as CFDictionary) else {
            throw Error.invalidImage
        }
        return image
    }

    private func validateModel() throws {
        if let model = model as? SystemLanguageModel {
            if case let .unavailable(reason) = model.availability { throw Error.modelUnavailable(reason) }
            guard model.supportsLocale(Locale(identifier: "ko_KR")) else { throw Error.unsupportedLanguage }
        }
        guard model.capabilities.contains(.vision), model.capabilities.contains(.guidedGeneration) else {
            throw Error.unsupportedModel
        }
    }

    public enum Error: LocalizedError {
        case invalidImage
        case incompleteResponse
        case duplicateInputs
        case invalidResults
        case modelUnavailable(SystemLanguageModel.Availability.UnavailableReason)
        case unsupportedLanguage
        case unsupportedModel

        public var errorDescription: String? {
            switch self {
            case .invalidImage: "분석할 이미지를 불러올 수 없습니다. 사진을 다시 선택해 주세요."
            case .incompleteResponse: "분석 결과를 완성하지 못했습니다. 다시 시도해 주세요."
            case .duplicateInputs: "같은 음식이 중복으로 전달되었습니다. 음식을 다시 선택해 주세요."
            case .invalidResults: "음식과 분석 결과를 정확히 연결하지 못했습니다. 다시 분석해 주세요."
            case .unsupportedLanguage: "현재 모델에서 한국어 메뉴 분석을 사용할 수 없습니다."
            case .unsupportedModel: "선택한 모델은 이미지 기반 메뉴 분석을 지원하지 않습니다."
            case let .modelUnavailable(reason):
                switch reason {
                case .deviceNotEligible: "이 기기는 온디바이스 메뉴 분석을 지원하지 않습니다."
                case .appleIntelligenceNotEnabled: "설정에서 Apple Intelligence를 켠 뒤 다시 시도해 주세요."
                case .modelNotReady: "Apple Intelligence 모델이 준비 중입니다. 준비가 끝난 뒤 다시 시도해 주세요."
                @unknown default: "현재 온디바이스 메뉴 분석을 사용할 수 없습니다."
                }
            }
        }
    }
}

private extension LanguageModelSession.Usage {
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            input: .init(
                totalTokenCount: lhs.input.totalTokenCount + rhs.input.totalTokenCount,
                cachedTokenCount: lhs.input.cachedTokenCount + rhs.input.cachedTokenCount
            ),
            output: .init(
                totalTokenCount: lhs.output.totalTokenCount + rhs.output.totalTokenCount,
                reasoningTokenCount: lhs.output.reasoningTokenCount + rhs.output.reasoningTokenCount
            )
        )
    }
}
