//
//  Recap.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import CoreImage.CIFilterBuiltins
import SubjectCutout
import SwiftUI

struct Recap {
    struct Food: Identifiable {
        let id: UUID
        let name: String
        let cutout: Cutout
        let date: Date
    }

    struct Menu: Identifiable {
        let name: String
        let foods: [Food]

        var id: String { name }
    }

    struct Comparison: Identifiable {
        let cutout: Cutout
        let onDevice: String
        let claude: String

        var id: UUID { cutout.id }
        var agrees: Bool { onDevice.filter { !$0.isWhitespace } == claude.filter { !$0.isWhitespace } }
    }

    struct Stamp: Identifiable {
        static let paper = Color(red: 0.97, green: 0.94, blue: 0.87)

        let title: String
        let detail: String
        let symbol: String
        let isEarned: Bool

        var id: String { title }
    }

    enum Meal: CaseIterable {
        case breakfast, lunch, dinner, lateNight

        init(_ date: Date) {
            switch Calendar.current.component(.hour, from: date) {
            case 5..<11: self = .breakfast
            case 11..<16: self = .lunch
            case 16..<21: self = .dinner
            default: self = .lateNight
            }
        }

        var name: String {
            switch self {
            case .breakfast: "아침"
            case .lunch: "점심"
            case .dinner: "저녁"
            case .lateNight: "야식"
            }
        }

        var symbol: String {
            switch self {
            case .breakfast: "sunrise.fill"
            case .lunch: "sun.max.fill"
            case .dinner: "sunset.fill"
            case .lateNight: "moon.stars.fill"
            }
        }

        var color: Color {
            switch self {
            case .breakfast: .orange
            case .lunch: .yellow
            case .dinner: .pink
            case .lateNight: .indigo
            }
        }
    }

    enum Tone: CaseIterable {
        case red, orange, yellow, green, purple, brown, white

        init(_ color: UIColor) {
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
            switch (hue * 360, saturation, brightness) {
            case (_, ..<0.2, 0.6...): self = .white
            case (_, ..<0.2, _), (15..<50, _, ..<0.55): self = .brown
            case (..<15, _, _), (330..., _, _): self = .red
            case (15..<40, _, _): self = .orange
            case (40..<70, _, _): self = .yellow
            case (70..<170, _, _): self = .green
            default: self = .purple
            }
        }

        var name: String {
            switch self {
            case .red: "매콤한 빨강"
            case .orange: "바삭한 주황"
            case .yellow: "달콤한 노랑"
            case .green: "싱그러운 초록"
            case .purple: "새콤한 보라"
            case .brown: "노릇노릇 캐러멜"
            case .white: "포근한 크림"
            }
        }

        var color: Color {
            switch self {
            case .red: .red
            case .orange: .orange
            case .yellow: .yellow
            case .green: .green
            case .purple: .purple
            case .brown: Color(red: 0.88, green: 0.56, blue: 0.26)
            case .white: Color(red: 1, green: 0.9, blue: 0.74)
            }
        }
    }

    nonisolated private static let context = CIContext()

    let scans: [Scan]
    let foods: [Food]
    let menus: [Menu]
    let comparisons: [Comparison]

    init(scans: [Scan], model: AnalysisModel) {
        self.scans = scans
        foods = scans.flatMap { scan in
            scan.dishes.compactMap { dish in
                let name = dish.results[model]?.name ?? AnalysisModel.allCases.lazy.compactMap { dish.results[$0]?.name }.first
                return name.map { Food(id: dish.id, name: $0, cutout: scan.cutout(for: dish), date: scan.date) }
            }
        }
        menus = Dictionary(grouping: foods, by: \.name)
            .map { Menu(name: $0.key, foods: $0.value.sorted { $0.date > $1.date }) }
            .sorted { ($0.foods.count, $0.foods[0].date) > ($1.foods.count, $1.foods[0].date) }
        comparisons = scans.flatMap { scan in
            scan.dishes.compactMap { dish in
                guard let onDevice = dish.results[.onDevice]?.name, let claude = dish.results[.claude]?.name else { return nil }
                return Comparison(cutout: scan.cutout(for: dish), onDevice: onDevice, claude: claude)
            }
        }
    }

    var dishCount: Int { scans.reduce(0) { $0 + $1.dishes.count } }

    var dishesByDay: [Date: Int] {
        Dictionary(grouping: scans) { Calendar.current.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.dishes.count } }
    }

    var meals: [Meal: Int] { Dictionary(grouping: scans) { Meal($0.date) }.mapValues(\.count) }

    var favoriteMeal: Meal? {
        scans.isEmpty ? nil : Meal.allCases.max { meals[$0, default: 0] < meals[$1, default: 0] }
    }

    var longestStreak: Int {
        var longest = 0
        var current = 0
        var previous: Date?
        for day in dishesByDay.keys.sorted() {
            current = previous.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) } == day ? current + 1 : 1
            longest = max(longest, current)
            previous = day
        }
        return longest
    }

    var agreement: Double? {
        comparisons.isEmpty ? nil : Double(comparisons.filter(\.agrees).count) / Double(comparisons.count)
    }

    var stamps: [Stamp] {
        [
            Stamp(title: "첫 한 입", detail: "첫 기록 남기기", symbol: "fork.knife", isEarned: !scans.isEmpty),
            Stamp(title: "푸짐한 한 상", detail: "한 번에 음식 5개", symbol: "square.stack.3d.up.fill", isEarned: scans.contains { $0.dishes.count >= 5 }),
            Stamp(title: "단골손님", detail: "같은 메뉴 3번", symbol: "heart.fill", isEarned: (menus.first?.foods.count ?? 0) >= 3),
            Stamp(title: "메뉴 탐험가", detail: "메뉴 10가지", symbol: "map.fill", isEarned: menus.count >= 10),
            Stamp(title: "꾸준함", detail: "3일 연속 기록", symbol: "flame.fill", isEarned: longestStreak >= 3),
            Stamp(title: "아침형 인간", detail: "아침 기록", symbol: "sunrise.fill", isEarned: meals[.breakfast] != nil),
            Stamp(title: "야식 클럽", detail: "밤 9시 이후 기록", symbol: "moon.stars.fill", isEarned: meals[.lateNight] != nil),
            Stamp(title: "AI 심판", detail: "두 모델로 비교하기", symbol: "person.2.fill", isEarned: !comparisons.isEmpty),
            Stamp(title: "미식가", detail: "음식 50개 기록", symbol: "crown.fill", isEarned: dishCount >= 50)
        ]
    }

    func duration(of model: AnalysisModel) -> TimeInterval {
        scans.compactMap { $0.durations[model] }.reduce(0, +)
    }

    func dishCount(of model: AnalysisModel) -> Int {
        scans.filter { $0.durations[model] != nil }.reduce(0) { $0 + $1.dishes.count }
    }

    func usage(of model: AnalysisModel) -> TokenUsage {
        scans.compactMap { $0.usages[model] }.reduce(into: TokenUsage()) { total, usage in
            total.input += usage.input
            total.cachedInput = (total.cachedInput ?? 0) + (usage.cachedInput ?? 0)
            total.output += usage.output
        }
    }

    static func tones(of colors: [UUID: UIColor]) -> [(tone: Tone, count: Int)] {
        Dictionary(grouping: colors.values) { Tone($0) }
            .map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private static var colorCache: [UUID: UIColor] = [:]

    static func cachedColors(of foods: [Food]) async -> [UUID: UIColor] {
        let missing = foods.prefix(60).filter { colorCache[$0.id] == nil }
        if !missing.isEmpty { colorCache.merge(await colors(of: Array(missing))) { $1 } }
        return colorCache.filter { id, _ in foods.contains { $0.id == id } }
    }

    @concurrent
    nonisolated private static func colors(of foods: [Food]) async -> [UUID: UIColor] {
        var colors: [UUID: UIColor] = [:]
        for food in foods.prefix(60) {
            guard !Task.isCancelled else { return colors }
            guard let image = CIImage(contentsOf: food.cutout.url) else { continue }
            let filter = CIFilter.areaAverage()
            filter.inputImage = image
            filter.extent = image.extent
            guard let output = filter.outputImage else { continue }
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            guard pixel[3] > 0 else { continue }
            let alpha = CGFloat(pixel[3])
            colors[food.id] = UIColor(red: CGFloat(pixel[0]) / alpha, green: CGFloat(pixel[1]) / alpha, blue: CGFloat(pixel[2]) / alpha, alpha: 1)
        }
        return colors
    }
}
