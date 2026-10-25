//
//  RecapView.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import SubjectCutout
import SwiftData
import SwiftUI

struct RecapView: View {
    enum Page: Hashable {
        case game(MenuGame), aura, menus, rhythm, stamps, versus
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Scan.date, order: .reverse) private var scans: [Scan]
    @AppStorage("analysisModel") private var analysisModel = AnalysisModel.onDevice
    @Namespace private var namespace
    @State private var path: [Page] = []
    @State private var colors: [UUID: UIColor] = [:]

    var body: some View {
        let recap = Recap(scans: scans, model: analysisModel)
        NavigationStack(path: $path) {
            Group {
                if scans.isEmpty {
                    ContentUnavailableView(
                        "아직 돌아볼 기록이 없어요", systemImage: "party.popper",
                        description: Text("음식을 기록하고 분석하면 리캡이 채워집니다.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header("오늘 뭐 먹지?")
                            GameCard(game: .slot, recap: recap)
                                .matchedTransitionSource(id: Page.game(.slot), in: namespace)
                            ScrollView(.horizontal) {
                                HStack(spacing: 12) {
                                    ForEach([MenuGame.lotto, .wheel, .croc], id: \.self) { game in
                                        GameCard(game: game, recap: recap)
                                            .containerRelativeFrame(.horizontal, count: 2, spacing: 12)
                                            .matchedTransitionSource(id: Page.game(game), in: namespace)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                            .scrollIndicators(.hidden)
                            .scrollClipDisabled()

                            header("나의 식탁")
                            card(.stamps, "도장", systemImage: "seal.fill", tint: .red) {
                                StampCard(stamps: recap.stamps)
                            }
                            HStack(spacing: 12) {
                                card(.menus, "TOP 메뉴", systemImage: "trophy.fill", tint: .pink) {
                                    TopMenuCard(menus: recap.menus)
                                }
                                card(.rhythm, "식사 시계", systemImage: "clock.fill", tint: .orange) {
                                    RhythmCard(recap: recap)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 12) {
                                card(.versus, "AI 대결", systemImage: "bolt.fill", tint: .mint) {
                                    VersusCard(agreement: recap.agreement)
                                }
                                card(.aura, "입맛 오라", systemImage: "sparkles", tint: .purple) {
                                    AuraCard(colors: colors)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                    }
                }
            }
            .background {
                LiquidGradient(colors: [.indigo, .purple, .pink, .blue, .orange, .red, .teal, .indigo, .purple])
                    .overlay(.black.opacity(0.45))
                    .ignoresSafeArea()
            }
            .navigationTitle("Food Recap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: Page.self) { page in
                destination(for: page, recap: recap)
                    .navigationTransition(.zoom(sourceID: page, in: namespace))
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: path)
        .task(id: recap.foods.count) {
            do { try await Task.sleep(for: .milliseconds(450)) }
            catch { return }
            let result = await Recap.cachedColors(of: recap.foods)
            if !Task.isCancelled { colors = result }
        }
    }

    @ViewBuilder
    private func destination(for page: Page, recap: Recap) -> some View {
        switch page {
        case let .game(game): GameScreen(game: game, recap: recap)
        case .aura: AuraDetail(foods: recap.foods, colors: colors)
        case .menus: MenuDetail(menus: recap.menus)
        case .rhythm: RhythmDetail(recap: recap)
        case .stamps: StampDetail(stamps: recap.stamps)
        case .versus: VersusDetail(recap: recap)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, 12)
    }

    private func card(
        _ page: Page, _ title: String, systemImage: String, tint: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        NavigationLink(value: page) {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(title).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: systemImage).foregroundStyle(tint)
                }
                .font(.subheadline.weight(.semibold))
                content()
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .contentShape(.rect(cornerRadius: 28))
            .glassEffect(.regular.tint(tint.opacity(0.3)).interactive(), in: .rect(cornerRadius: 28))
            .matchedTransitionSource(id: page, in: namespace)
        }
        .buttonStyle(.plain)
        .scrollTransition { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                .opacity(phase.isIdentity ? 1 : 0.6)
        }
    }
}

private struct AuraCard: View {
    let colors: [UUID: UIColor]

    var body: some View {
        let tones = Recap.tones(of: colors)
        AuraOrb(tones: tones)
            .frame(width: 80, height: 80)
            .frame(maxWidth: .infinity, minHeight: 88)
        Spacer(minLength: 0)
        VStack(alignment: .leading, spacing: 2) {
            Text(tones.first?.tone.name ?? "색을 모으는 중")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("식탁에 가장 자주 오른 색")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TopMenuCard: View {
    let menus: [Recap.Menu]

    var body: some View {
        if let top = menus.first {
            Podium(menus: Array(menus.prefix(3)), scale: 0.8)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(top.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(top.foods.count)번 기록으로 1위")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("분석한 음식이 생기면 순위를 보여 드려요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RhythmCard: View {
    let recap: Recap

    var body: some View {
        MealClock(dates: recap.scans.map(\.date), meal: recap.favoriteMeal)
            .frame(maxWidth: .infinity, maxHeight: 120)
        Spacer(minLength: 0)
        Label("최장 \(recap.longestStreak)일 연속", systemImage: "flame.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct StampCard: View {
    let stamps: [Recap.Stamp]

    var body: some View {
        let earned = stamps.enumerated().filter(\.element.isEarned)
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                Circle()
                    .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                if let latest = earned.last {
                    StampPress(stamp: latest.element, index: latest.offset, size: 96, delay: 0.5)
                        .shadow(color: StampMark.ink(latest.offset, isBright: true).opacity(0.5), radius: 10)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(earned.last?.element.title ?? "첫 도장을 모아 보세요")
                        .font(.title3.bold())
                    Text(earned.last.map { "새로 받은 도장 · \($0.element.detail)" } ?? "기록을 남기면 도장이 찍혀요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach([0, 5], id: \.self) { start in
                        GridRow {
                            ForEach(start..<min(start + 5, stamps.count), id: \.self) { index in
                                slot(stamps[index], index: index)
                            }
                        }
                    }
                }
                Text("\(earned.count) / \(stamps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func slot(_ stamp: Recap.Stamp, index: Int) -> some View {
        Group {
            if stamp.isEarned {
                Image(systemName: stamp.symbol)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(StampMark.ink(index, isBright: true))
                    .frame(width: 24, height: 24)
                    .overlay { Circle().strokeBorder(StampMark.ink(index, isBright: true), lineWidth: 2) }
                    .rotationEffect(.degrees(Double(index * 7 % 5 - 2) * 7))
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    .frame(width: 24, height: 24)
            }
        }
    }
}

private struct VersusCard: View {
    let agreement: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFacing = false

    var body: some View {
        HStack {
            Image(systemName: "iphone")
                .offset(x: isFacing || reduceMotion ? 0 : -30)
            Spacer()
            Text("VS")
                .font(.title2.weight(.black).italic())
                .scaleEffect(isFacing || reduceMotion ? 1 : 0.2)
            Spacer()
            Image(systemName: "cloud.fill")
                .offset(x: isFacing || reduceMotion ? 0 : 30)
        }
        .font(.title)
        .padding(.horizontal, 8)
        .frame(minHeight: 72)
        .task { withAnimation(.spring(duration: 0.6, bounce: 0.5).delay(0.3)) { isFacing = true } }
        Spacer(minLength: 0)
        VStack(alignment: .leading, spacing: 2) {
            if let agreement {
                Text("\(agreement, format: .percent.precision(.fractionLength(0))) 일치")
                    .font(.headline)
                Text("온디바이스 vs Claude")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("두 모델로 분석하면 대결이 시작돼요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LiquidGradient: View {
    let colors: [Color]
    var speed = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate * speed
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, Float(0.5 + 0.15 * sin(time * 0.8))],
                    [Float(0.5 + 0.25 * sin(time)), Float(0.5 + 0.2 * cos(time * 0.8))],
                    [1, Float(0.5 + 0.15 * cos(time * 0.9))],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: (0..<9).map { colors[$0 % colors.count] }
            )
        }
    }
}

struct AuraOrb: View {
    let tones: [(tone: Recap.Tone, count: Int)]

    var body: some View {
        let colors = tones.isEmpty ? [Color.purple, .pink, .indigo] : tones.prefix(3).map(\.tone.color)
        LiquidGradient(colors: colors, speed: 1.2)
            .clipShape(.circle)
            .blur(radius: 3)
            .shadow(color: colors[0].opacity(0.8), radius: 18)
    }
}

struct Podium: View {
    let menus: [Recap.Menu]
    var scale: CGFloat = 1
    @State private var isRaised = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6 * scale) {
            ForEach([1, 0, 2].filter { $0 < menus.count }, id: \.self) { rank in
                VStack(spacing: 4 * scale) {
                    CutoutImage(cutout: menus[rank].foods[0].cutout)
                        .frame(width: (rank == 0 ? 60 : 46) * scale, height: (rank == 0 ? 60 : 46) * scale)
                        .scaleEffect(isRaised ? 1 : 0.3)
                        .opacity(isRaised ? 1 : 0)
                    Text("\(rank + 1)")
                        .font(.system(size: 18 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.7))
                        .padding(.top, 4 * scale)
                        .frame(width: 48 * scale, height: (isRaised ? [52, 36, 24][rank] : 6) * scale, alignment: .top)
                        .background([Color.yellow, Color(white: 0.85), .orange][rank].gradient, in: .rect(cornerRadius: 8 * scale))
                }
                .animation(.spring(duration: 0.7, bounce: 0.4).delay(0.2 + Double(2 - rank) * 0.12), value: isRaised)
            }
        }
        .task { isRaised = true }
    }
}

struct MealClock: View {
    let dates: [Date]
    let meal: Recap.Meal?
    @State private var isShown = false

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: radius * 0.16)
                    .padding(radius * 0.08)
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    let angle = Angle.degrees(Double(hour) * 15).radians
                    Text("\(hour)")
                        .font(.system(size: radius * 0.13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .offset(x: sin(angle) * radius * 0.64, y: -cos(angle) * radius * 0.64)
                }
                ForEach(dates.indices, id: \.self) { index in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: dates[index])
                    let angle = Angle.degrees(Double((components.hour ?? 0) * 60 + (components.minute ?? 0)) / 4).radians
                    let distance = radius * (0.92 - 0.04 * CGFloat(index % 3))
                    Circle()
                        .fill(Recap.Meal(dates[index]).color)
                        .frame(width: radius * 0.12, height: radius * 0.12)
                        .scaleEffect(isShown ? 1 : 0)
                        .offset(x: sin(angle) * distance, y: -cos(angle) * distance)
                        .animation(.spring(duration: 0.5, bounce: 0.5).delay(Double(index) * 0.03), value: isShown)
                }
                if let meal {
                    VStack(spacing: 2) {
                        Image(systemName: meal.symbol)
                            .font(.system(size: radius * 0.3))
                            .foregroundStyle(meal.color)
                            .symbolEffect(.bounce, value: isShown)
                        Text("\(meal.name)형")
                            .font(.system(size: radius * 0.17, weight: .bold))
                    }
                }
            }
            .frame(width: radius * 2, height: radius * 2)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .task { isShown = true }
    }
}

struct StampMark: View {
    let stamp: Recap.Stamp
    let index: Int
    var size: CGFloat = 88
    @Environment(\.colorScheme) private var colorScheme

    static func ink(_ index: Int, isBright: Bool = false) -> Color {
        Color(hue: Double(index) / 9, saturation: isBright ? 0.5 : 0.75, brightness: isBright ? 1 : 0.7)
    }

    var body: some View {
        VStack(spacing: size * 0.02) {
            Image(systemName: stamp.symbol)
                .font(.system(size: size * 0.26, weight: .heavy))
            Text(stamp.title)
                .font(.system(size: size * 0.12, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(size * 0.16)
        .frame(width: size, height: size)
        .overlay { Circle().strokeBorder(lineWidth: size * 0.045) }
        .overlay {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: size * 0.018, dash: [size * 0.035, size * 0.025]))
                .padding(size * 0.09)
        }
        .foregroundStyle(Self.ink(index, isBright: colorScheme == .dark))
        .opacity(0.88)
        .rotationEffect(.degrees(Double(index * 7 % 5 - 2) * 7))
    }
}

struct StampPress: View {
    let stamp: Recap.Stamp
    let index: Int
    var size: CGFloat = 88
    var delay = 0.3
    @State private var height = 2.0
    @State private var impacts = 0

    var body: some View {
        StampMark(stamp: stamp, index: index, size: size)
            .scaleEffect(height)
            .opacity(min(max(2 - height, 0), 1))
            .contentShape(.circle)
            .onTapGesture { press(from: 1.35) }
            .sensoryFeedback(.impact(weight: .heavy), trigger: impacts)
            .task {
                guard impacts == 0 else { return }
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                press(from: 2)
            }
    }

    private func press(from height: Double) {
        withAnimation(.easeOut(duration: 0.14)) { self.height = height } completion: {
            withAnimation(.easeIn(duration: 0.11)) { self.height = 1 } completion: {
                impacts += 1
            }
        }
    }
}

struct RecapPage<Content: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let content: (Bool) -> Content
    @State private var isRevealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                content(isRevealed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background {
            LinearGradient(colors: [tint.opacity(0.6), .black], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { withAnimation(.spring(duration: 0.8, bounce: 0.3).delay(0.3)) { isRevealed = true } }
    }
}

struct RecapSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            content
        }
    }
}

struct Figure: View {
    let value: Int
    let unit: String
    @State private var shown = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(shown, format: .number)
                .font(.system(size: 64, weight: .bold))
                .contentTransition(.numericText(value: Double(shown)))
            Text(unit)
                .font(.title)
                .foregroundStyle(.secondary)
        }
        .task(id: value) { withAnimation(.smooth(duration: 1)) { shown = value } }
    }
}
