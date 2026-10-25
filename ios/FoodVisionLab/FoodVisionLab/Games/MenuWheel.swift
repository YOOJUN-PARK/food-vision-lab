//
//  MenuWheel.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import SubjectCutout
import SwiftUI

struct MenuWheel: View {
    let menus: [Recap.Menu]
    let draw: MenuDraw
    let isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var finger: Double?

    private var slices: [WheelFace.Slice] {
        let menus = menus.prefix(8)
        let total = Double(menus.reduce(0) { $0 + $1.foods.count })
        var start = 0.0
        return menus.enumerated().map { index, menu in
            let end = start + 360 * Double(menu.foods.count) / total
            defer { start = end }
            return WheelFace.Slice(menu: menu, start: start, end: end, color: Color(hue: Double(index) / Double(menus.count), saturation: 0.5, brightness: 1))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            WheelFace(angle: angle, slices: slices, winner: draw.pick?.name, ticks: draw.isDrawing || draw.charge.isCharging || finger != nil)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard !draw.isDrawing else { return }
                            draw.charge.begin()
                            let current = Angle(radians: atan2(value.location.y - center.y, value.location.x - center.x)).degrees
                            if let finger {
                                let delta = current - finger
                                angle += delta > 180 ? delta - 360 : delta < -180 ? delta + 360 : delta
                            }
                            finger = current
                        }
                        .onEnded { value in
                            finger = nil
                            let level = draw.charge.consume()
                            let speed = hypot(value.velocity.width, value.velocity.height)
                            if level > 0.15 || speed > 300 { draw.start(strength: max(min(speed / 1500, 2), 1 + level * 2)) }
                        },
                    isEnabled: isExpanded && !menus.isEmpty
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: drifts) { await drift() }
        .onChange(of: draw.round) { spin() }
    }

    private var drifts: Bool {
        !menus.isEmpty && !draw.isDrawing && !reduceMotion && (draw.charge.isCharging || draw.pick == nil)
    }

    private func drift() async {
        guard drifts else { return }
        var last = Date.now
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(draw.charge.isCharging ? 16 : 33)) }
            catch { return }
            let now = Date.now
            angle += (draw.charge.isCharging ? 40 + draw.charge.level * 900 : 10) * now.timeIntervalSince(last)
            last = now
        }
    }

    private func spin() {
        let slices = slices
        guard let food = slices.flatMap(\.menu.foods).randomElement(),
              let slice = slices.first(where: { $0.menu.name == food.name }) else { return }
        let margin = (slice.end - slice.start) * 0.15
        let target = Double.random(in: slice.start + margin...slice.end - margin)
        let offset = ((360 - target - angle).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let turns = (4 + draw.strength * 4).rounded()
        withAnimation(.timingCurve(0.12, 0.8, 0.2, 1, duration: reduceMotion ? 1 : 4 + draw.strength * 0.8)) {
            angle += turns * 360 + offset
        } completion: {
            draw.finish(with: food)
        }
    }
}

private struct WheelFace: View, Animatable {
    struct Slice {
        let menu: Recap.Menu
        let start: Double
        let end: Double
        let color: Color
    }

    var angle: Double
    let slices: [Slice]
    let winner: String?
    let ticks: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let pointer = (360 - angle.truncatingRemainder(dividingBy: 360)).truncatingRemainder(dividingBy: 360)
        let index = slices.firstIndex { $0.start <= pointer && pointer < $0.end } ?? 0
        let gap = slices.map { slice in
            let distance = abs(pointer - slice.start)
            return min(distance, 360 - distance)
        }.min() ?? 90
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            ZStack {
                ForEach(slices.indices, id: \.self) { index in
                    let slice = slices[index]
                    let middle = (slice.start + slice.end) / 2
                    SliceShape(start: slice.start, end: slice.end)
                        .fill(slice.color.gradient)
                        .opacity(winner == nil || winner == slice.menu.name ? 1 : 0.35)
                        .animation(.easeInOut, value: winner)
                    SliceShape(start: slice.start, end: slice.end)
                        .stroke(.white.opacity(0.7), lineWidth: 1.5)
                    CutoutImage(cutout: slice.menu.foods[0].cutout)
                        .frame(width: radius * 0.4, height: radius * 0.4)
                        .rotationEffect(.degrees(middle))
                        .offset(y: -radius * 0.6)
                        .rotationEffect(.degrees(middle))
                    Circle()
                        .fill(.white)
                        .frame(width: radius * 0.06, height: radius * 0.06)
                        .offset(y: -radius * 0.93)
                        .rotationEffect(.degrees(slice.start))
                }
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: radius * 0.03)
            }
            .rotationEffect(.degrees(angle))
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.system(size: radius * 0.16, weight: .bold))
                    .frame(width: radius * 0.4, height: radius * 0.4)
                    .glassEffect(in: .circle)
            }
            .overlay(alignment: .top) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: radius * 0.2))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .rotationEffect(.degrees(-max(0, 1 - gap / 10) * 28), anchor: .top)
                    .offset(y: -radius * 0.08)
            }
            .frame(width: radius * 2, height: radius * 2)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .sensoryFeedback(trigger: index) { _, _ in ticks ? .selection : nil }
    }
}

private struct SliceShape: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center, radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(start - 90), endAngle: .degrees(end - 90), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
