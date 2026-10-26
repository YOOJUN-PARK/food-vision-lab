//
//  ScanView.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import MenuRecognition
import SubjectCutout
import SwiftUI

struct ScanView: View {
    let scan: Scan
    let analyzer: Analyzer
    let onOpenSettings: () -> Void
    @AppStorage("recognitionMode") private var recognitionMode = MenuRecognitionMode.balanced
    @State private var model: AnalysisModel
    @State private var photo: UIImage?
    @State private var exportingCutout: Cutout?
    @State private var summary: AnalysisModel?
    @State private var rowFrames: [AnalysisModel: CGRect] = [:]
    @State private var tapLocation = CGPoint.zero
    @AppStorage("cloudUsageDay") private var cloudUsageDay = 0.0
    @AppStorage("cloudUsageCount") private var cloudUsageCount = 0

    init(scan: Scan, analyzer: Analyzer, model: AnalysisModel, onOpenSettings: @escaping () -> Void) {
        self.scan = scan
        self.analyzer = analyzer
        self.onOpenSettings = onOpenSettings
        _model = State(initialValue: analyzer.isAnalyzing(scan) ? analyzer.model : model)
    }

    var body: some View {
        List {
            if let photo {
                CutoutPhoto(image: photo, cutouts: scan.cutouts)
                    .aspectRatio(photo.size, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 20))
                    .frame(maxWidth: .infinity, idealHeight: 220, maxHeight: 220)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("분석 모델") {
                ForEach(AnalysisModel.allCases) { model in
                    if scan.durations[model] != nil {
                        LabeledContent {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.tint)
                        } label: {
                            ModelStatus(model: model, scan: scan)
                        }
                        .contentShape(.rect)
                        .onTapGesture(coordinateSpace: .global) { location in
                            tapLocation = location
                            summary = model
                        }
                        .accessibilityAddTraits(.isButton)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rowFrames[model] = $0 }
                    } else {
                        Button { analyze(scan.dishes, with: model) } label: {
                            LabeledContent {
                                Text("분석하기")
                            } label: {
                                ModelStatus(
                                    model: model, scan: scan,
                                    isAnalyzing: analyzer.isAnalyzing(scan) && analyzer.model == model
                                )
                            }
                        }
                        .disabled(analyzer.isRunning)
                    }
                }
            }

            Section {
                ForEach(scan.dishes) { dish in
                    NavigationLink(value: dish.id) { row(for: dish) }
                }
            } header: {
                HStack {
                    Text("음식 \(scan.dishes.count)개")
                    Spacer()
                    Menu {
                        Section("Foundation Models") {
                            ForEach([AnalysisLevel.fast, .balanced, .accurate]) { option($0) }
                        }
                        Section(AnalysisModel.claude.name) {
                            option(.cloud, detail: "클라우드 · 오늘 \(cloudUsageDay == todayStart ? cloudUsageCount : 0)회 / \(AnalysisLevel.dailyCloudLimit.map { "\($0)회" } ?? "무한")")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: level.wrappedValue.symbol)
                            Text(level.wrappedValue.name)
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                        }
                        .fontWeight(.semibold)
                    }
                    .foregroundStyle(.yellow)
                    .fixedSize()
                }
            }
        }
        .navigationTitle(scan.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { id in
            if let dish = scan.dishes.first(where: { $0.id == id }) {
                detail(for: dish)
            }
        }
        .safeAreaBar(edge: .bottom) { controls }
        .overlay {
            if summary != nil {
                Color.black
                    .opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { summary = nil }
                    .transition(.opacity)
            }
        }
        .overlay {
            GeometryReader { geometry in
                if let summary {
                    let frame = geometry.frame(in: .global)
                    VStack(alignment: .leading, spacing: 0) {
                        AnalysisSummary(model: summary, scan: scan)
                        Button("다시 분석", systemImage: "arrow.clockwise") {
                            self.summary = nil
                            analyze(scan.dishes, with: summary)
                        }
                        .buttonStyle(.glass)
                        .disabled(analyzer.isRunning)
                        .padding([.horizontal, .bottom], 20)
                    }
                    .background(.thickMaterial, in: .rect(cornerRadius: 28))
                    .transition(.scale(scale: 0.88, anchor: UnitPoint(x: (tapLocation.x - frame.minX - 16) / max(frame.width - 32, 1), y: 1)).combined(with: .opacity))
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, max(frame.maxY - (rowFrames[summary]?.minY ?? frame.midY) + 8, 0))
                }
            }
        }
        .animation(summary == nil ? .easeIn(duration: 0.12) : .easeOut(duration: 0.18), value: summary)
        .sheet(item: $exportingCutout) { CutoutExportView(cutout: $0) }
        .task {
            photo = UIImage(data: scan.photo)
        }
        .task(id: recognitionMode) { await analyzer.prewarm(mode: recognitionMode) }
        .sensoryFeedback(.selection, trigger: level.wrappedValue)
    }

    private func isAnalyzing(_ dish: Dish) -> Bool {
        analyzer.model == model && analyzer.analyzingIDs.contains(dish.id)
    }

    private func name(for dish: Dish) -> String {
        (analyzer.model == model ? analyzer.previews[dish.id] : nil)
            ?? dish.results[model]?.name ?? "음식 \(dish.number)"
    }

    private func row(for dish: Dish) -> some View {
        HStack(spacing: 12) {
            CutoutPreview(cutout: scan.cutout(for: dish))
                .frame(width: 60, height: 60)
                .background(.quaternary)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name(for: dish))
                    .font(.headline)
                    .foregroundStyle(isAnalyzing(dish) ? .secondary : .primary)
                status(for: dish)
            }
        }
    }

    @ViewBuilder
    private func status(for dish: Dish) -> some View {
        if isAnalyzing(dish) {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(analyzer.isCancelling ? "취소 중…" : "분석 중…")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else if analyzer.failures[model]?[dish.id] != nil {
            Label("분석 실패", systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.red)
        } else if let result = dish.results[model] {
            HStack(spacing: 4) {
                if !result.alternatives.isEmpty { Text("다른 후보 \(result.alternatives.count)개 ·") }
                if result.reason != nil { Text("판단 불가 ·") }
                if model == .claude { Text("전체") }
                Text("\(result.duration, format: .number.precision(.fractionLength(1)))초")
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
        } else {
            Text("분석 대기")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if analyzer.isAnalyzing(scan) {
            VStack(spacing: 8) {
                ProgressView()
                Text(analyzer.status)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("취소", action: analyzer.cancel)
                    .disabled(analyzer.isCancelling)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassEffect(in: .rect(cornerRadius: 24))
            .padding()
        } else {
            Button(scan.durations[model] == nil ? "메뉴 분석" : "다시 분석", systemImage: "sparkle.magnifyingglass") {
                analyze(scan.dishes, with: model)
            }
            .buttonStyle(.glass(.regular.tint(.yellow)))
            .foregroundStyle(.black)
            .controlSize(.large)
            .disabled(analyzer.isRunning)
            .padding()
        }
    }

    private func detail(for dish: Dish) -> some View {
        let cutout = scan.cutout(for: dish)
        let result = dish.results[model]
        return List {
            Section {
                CutoutPreview(cutout: cutout)
                    .frame(height: 360)
                    .clipShape(.rect(cornerRadius: 20))
                    .listRowInsets(EdgeInsets())
                VStack(alignment: .leading, spacing: 4) {
                    Text(name(for: dish))
                        .font(.title2.bold())
                        .foregroundStyle(isAnalyzing(dish) ? .secondary : .primary)
                    status(for: dish)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if model == .onDevice, let mode = result?.mode {
                Section {
                    LabeledContent("분석 모드", value: mode.name)
                }
            }

            if let failure = analyzer.failures[model]?[dish.id] {
                Section("오류") { Text(failure) }
            } else if let reason = result?.reason {
                Section("판단하기 어려운 이유") { Text(reason) }
            } else if let alternatives = result?.alternatives, !alternatives.isEmpty {
                Section("다른 후보") {
                    ForEach(alternatives, id: \.self) { Text($0) }
                }
            }
        }
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("이미지 내보내기", systemImage: "square.and.arrow.up") { exportingCutout = cutout }
        }
        .safeAreaBar(edge: .bottom) {
            Group {
                if analyzer.isAnalyzing(scan) {
                    Button("분석 취소", systemImage: "stop.fill", action: analyzer.cancel)
                        .disabled(analyzer.isCancelling)
                } else {
                    Button(result == nil ? "메뉴 분석" : "다시 분석", systemImage: "sparkle.magnifyingglass") {
                        analyze([dish], with: model)
                    }
                    .disabled(analyzer.isRunning)
                }
            }
            .buttonStyle(.glass(.regular.tint(.yellow)))
            .foregroundStyle(.black)
            .controlSize(.large)
            .padding()
        }
    }

    private func option(_ option: AnalysisLevel, detail: String? = nil) -> some View {
        Toggle(isOn: Binding { level.wrappedValue == option } set: { if $0 { level.wrappedValue = option } }) {
            Label(option.name, systemImage: option.symbol)
            if let detail { Text(detail) }
        }
    }

    private var todayStart: Double { Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate }

    private var level: Binding<AnalysisLevel> {
        Binding {
            AnalysisLevel(model: model, mode: recognitionMode)
        } set: { level in
            model = level.model
            if let mode = level.mode { recognitionMode = mode }
        }
    }

    private func analyze(_ dishes: [Dish], with model: AnalysisModel) {
        self.model = model
        if model == .claude {
            if cloudUsageDay != todayStart {
                cloudUsageDay = todayStart
                cloudUsageCount = 0
            }
            if let limit = AnalysisLevel.dailyCloudLimit, cloudUsageCount >= limit { return }
        }
        let mode = recognitionMode
        guard let recognizer = analyzer.recognizer(for: model, mode: mode) else { return onOpenSettings() }
        analyzer.analyze(dishes, in: scan, with: model, mode: mode, using: recognizer)
        if model == .claude { cloudUsageCount += 1 }
    }
}

struct ModelStatus: View {
    let model: AnalysisModel
    let scan: Scan
    var isAnalyzing = false

    var body: some View {
        let duration = scan.durations[model]
        HStack(spacing: 8) {
            if isAnalyzing {
                ProgressView()
            } else {
                Image(systemName: duration == nil ? "circle" : "checkmark.circle.fill")
            }
            Text(model.name)
            if let duration {
                Text("· \(duration, format: .number.precision(.fractionLength(1)))초")
                    .monospacedDigit()
            }
            if let cost = scan.usages[model].flatMap(model.cost) {
                Text("· \(cost, format: .currency(code: "USD").precision(.fractionLength(4)))")
                    .monospacedDigit()
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(duration == nil ? Color.secondary : Color(.success))
    }
}

struct AnalysisSummary: View {
    let model: AnalysisModel
    let scan: Scan

    var body: some View {
        let duration = scan.durations[model] ?? 0
        let identified = scan.dishes.filter { $0.results[model]?.name != nil }.count
        let usage = scan.usages[model]
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(model.name, systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color(.success))
                if model == .onDevice {
                    let modes = Dictionary(grouping: scan.dishes.compactMap { $0.results[model] }) { $0.mode ?? .balanced }
                    let used = MenuRecognitionMode.allCases.filter { modes[$0] != nil }
                    if let main = used.max(by: { modes[$0]!.count < modes[$1]!.count }) {
                        Label(
                            "분석 수준 · " + used.map { used.count > 1 ? "\($0.name) \(modes[$0]!.count)개" : $0.name }.joined(separator: " · "),
                            systemImage: AnalysisLevel(model: .onDevice, mode: main).symbol
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 16) {
                GridRow {
                    stat("총 시간", seconds(duration))
                    stat("음식당 평균", seconds(duration / Double(max(scan.dishes.count, 1))))
                    stat("식별", "\(identified)/\(scan.dishes.count)개")
                }
                if let usage {
                    GridRow {
                        stat("입력 토큰", usage.input.formatted())
                        stat("출력 토큰", usage.output.formatted())
                        if let cost = model.cost(of: usage) {
                            stat("예상 비용", cost.formatted(.currency(code: "USD").precision(.fractionLength(4))))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func seconds(_ value: TimeInterval) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))초"
    }
}
