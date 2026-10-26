//
//  AnalysisModel.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import ClaudeForFoundationModels
import Foundation
import FoundationModels
import MenuRecognition

enum AnalysisModel: String, CaseIterable, Codable, Identifiable {
    case onDevice
    case claude

    var id: Self { self }

    var name: String {
        switch self {
        case .onDevice: "Foundation Models (On-Device)"
        case .claude: "Claude Haiku 5.5"
        }
    }

    var pricePerMillionTokens: (input: Double, cachedInput: Double, output: Double)? {
        switch self {
        case .onDevice: nil
        case .claude: (0.1, 0.01, 0.5)
        }
    }

    func cost(of usage: TokenUsage) -> Double? {
        pricePerMillionTokens.map { price in
            let cached = Double(usage.cachedInput ?? 0)
            let uncached = Double(usage.input) - cached
            return (uncached * price.input + cached * price.cachedInput + Double(usage.output) * price.output) / 1_000_000
        }
    }

    func recognizer() -> MenuRecognizer? {
        switch self {
        case .onDevice:
            return MenuRecognizer()
        case .claude:
            guard let key = try? APIKeyStore.read(.claude) else { return nil }
            return MenuRecognizer(
                model: ClaudeLanguageModel(name: .haiku5_5, auth: .apiKey(key), fixedEffort: .low),
                instructions: MenuPrompts.claude,
                options: .init(maximumResponseTokens: 4096),
                maximumImageSize: 768
            )
        }
    }

    func errorMessage(for error: any Error) -> String {
        if let error = error as? ClaudeError, case .missingCredential = error {
            return "Claude API 키가 없거나 유효하지 않습니다. 설정의 API 관리에서 확인해 주세요."
        }
        return error.localizedDescription
    }
}

enum AnalysisLevel: Int, CaseIterable, Identifiable {
    case fast, balanced, accurate, cloud

    static let dailyCloudLimit: Int? = nil

    init(model: AnalysisModel, mode: MenuRecognitionMode) {
        switch (model, mode) {
        case (.claude, _): self = .cloud
        case (.onDevice, .fast): self = .fast
        case (.onDevice, .balanced): self = .balanced
        case (.onDevice, .accurate): self = .accurate
        }
    }

    var id: Self { self }

    var model: AnalysisModel { self == .cloud ? .claude : .onDevice }

    var mode: MenuRecognitionMode? {
        switch self {
        case .fast: .fast
        case .balanced: .balanced
        case .accurate: .accurate
        case .cloud: nil
        }
    }

    var name: String { mode?.name ?? "매우 정확" }

    var symbol: String {
        switch self {
        case .fast: "gauge.with.dots.needle.33percent"
        case .balanced: "gauge.with.dots.needle.50percent"
        case .accurate: "gauge.with.dots.needle.67percent"
        case .cloud: "gauge.with.dots.needle.100percent"
        }
    }
}
