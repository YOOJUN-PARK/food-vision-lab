//
//  ContentView.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/23/26.
//

import MenuRecognition
import PhotosUI
import SubjectCutout
import SwiftData
import SwiftUI
import Vision

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Scan.date, order: .reverse) private var scans: [Scan]
    @State private var path = NavigationPath()
    @State private var isAdding = false
    @State private var usesCamera = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: Data?
    @State private var selection: CutoutSession?
    @State private var isEditing = false
    @State private var quality = GenerateIterativeSegmentationRequest.QualityLevel.balanced
    @State private var showsSettings = false
    @State private var showsRecap = false
    @Namespace private var namespace
    @AppStorage("analysisModel") private var analysisModel = AnalysisModel.onDevice
    @State private var error: String?
    @State private var analyzer = Analyzer()
    @State private var feedback = SensoryFeedback.success
    @State private var feedbackCount = 0

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(scans) { scan in
                    NavigationLink(value: scan) { card(for: scan) }
                        .navigationLinkIndicatorVisibility(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onDelete { offsets in
                    for index in offsets { delete(scans[index]) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .overlay {
                if scans.isEmpty {
                    ContentUnavailableView(
                        "사진 속 메뉴 찾기", systemImage: "fork.knife",
                        description: Text("음식을 촬영하거나 사진을 고르면 분석 기록이 여기에 쌓입니다.")
                    )
                }
            }
            .navigationTitle("Food Vision Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsRecap = true } label: {
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.3, green: 0.33, blue: 0.82), Color(red: 0.1, green: 0.55, blue: 0.55), Color(red: 0.9, green: 0.5, blue: 0.1), Color(red: 0.82, green: 0.22, blue: 0.36)],
                                    startPoint: UnitPoint(x: 0.4, y: 0), endPoint: UnitPoint(x: 1, y: 0.6)
                                ),
                                Color.accentColor
                            )
                            .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(delay: 2.5)))
                    }
                    .accessibilityLabel("Food Recap")
                }
                .matchedTransitionSource(id: "recap", in: namespace)
                ToolbarItem(placement: .principal) {
                    Label {
                        Text("Food Vision Lab").font(.headline.bold())
                    } icon: {
                        Image(.logo)
                            .resizable()
                            .frame(width: 28, height: 28)
                            .clipShape(.rect(cornerRadius: 7))
                    }
                    .labelStyle(.titleAndIcon)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("설정", systemImage: "gearshape") { showsSettings = true }
                }
            }
            .safeAreaBar(edge: .top) {
                if analyzer.isRunning, let scan = analyzer.scan {
                    Button { path.append(scan) } label: {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(analyzer.model.name) 분석 중")
                                    .font(.subheadline.weight(.semibold))
                                Text(analyzer.status)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
                        .contentShape(.rect(cornerRadius: 28))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
            .safeAreaBar(edge: .bottom) {
                Button("새 메뉴 찾기", systemImage: "camera.viewfinder") { isAdding = true }
                    .buttonStyle(.glass(.regular.tint(.yellow)))
                    .foregroundStyle(.black)
                    .controlSize(.large)
                    .matchedTransitionSource(id: "source", in: namespace)
                    .padding()
            }
            .navigationDestination(for: Scan.self) { scan in
                ScanView(scan: scan, analyzer: analyzer, model: analysisModel) { showsSettings = true }
            }
        }
        .sheet(isPresented: $isAdding, onDismiss: {
            selectedPhoto = nil
            isEditing = selection != nil
        }) { source }
        .fullScreenCover(isPresented: $isEditing, onDismiss: { selection = nil }) {
            if let selection, let photo {
                NavigationStack {
                    CutoutEditor(session: selection, directory: Scan.directory) { cutouts in
                        isEditing = false
                        guard !cutouts.isEmpty else { return }
                        let scan = Scan(photo: photo, cutouts: cutouts)
                        modelContext.insert(scan)
                        path.append(scan)
                        playFeedback(.success)
                    }
                }
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsView(quality: $quality) }
        .fullScreenCover(isPresented: $showsRecap) {
            RecapView()
                .navigationTransition(.zoom(sourceID: "recap", in: namespace))
        }
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("확인", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            defer {
                if self.selectedPhoto == selectedPhoto { self.selectedPhoto = nil }
            }
            do {
                let data = try await selectedPhoto.loadTransferable(type: Data.self)
                try Task.checkCancellation()
                guard isAdding else { return }
                guard let data else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                open(data)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    playFeedback(.error)
                }
            }
        }
        .task(id: scans.count) {
            let cutouts = scans.flatMap(\.cutouts)
            await CutoutImage.prefetch(cutouts)
            await FoodThumbnails.prefetch(cutouts)
        }
        .sensoryFeedback(feedback, trigger: feedbackCount)
        .sensoryFeedback(trigger: analyzer.finishCount) { _, _ in analyzer.didFail ? .error : .success }
    }

    private func card(for scan: Scan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scan.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if let data = scan.thumbnail, let image = UIImage(data: data) {
                Color.clear
                    .frame(height: 180)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(.rect(cornerRadius: 16))
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(scan.dishes) { dish in
                        VStack(spacing: 6) {
                            CutoutImage(cutout: scan.cutout(for: dish))
                                .frame(width: 64, height: 64)
                            Text(dish.results[analysisModel]?.name ?? "음식 \(dish.number)")
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .frame(width: 76)
                    }
                }
            }
            .scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(AnalysisModel.allCases) { model in
                    ModelStatus(
                        model: model, scan: scan,
                        isAnalyzing: analyzer.isAnalyzing(scan) && analyzer.model == model
                    )
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
        .contentShape(.rect(cornerRadius: 28))
    }

    private var source: some View {
        ZStack {
            if usesCamera {
                CameraView(onCapture: open)
                    .clipShape(ConcentricRectangle())
                    .padding(8)
                    .transition(.blurReplace)
            } else {
                NavigationStack {
                    PhotosPicker("사진 선택", selection: $selectedPhoto, matching: .images)
                        .photosPickerStyle(.inline)
                        .photosPickerAccessoryVisibility(.hidden, edges: .all)
                        .toolbarVisibility(.hidden, for: .navigationBar)
                }
                .transition(.blurReplace)
            }
        }
        .overlay(alignment: .bottom) {
            HStack {
                Button("닫기", systemImage: "xmark") { isAdding = false }
                Spacer()
                Button(usesCamera ? "사진" : "카메라", systemImage: usesCamera ? "photo.on.rectangle" : "camera.fill") {
                    usesCamera.toggle()
                }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .frame(height: 76)
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .animation(.smooth(duration: 0.35), value: usesCamera)
        .presentationDetents([.medium, .large])
        .presentationBackground(.background)
        .navigationTransition(.zoom(sourceID: "source", in: namespace))
    }

    private func open(_ data: Data) {
        guard let image = UIImage(data: data) else {
            error = CocoaError(.fileReadCorruptFile).localizedDescription
            return
        }
        photo = data
        selection = CutoutSession(image: image, quality: quality)
        isAdding = false
    }

    private func delete(_ scan: Scan) {
        if analyzer.isAnalyzing(scan) { analyzer.cancel() }
        try? FileManager.default.removeItem(at: scan.folderURL)
        modelContext.delete(scan)
    }

    private func playFeedback(_ feedback: SensoryFeedback) {
        self.feedback = feedback
        feedbackCount += 1
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Scan.self, inMemory: true)
}
