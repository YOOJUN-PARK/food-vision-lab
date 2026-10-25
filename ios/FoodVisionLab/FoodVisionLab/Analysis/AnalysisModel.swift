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
