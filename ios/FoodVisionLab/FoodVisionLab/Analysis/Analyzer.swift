//
//  Analyzer.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import Foundation
import MenuRecognition
import SubjectCutout
import SwiftData

@Observable
final class Analyzer {
    private(set) var scan: Scan?
    private(set) var model = AnalysisModel.onDevice
    private(set) var analyzingIDs: Set<UUID> = []
    private(set) var previews: [UUID: String] = [:]
    private(set) var failures: [AnalysisModel: [UUID: String]] = [:]
    private(set) var completedCount = 0
    private(set) var count = 0
    private(set) var isCancelling = false
    private(set) var didFail = false
    private(set) var finishCount = 0
    private var task: Task<Void, Never>?
    private let onDevice = MenuRecognizer()

    var isRunning: Bool { task != nil }

    var status: String {
        if isCancelling { return "취소 중…" }
        return model == .claude ? "음식 \(count)개 분석 중…" : "\(completedCount)/\(count)개 처리 중"
    }

    func isAnalyzing(_ scan: Scan) -> Bool {
        isRunning && self.scan === scan
    }

    func recognizer(for model: AnalysisModel) -> MenuRecognizer? {
        model == .onDevice ? onDevice : model.recognizer()
    }

    func prewarm() async {
        await onDevice.prewarm()
    }

    func cancel() {
        isCancelling = true
        task?.cancel()
    }

    func analyze(_ dishes: [Dish], in scan: Scan, with model: AnalysisModel, using recognizer: MenuRecognizer) {
        guard task == nil, let first = dishes.first else { return }
        let inputs = dishes.map { MenuRecognizer.Input(id: $0.id, imageURL: scan.cutout(for: $0).cropURL) }
        self.scan = scan
        self.model = model
        let previousDishes = scan.dishes
        let previousFailures = failures[model]
        let previousDuration = scan.durations[model]
        let previousUsage = scan.usages[model]
        analyzingIDs = model == .claude ? Set(inputs.map(\.id)) : [first.id]
        for input in inputs { failures[model]?[input.id] = nil }
        completedCount = 0
        count = inputs.count
        isCancelling = false
        task = Task {
            defer {
                previews = [:]
                analyzingIDs = []
                task = nil
                self.scan = nil
                isCancelling = false
            }
            let start = ProcessInfo.processInfo.systemUptime
            var usage = TokenUsage()
            do {
                if model == .claude {
                    do {
                        let result = try await recognizer.recognize(
                            inputs, maximumResponseTokens: max(4096, inputs.count * 1024)
                        )
                        try Task.checkCancellation()
                        let duration = ProcessInfo.processInfo.systemUptime - start
                        for (id, prediction) in result.predictions {
                            save(prediction, for: id, in: scan, duration: duration)
                        }
                        if let resultUsage = result.usage { usage.add(resultUsage) }
                    } catch where !(error is CancellationError || Task.isCancelled) {
                        for input in inputs { fail(input.id, in: scan, with: error) }
                    }
                } else {
                    for input in inputs {
                        analyzingIDs = [input.id]
                        let itemStart = ProcessInfo.processInfo.systemUptime
                        do {
                            let result = try await recognizer.recognize(imageURL: input.imageURL) { name in
                                await MainActor.run {
                                    if !self.isCancelling { self.previews[input.id] = name }
                                }
                            }
                            try Task.checkCancellation()
                            save(result.prediction, for: input.id, in: scan, duration: ProcessInfo.processInfo.systemUptime - itemStart)
                            usage.add(result.usage)
                        } catch where !(error is CancellationError || Task.isCancelled) {
                            fail(input.id, in: scan, with: error)
                        }
                        completedCount += 1
                    }
                }
                try Task.checkCancellation()
            } catch {
                if !scan.isDeleted, scan.modelContext != nil {
                    scan.dishes = previousDishes
                    scan.durations[model] = previousDuration
                    scan.usages[model] = previousUsage
                }
                failures[model] = previousFailures
                return
            }
            let failed = inputs.contains { failures[model]?[$0.id] != nil }
            let isComplete = !failed && inputs.count == scan.dishes.count
            scan.durations[model] = isComplete ? ProcessInfo.processInfo.systemUptime - start : nil
            scan.usages[model] = isComplete ? usage : nil
            didFail = failed
            finishCount += 1
        }
    }

    private func save(_ prediction: MenuPrediction, for id: UUID, in scan: Scan, duration: TimeInterval) {
        guard let index = scan.dishes.firstIndex(where: { $0.id == id }) else { return }
        scan.dishes[index].results[model] = Dish.Result(prediction, duration: duration)
    }

    private func fail(_ id: UUID, in scan: Scan, with error: any Error) {
        failures[model, default: [:]][id] = model.errorMessage(for: error)
        guard let index = scan.dishes.firstIndex(where: { $0.id == id }) else { return }
        scan.dishes[index].results[model] = nil
    }
}
