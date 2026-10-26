//
//  SettingsView.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import MenuRecognition
import SwiftUI
import Vision

struct SettingsView: View {
    private static let qualities: [(level: GenerateIterativeSegmentationRequest.QualityLevel, name: String)] = [
        (.fast, "빠르게"), (.balanced, "균형"), (.accurate, "정밀하게")
    ]

    @Environment(\.dismiss) private var dismiss
    @Binding var quality: GenerateIterativeSegmentationRequest.QualityLevel
    @AppStorage("analysisModel") private var analysisModel = AnalysisModel.onDevice
    @AppStorage("recognitionMode") private var recognitionMode = MenuRecognitionMode.balanced

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("홈 표시") {
                        Menu {
                            Picker("홈 표시", selection: $analysisModel) {
                                ForEach(AnalysisModel.allCases) { Text($0.name).tag($0) }
                            }
                        } label: {
                            MenuValue(title: analysisModel.name)
                        }
                    }
                    LabeledContent("Foundation Models 모드") {
                        Menu {
                            Picker("Foundation Models 모드", selection: $recognitionMode) {
                                ForEach(MenuRecognitionMode.allCases) { Text($0.name).tag($0) }
                            }
                        } label: {
                            MenuValue(title: recognitionMode.name)
                        }
                    }
                } header: {
                    Text("메뉴 인식")
                } footer: {
                    Text("홈 화면 기록 카드에 표시할 메뉴 인식 결과를 선택합니다.")
                }

                Section {
                    LabeledContent("구분 정확도") {
                        Menu {
                            Picker("구분 정확도", selection: $quality) {
                                ForEach(Self.qualities, id: \.level) { Text($0.name).tag($0.level) }
                            }
                        } label: {
                            MenuValue(title: Self.qualities.first { $0.level == quality }?.name ?? "")
                        }
                    }
                } header: {
                    Text("음식 선택")
                } footer: {
                    Text("정밀할수록 음식 경계를 더 정확히 구분하지만 시간이 더 걸립니다.")
                }

                Section {
                    NavigationLink {
                        Form {
                            ForEach(APIProvider.allCases) { APIKeySection(provider: $0) }
                        }
                        .navigationTitle("API 관리")
                    } label: {
                        Label("API 관리", systemImage: "key")
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

private struct MenuValue: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
        }
        .fontWeight(.semibold)
    }
}

private struct APIKeySection: View {
    let provider: APIProvider
    @State private var draft = ""
    @State private var isSaved = false
    @State private var changes = 0
    @State private var error: String?

    var body: some View {
        Section {
            SecureField(isSaved ? "새 API 키 입력" : "API 키 입력", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("저장", action: save)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if isSaved {
                Button("저장된 키 삭제", role: .destructive, action: delete)
            }
        } header: {
            Text(provider.rawValue)
        } footer: {
            if let error {
                Text(error).foregroundStyle(.red)
            } else {
                Text("키는 이 기기의 키체인에만 보관됩니다.")
            }
        }
        .task {
            do { isSaved = try APIKeyStore.read(provider) != nil }
            catch { self.error = error.localizedDescription }
        }
        .sensoryFeedback(.success, trigger: changes)
    }

    private func save() {
        do {
            try APIKeyStore.save(draft.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
            draft = ""
            isSaved = true
            changes += 1
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try APIKeyStore.delete(provider)
            isSaved = false
            changes += 1
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
