//
//  MenuGames.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import SpriteKit
import SubjectCutout
import SwiftUI

// MARK: - Game State

enum MenuGame: CaseIterable, Hashable {
    case slot, lotto, wheel, croc

    var title: String? {
        switch self {
        case .slot: nil
        case .lotto: "메뉴 추첨기"
        case .wheel: "메뉴 돌림판"
        case .croc: "악어 먹이 주기"
        }
    }

    var symbol: String {
        switch self {
        case .slot: "rectangle.split.3x1.fill"
        case .lotto: "circle.hexagongrid.fill"
        case .wheel: "chart.pie.fill"
        case .croc: "lizard.fill"
        }
    }

    var tint: Color {
        switch self {
        case .slot: .red
        case .lotto: .pink
        case .wheel: .orange
        case .croc: .green
        }
    }

    var widgetAction: String {
        switch self {
        case .slot: "슬롯 돌리기"
        case .lotto: "추첨하기"
        case .wheel: "돌리기"
        case .croc: "던지기"
        }
    }

    var action: String {
        switch self {
        case .slot: "레버 당기기"
        case .lotto: "바람 세게"
        case .wheel: "돌리기"
        case .croc: "던지기"
        }
    }

    var pickTitle: String {
        self == .croc ? "악어가 먹은 메뉴" : "오늘의 메뉴"
    }

    var prompt: String {
        switch self {
        case .slot: "버튼을 길게 누르거나 레버를 당긴 채 버티면 점점 빨리 돌아요."
        case .lotto: "바람을 탄 음식이 솟아올라요. 하나를 잡아 아래 접시에 올려 보세요."
        case .wheel: "돌림판이나 버튼을 꾹 누르면 점점 빨리 돌아요."
        case .croc: "악어가 입을 벌렸을 때 공을 위로 튕겨 던져 보세요."
        }
    }

    var hint: String {
        switch self {
        case .slot: "릴이 돌아가는 중…"
        case .lotto: "마음에 드는 음식을 잡아 접시에 올려 보세요."
        case .wheel: "돌아가는 중…"
        case .croc: "입이 열릴 때를 노려 보세요."
        }
    }
}

@Observable
final class MenuDraw {
    let charge = Charge()
    private(set) var pick: Recap.Food?
    private(set) var isDrawing = false
    private(set) var round = 0
    private(set) var strength = 1.0

    func start(strength: Double = 1) {
        guard !isDrawing else { return }
        pick = nil
        isDrawing = true
        self.strength = strength
        round += 1
    }

    func finish(with food: Recap.Food) {
        pick = food
        isDrawing = false
    }

    func release() {
        isDrawing = false
    }
}

@Observable
final class Charge {
    private(set) var level = 0.0
    private(set) var step = 0
    private(set) var isCharging = false
    private var task: Task<Void, Never>?

    func begin() {
        guard task == nil else { return }
        level = 0
        isCharging = true
        task = Task {
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                level = min(level + 0.05, 1)
                step += 1
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isCharging = false
    }

    func consume() -> Double {
        stop()
        defer { level = 0 }
        return level
    }
}

// MARK: - Game Views

struct GameCard: View {
    let game: MenuGame
    let recap: Recap
    @State private var draw = MenuDraw()

    var body: some View {
        VStack(spacing: 10) {
            GameBoard(game: game, recap: recap, draw: draw)
                .contentShape(.rect)
                .onTapGesture { if !recap.foods.isEmpty { draw.start() } }
            ChargeButton(draw: draw, isEnabled: !recap.foods.isEmpty, gauge: .blue) {
                Text(draw.pick?.name ?? (draw.isDrawing && game != .croc ? "고르는 중…" : game.widgetAction))
            }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .buttonStyle(.glass)
                .contentTransition(.interpolate)
                .animation(.snappy, value: draw.pick?.id)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    NavigationLink(value: RecapView.Page.game(game)) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("크게 보기")
                }
        }
        .padding(game == .slot ? 16 : 12)
        .glassEffect(.regular.tint(game.tint.opacity(0.35)), in: .rect(cornerRadius: 28))
        .sensoryFeedback(trigger: draw.charge.step) { _, _ in .impact(weight: .heavy, intensity: 0.3 + draw.charge.level * 0.7) }
    }
}

private struct ChargeButton<Label: View>: View {
    let draw: MenuDraw
    let isEnabled: Bool
    let gauge: Color
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            let level = draw.charge.consume()
            if isEnabled { draw.start(strength: 1 + level * 2) }
        } label: {
            label
        }
        .background {
            GeometryReader { geometry in
                Capsule()
                    .fill(gauge.gradient)
                    .frame(width: geometry.size.width * draw.charge.level)
                    .animation(.linear(duration: draw.charge.level == 0 ? 0.2 : 0.09), value: draw.charge.level)
            }
            .clipShape(.capsule)
            .allowsHitTesting(false)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.15, maximumDistance: 30)
                .onEnded { _ in if isEnabled && !draw.isDrawing { draw.charge.begin() } }
        )
    }
}

struct GameScreen: View {
    let game: MenuGame
    let recap: Recap
    @State private var draw = MenuDraw()

    var body: some View {
        GameBoard(game: game, recap: recap, draw: draw, isExpanded: true)
            .padding(.horizontal, game == .lotto || game == .croc ? 0 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(colors: [game.tint.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) { panel }
            .navigationTitle(game.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var panel: some View {
        VStack(spacing: 16) {
            Group {
                if let pick = draw.pick {
                    let dates = recap.foods.filter { $0.name == pick.name }.map(\.date)
                    VStack(spacing: 4) {
                        Text(game.pickTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(game.tint)
                        Text(pick.name)
                            .font(.largeTitle.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("\(dates.count)번 기록 · 마지막 \((dates.max() ?? pick.date).formatted(.dateTime.month().day().locale(Locale(identifier: "ko_KR"))))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.blurReplace)
                } else {
                    Text(recap.foods.isEmpty ? "음식을 분석하면 메뉴를 뽑을 수 있어요." : draw.isDrawing && game != .croc ? game.hint : game.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.blurReplace)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            ChargeButton(draw: draw, isEnabled: !recap.foods.isEmpty, gauge: .orange) {
                Label(draw.pick == nil || game == .croc ? game.action : "다시 뽑기", systemImage: game.symbol)
            }
                .buttonStyle(.glass(.regular.tint(.yellow)))
                .foregroundStyle(.black)
                .controlSize(.large)
                .disabled(recap.foods.isEmpty || (draw.isDrawing && game != .croc))
        }
        .padding()
        .animation(.spring(duration: 0.5, bounce: 0.3), value: draw.pick?.id)
        .animation(.default, value: draw.isDrawing)
        .sensoryFeedback(trigger: draw.charge.step) { _, _ in .impact(weight: .heavy, intensity: 0.3 + draw.charge.level * 0.7) }
    }
}

private struct GameBoard: View {
    let game: MenuGame
    let recap: Recap
    let draw: MenuDraw
    var isExpanded = false

    var body: some View {
        switch game {
        case .slot:
            SlotMachine(menus: recap.menus, draw: draw, hasLever: isExpanded)
        case .lotto:
            if isExpanded {
                SceneBoard(foods: recap.foods, draw: draw) { BlowerScene() }
                    .ignoresSafeArea(edges: .top)
            } else {
                SceneBoard(foods: recap.foods, draw: draw) { LottoScene() }
                    .aspectRatio(1.35, contentMode: .fit)
            }
        case .wheel:
            MenuWheel(menus: recap.menus, draw: draw, isExpanded: isExpanded)
                .aspectRatio(isExpanded ? 1 : 1.35, contentMode: .fit)
        case .croc:
            if isExpanded {
                SceneBoard(foods: recap.foods, draw: draw) { CrocScene(isExpanded: true) }
            } else {
                SceneBoard(foods: recap.foods, draw: draw) { CrocScene(isExpanded: false) }
                    .aspectRatio(1.35, contentMode: .fit)
            }
        }
    }
}

private struct SceneBoard: View {
    let foods: [Recap.Food]
    let draw: MenuDraw
    let makeScene: () -> FoodScene
    @State private var scene: FoodScene?
    @State private var playedRound: Int?

    var body: some View {
        Color.clear
            .overlay {
                if let scene {
                    SpriteView(scene: scene, options: [.allowsTransparency, .ignoresSiblingOrder])
                        .transition(.opacity)
                }
            }
            .task {
                guard scene == nil else { return }
                do { try await Task.sleep(for: .milliseconds(350)) }
                catch { return }
                let scene = makeScene()
                scene.draw = draw
                withAnimation(.easeOut(duration: 0.3)) { self.scene = scene }
                await scene.load(foods)
                guard !Task.isCancelled else {
                    self.scene = nil
                    return
                }
                playedRound = 0
                play()
            }
            .onChange(of: draw.round) { play() }
    }

    private func play() {
        guard let scene, let playedRound, draw.isDrawing, draw.round != playedRound else { return }
        self.playedRound = draw.round
        if scene.items.isEmpty { draw.release() }
        else { scene.play() }
    }
}

// MARK: - Thumbnails

enum FoodThumbnails {
    private static var images: [URL: UIImage] = [:]

    static func image(of cutout: Cutout) async -> UIImage? {
        if let image = images[cutout.url] { return image }
        let bounds = cutout.bounds
        let scale = 320 / max(bounds.width, bounds.height, 1)
        let image = await UIImage(contentsOfFile: cutout.url.path)?.byPreparingThumbnail(
            ofSize: CGSize(width: bounds.width * scale, height: bounds.height * scale)
        )
        images[cutout.url] = image
        return image
    }

    static func prefetch(_ cutouts: [Cutout]) async {
        for cutout in cutouts.prefix(24) {
            guard !Task.isCancelled else { return }
            _ = await image(of: cutout)
        }
    }
}
