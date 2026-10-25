//
//  RecapDetails.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import SubjectCutout
import SwiftUI

struct AuraDetail: View {
    let foods: [Recap.Food]
    let colors: [UUID: UIColor]

    var body: some View {
        let tones = Recap.tones(of: colors)
        let swatches = foods.compactMap { food in colors[food.id].map { (food: food, color: Color($0)) } }
        RecapPage(title: "입맛 오라", tint: .purple) { isRevealed in
            VStack(spacing: 20) {
                AuraOrb(tones: tones)
                    .frame(width: 220, height: 220)
                    .scaleEffect(isRevealed ? 1 : 0.5)
                VStack(spacing: 6) {
                    Text(tones.first?.tone.name ?? "색을 모으는 중")
                        .font(.largeTitle.bold())
                    Text("음식 \(colors.count)개의 색을 섞어 만든 오라예요.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            RecapSection(title: "색 분포") {
                GeometryReader { geometry in
                    HStack(spacing: 3) {
                        ForEach(tones, id: \.tone) { item in
                            Capsule()
                                .fill(item.tone.color.gradient)
                                .frame(width: max(8, geometry.size.width * CGFloat(item.count) / CGFloat(max(colors.count, 1)) - 3))
                        }
                    }
                    .scaleEffect(x: isRevealed ? 1 : 0, anchor: .leading)
                }
                .frame(height: 16)
                ForEach(tones, id: \.tone) { item in
                    HStack {
                        Circle()
                            .fill(item.tone.color)
                            .frame(width: 12, height: 12)
                        Text(item.tone.name)
                        Spacer()
                        Text(Double(item.count) / Double(max(colors.count, 1)), format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            RecapSection(title: "내 식탁 팔레트") {
                LazyVGrid(columns: Array(repeating: GridItem(spacing: 12), count: 4), spacing: 12) {
                    ForEach(swatches, id: \.food.id) { swatch in
                        CutoutImage(cutout: swatch.food.cutout)
                            .padding(10)
                            .frame(width: 64, height: 64)
                            .background(swatch.color.gradient, in: .circle)
                            .accessibilityLabel(swatch.food.name)
                    }
                }
            }
        }
    }
}

struct MenuDetail: View {
    let menus: [Recap.Menu]

    var body: some View {
        RecapPage(title: "TOP 메뉴", tint: .pink) { isRevealed in
            if let top = menus.first {
                VStack(spacing: 16) {
                    Podium(menus: Array(menus.prefix(3)), scale: 1.8)
                    VStack(spacing: 4) {
                        Text(top.name)
                            .font(.largeTitle.bold())
                        Text("\(top.foods.count)번 기록으로 1위")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }

            RecapSection(title: "메뉴 순위") {
                let most = Double(menus.first?.foods.count ?? 1)
                ForEach(Array(menus.prefix(10).enumerated()), id: \.element.id) { rank, menu in
                    HStack(spacing: 12) {
                        Text("\(rank + 1)")
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(.pink)
                            .frame(width: 28)
                        CutoutImage(cutout: menu.foods[0].cutout)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(menu.name)
                                .font(.headline)
                            Capsule()
                                .fill(.pink.gradient)
                                .containerRelativeFrame(.horizontal) { length, _ in
                                    max(8, length * 0.55 * Double(menu.foods.count) / most * (isRevealed ? 1 : 0))
                                }
                                .frame(height: 8)
                        }
                        Spacer(minLength: 0)
                        Text("\(menu.foods.count)번")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            RecapSection(title: "음식 도감 \(menus.count)종") {
                LazyVGrid(columns: Array(repeating: GridItem(spacing: 12), count: 4), spacing: 16) {
                    ForEach(menus) { menu in
                        VStack(spacing: 6) {
                            CutoutImage(cutout: menu.foods[0].cutout)
                                .frame(width: 60, height: 60)
                            Text(menu.name)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
    }
}

struct RhythmDetail: View {
    let recap: Recap

    var body: some View {
        let days = recap.dishesByDay
        let today = Calendar.current.startOfDay(for: .now)
        RecapPage(title: "식사 시계", tint: .orange) { _ in
            VStack(spacing: 16) {
                MealClock(dates: recap.scans.map(\.date), meal: recap.favoriteMeal)
                    .frame(width: 260, height: 260)
                if let meal = recap.favoriteMeal {
                    Text("주로 \(meal.name)에 기록해요")
                        .font(.title2.bold())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)

            RecapSection(title: "연속 기록") {
                Figure(value: recap.longestStreak, unit: "일")
                HStack {
                    ForEach((0..<7).reversed(), id: \.self) { offset in
                        let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) ?? today
                        let isRecorded = days[day] != nil
                        VStack(spacing: 6) {
                            Image(systemName: isRecorded ? "flame.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(isRecorded ? AnyShapeStyle(.orange.gradient) : AnyShapeStyle(.tertiary))
                                .frame(height: 32)
                            Text(day.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ko_KR"))))
                                .font(.caption)
                                .foregroundStyle(offset == 0 ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            RecapSection(title: "기록 캘린더") {
                let start = Calendar.current.date(byAdding: .weekOfYear, value: -15, to: Calendar.current.dateInterval(of: .weekOfYear, for: today)?.start ?? today) ?? today
                let most = Double(days.values.max() ?? 1)
                HStack(spacing: 4) {
                    ForEach(0..<16, id: \.self) { week in
                        VStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { weekday in
                                let day = Calendar.current.date(byAdding: .day, value: week * 7 + weekday, to: start) ?? start
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(days[day].map { Color.orange.opacity(0.35 + 0.65 * Double($0) / most) } ?? .white.opacity(day > today ? 0 : 0.08))
                                    .aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
                Text("\(recap.dishesByDay.count)일 동안 음식 \(recap.dishCount)개를 기록했어요.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StampDetail: View {
    let stamps: [Recap.Stamp]

    var body: some View {
        let earned = stamps.filter(\.isEarned).count
        RecapPage(title: "도장", tint: .red) { _ in
            RecapSection(title: "모은 도장") {
                Figure(value: earned, unit: "/ \(stamps.count)")
                Text("찍힌 도장을 탭하면 다시 꾹 눌러 볼 수 있어요.")
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 12), count: 3), spacing: 20) {
                ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                    StampSlot(stamp: stamp, index: index, delay: 0.35 + Double(stamps.prefix(index).filter(\.isEarned).count) * 0.22)
                }
            }
            .padding(20)
            .background(Recap.Stamp.paper, in: .rect(cornerRadius: 24))
            .environment(\.colorScheme, .light)
        }
    }
}

private struct StampSlot: View {
    let stamp: Recap.Stamp
    let index: Int
    let delay: Double

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(.black.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                if stamp.isEarned {
                    StampPress(stamp: stamp, index: index, delay: delay)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 88, height: 88)
            Text(stamp.title)
                .font(.subheadline.weight(.semibold))
            Text(stamp.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

struct VersusDetail: View {
    let recap: Recap

    var body: some View {
        let disagreements = recap.comparisons.filter { !$0.agrees }
        let models = AnalysisModel.allCases.filter { recap.dishCount(of: $0) > 0 }
        let usages = models.map(recap.usage)
        RecapPage(title: "AI 대결", tint: .mint) { isRevealed in
            RecapSection(title: "의견 일치율") {
                if let agreement = recap.agreement {
                    Figure(value: Int((agreement * 100).rounded()), unit: "%")
                    Text("두 모델이 모두 분석한 음식 \(recap.comparisons.count)개 중 \(recap.comparisons.count - disagreements.count)개의 이름이 같았어요.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("같은 기록을 두 모델로 모두 분석하면 결과를 비교해 드려요.")
                        .foregroundStyle(.secondary)
                }
            }

            if !models.isEmpty {
                RecapSection(title: "속도 대결") {
                    Race(lanes: models.map { ($0, recap.duration(of: $0) / Double(max(recap.dishCount(of: $0), 1))) })
                }
            }

            if !disagreements.isEmpty {
                RecapSection(title: "의견이 갈린 음식") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Text(AnalysisModel.onDevice.name)
                            Text(AnalysisModel.claude.name)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        ForEach(disagreements) { comparison in
                            GridRow {
                                CutoutImage(cutout: comparison.cutout)
                                    .frame(width: 48, height: 48)
                                Text(comparison.onDevice)
                                Text(comparison.claude)
                            }
                            .font(.headline)
                        }
                    }
                }
            }

            if !models.isEmpty {
                RecapSection(title: "토큰") {
                    Figure(value: usages.reduce(0) { $0 + $1.input + $1.output }, unit: "개")
                    Text("입력 \(usages.reduce(0) { $0 + $1.input }.formatted())개 · 출력 \(usages.reduce(0) { $0 + $1.output }.formatted())개")
                        .foregroundStyle(.secondary)
                    if let cost = AnalysisModel.claude.cost(of: recap.usage(of: .claude)), cost > 0 {
                        Text("Claude 예상 비용 \(cost, format: .currency(code: "USD").precision(.fractionLength(4)))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct Race: View {
    let lanes: [(model: AnalysisModel, average: TimeInterval)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRacing = false
    @State private var arrivals: [AnalysisModel] = []

    private func duration(of average: TimeInterval) -> TimeInterval {
        reduceMotion ? 0 : 2.4 * average / max(lanes.map(\.average).max() ?? 1, 0.1)
    }

    var body: some View {
        let fastest = lanes.min { $0.average < $1.average }?.model
        VStack(alignment: .leading, spacing: 18) {
            ForEach(lanes, id: \.model) { lane in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(lane.model.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("음식당 \(lane.average.formatted(.number.precision(.fractionLength(1))))초")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        let width = isRacing ? geometry.size.width : geometry.size.height
                        Capsule()
                            .fill(.white.opacity(0.1))
                        Group {
                            Capsule()
                                .fill(.mint.gradient)
                                .frame(width: width)
                            Image(systemName: lane.model == fastest ? "hare.fill" : "tortoise.fill")
                                .font(.title2)
                                .symbolEffect(.bounce, value: arrivals.contains(lane.model))
                                .offset(x: width - 36, y: -30)
                        }
                        .animation(.easeInOut(duration: duration(of: lane.average)), value: isRacing)
                    }
                    .frame(height: 14)
                    .padding(.top, 24)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: arrivals.count)
        .task {
            do { try await Task.sleep(for: .seconds(0.4)) }
            catch { return }
            isRacing = true
            var elapsed = 0.0
            for lane in lanes.sorted(by: { $0.average < $1.average }) {
                do { try await Task.sleep(for: .seconds(duration(of: lane.average) - elapsed)) }
                catch { return }
                elapsed = duration(of: lane.average)
                arrivals.append(lane.model)
            }
        }
    }
}
