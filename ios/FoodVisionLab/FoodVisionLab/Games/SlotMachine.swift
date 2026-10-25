//
//  SlotMachine.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import SwiftUI

struct SlotMachine: View {
    let menus: [Recap.Menu]
    let draw: MenuDraw
    let hasLever: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var strips: [[Recap.Menu]] = []
    @State private var images: [String: UIImage] = [:]
    @State private var offsets = [0.0, 0.0, 0.0]
    @State private var spinning = [false, false, false]
    @State private var pull = 0.0
    @State private var isPulledByHand = false
    @State private var stops = 0
    @State private var isJackpot = false
    @State private var playedRound = 0

    private var marqueeHeight: CGFloat { hasLever ? 0.15 : 0.12 }
    private var reelHeight: CGFloat { hasLever ? 0.72 : 0.3 }
    private var heightRatio: CGFloat { 0.1 + marqueeHeight + reelHeight + (hasLever ? 0.06 + 0.11 : 0.03) }
    private var drifts: Bool {
        !strips.isEmpty && !draw.isDrawing && !reduceMotion && draw.charge.isCharging
    }

    var body: some View {
        let leverShare = hasLever ? 0.13 : 0
        GeometryReader { geometry in
            let width = geometry.size.width / (1 + leverShare)
            HStack(spacing: 0) {
                cabinet(width: width)
                if hasLever {
                    lever(CGSize(width: width * leverShare, height: width * heightRatio))
                }
            }
        }
        .aspectRatio((1 + leverShare) / heightRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: hasLever ? .infinity : nil)
        .task { await prepare() }
        .task(id: drifts) { await drift() }
        .onChange(of: draw.round) { spin() }
        .sensoryFeedback(.impact(weight: .medium), trigger: stops)
        .sensoryFeedback(trigger: isJackpot) { _, isJackpot in isJackpot ? .success : nil }
    }

    private func cabinet(width: CGFloat) -> some View {
        let corner = width * 0.08
        return VStack(spacing: width * 0.03) {
            Marquee(isJackpot: isJackpot)
                .frame(height: width * marqueeHeight)
            HStack(spacing: width * 0.015) {
                ForEach(0..<3, id: \.self) { reel in
                    SlotReel(offset: offsets[reel], strip: strips.indices.contains(reel) ? strips[reel] : [], images: images)
                        .blur(radius: spinning[reel] ? 1.5 : 0)
                        .clipShape(.rect(cornerRadius: corner * 0.4))
                }
            }
            .padding(width * 0.015)
            .frame(height: width * reelHeight)
            .background(.black.opacity(0.4), in: .rect(cornerRadius: corner * 0.6))
            .overlay {
                Rectangle()
                    .fill(.red.opacity(0.7))
                    .frame(height: 2)
            }
            .overlay {
                LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center)
                    .clipShape(.rect(cornerRadius: corner * 0.6))
                    .allowsHitTesting(false)
            }
            .shadow(color: .yellow.opacity(isJackpot ? 0.9 : 0), radius: 14)
            .animation(.easeInOut(duration: 0.4), value: isJackpot)
            if hasLever {
                deck(width: width)
                    .frame(height: width * 0.11)
            }
        }
        .padding(width * 0.05)
        .frame(width: width)
        .background(
            LinearGradient(colors: [Color(red: 0.96, green: 0.3, blue: 0.35), Color(red: 0.55, green: 0.05, blue: 0.2)], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: corner)
        )
        .overlay {
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(LinearGradient(colors: [.yellow, .orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
        }
    }

    private func deck(width: CGFloat) -> some View {
        HStack(spacing: width * 0.03) {
            Capsule()
                .fill(.black.opacity(0.55))
                .frame(width: width * 0.2, height: width * 0.025)
            Spacer()
            ForEach([Color.yellow, .white], id: \.self) { color in
                Circle()
                    .fill(color.gradient)
                    .frame(width: width * 0.065, height: width * 0.065)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
            }
        }
        .padding(.horizontal, width * 0.05)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.25), in: .rect(cornerRadius: width * 0.04))
    }

    private func lever(_ size: CGSize) -> some View {
        let travel = size.height * 0.28
        let pivot = size.height * 0.55
        let knob = pivot - travel * (1 - 2 * pull)
        return ZStack(alignment: .top) {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.5)], startPoint: .top, endPoint: .bottom))
                .frame(width: size.width * 0.55, height: size.height * 0.2)
                .offset(x: -size.width * 0.25, y: pivot - size.height * 0.1)
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.55)], startPoint: .leading, endPoint: .trailing))
                .frame(width: size.width * 0.18, height: max(abs(knob - pivot), 1))
                .offset(y: min(knob, pivot))
            Circle()
                .fill(RadialGradient(colors: [.white, .red, Color(red: 0.45, green: 0, blue: 0.05)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size.width * 0.4))
                .frame(width: size.width * 0.75, height: size.width * 0.75)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
                .scaleEffect(1 + 0.25 * sin(pull * .pi))
                .offset(y: knob - size.width * 0.375)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !draw.isDrawing, !menus.isEmpty else { return }
                    pull = min(max(value.translation.height / (travel * 2), 0), 1)
                    if pull > 0.7 { draw.charge.begin() } else { _ = draw.charge.consume() }
                }
                .onEnded { _ in
                    let level = draw.charge.consume()
                    if pull > 0.7 {
                        isPulledByHand = true
                        draw.start(strength: 1 + level * 2)
                    }
                    withAnimation(.spring(duration: 0.7, bounce: 0.55)) { pull = 0 }
                }
        )
        .sensoryFeedback(trigger: pull > 0.7) { _, isLatched in isLatched ? .impact(weight: .heavy) : nil }
        .accessibilityLabel("레버")
    }

    private func prepare() async {
        guard strips.isEmpty, !menus.isEmpty else { return }
        let menus = Array(menus.prefix(8))
        for menu in menus {
            let image = await FoodThumbnails.image(of: menu.foods[0].cutout)
            guard !Task.isCancelled else { return }
            images[menu.name] = image
        }
        strips = (0..<3).map { _ in menus.shuffled() }
        if draw.isDrawing { spin() }
    }

    private func drift() async {
        guard drifts else { return }
        var last = Date.now
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(draw.charge.isCharging ? 16 : 33)) }
            catch { return }
            let now = Date.now
            let speed = 1.5 + draw.charge.level * 20
            for reel in offsets.indices {
                offsets[reel] += speed * (1 + Double(reel) * 0.15) * now.timeIntervalSince(last)
                spinning[reel] = speed > 6
            }
            last = now
        }
    }

    private func spin() {
        guard draw.round != playedRound, !strips.isEmpty,
              let winner = strips[0].flatMap(\.foods).randomElement() else { return }
        playedRound = draw.round
        let isJackpot = strips[0].count < 2 || Double.random(in: 0...1) < 0.45
        let decoy = strips[0].filter { $0.name != winner.name }.randomElement()?.name ?? winner.name
        self.isJackpot = false
        if hasLever && !isPulledByHand {
            withAnimation(.easeIn(duration: 0.15)) { pull = 1 } completion: {
                withAnimation(.spring(duration: 0.7, bounce: 0.55)) { pull = 0 }
            }
        }
        isPulledByHand = false
        for reel in strips.indices {
            let strip = strips[reel]
            let count = Double(strip.count)
            let name = reel < 2 || isJackpot ? winner.name : decoy
            let landing = Double(strip.firstIndex { $0.name == name } ?? 0)
            let loops = Double(2 + reel) + (draw.strength - 1) * 4
            let target = ((offsets[reel] + count * loops - landing) / count).rounded(.up) * count + landing
            spinning[reel] = true
            let duration = (1.5 + Double(reel) * 0.6) * (1 + (draw.strength - 1) * 0.2)
            let curve: Animation = draw.strength > 1.05
                ? .timingCurve(0.15, 0.6, 0.25, 1.03, duration: reduceMotion ? 0.4 : duration)
                : .timingCurve(0.35, 0, 0.2, 1.06, duration: reduceMotion ? 0.4 : duration).delay(0.15)
            withAnimation(curve) {
                offsets[reel] = target
            } completion: {
                withAnimation(.easeOut(duration: 0.2)) { spinning[reel] = false }
                stops += 1
                if reel == strips.count - 1 {
                    self.isJackpot = isJackpot
                    draw.finish(with: winner)
                }
            }
        }
    }
}

private struct SlotReel: View, Animatable {
    var offset: Double
    let strip: [Recap.Menu]
    let images: [String: UIImage]

    var animatableData: Double {
        get { offset }
        set { offset = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let height = min(geometry.size.height * 0.8, geometry.size.width * 0.95)
            let base = Int(offset.rounded(.down))
            ZStack {
                ForEach(-2...3, id: \.self) { step in
                    let position = Double(base + step) - offset
                    Group {
                        if !strip.isEmpty, let image = images[strip[((base + step) % strip.count + strip.count) % strip.count].name] {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(systemName: "fork.knife")
                                .font(.title)
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding(geometry.size.width * 0.04)
                    .frame(width: geometry.size.width, height: height)
                    .scaleEffect(y: 1 - min(abs(position), 1) * 0.35)
                    .offset(y: -position * height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(LinearGradient(colors: [Color(white: 0.78), .white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
        .overlay {
            LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .sensoryFeedback(.selection, trigger: Int(offset.rounded()))
    }
}

private struct Marquee: View {
    let isJackpot: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let interval = isJackpot ? 0.1 : 0.45
        TimelineView(.animation(minimumInterval: interval, paused: reduceMotion)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / interval)
            GeometryReader { geometry in
                let bulb = geometry.size.height * 0.22
                HStack(spacing: bulb * 0.7) {
                    bulbs(phase: phase, size: bulb)
                    Text(isJackpot ? "JACKPOT" : "FOOD SLOT")
                        .font(.system(size: geometry.size.height * 0.62, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                        .shadow(color: .orange, radius: isJackpot ? 6 : 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .scaleEffect(isJackpot ? 1.12 : 1)
                        .animation(.spring(duration: 0.4, bounce: 0.6), value: isJackpot)
                    bulbs(phase: phase + 1, size: bulb)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.4), in: .capsule)
            }
        }
    }

    private func bulbs(phase: Int, size: CGFloat) -> some View {
        HStack(spacing: size * 0.6) {
            ForEach(0..<2, id: \.self) { index in
                let isLit = (index + phase) % 2 == 0
                Circle()
                    .fill(isLit ? Color.yellow : Color.yellow.opacity(0.25))
                    .frame(width: size, height: size)
                    .shadow(color: .yellow, radius: isLit ? size * 0.6 : 0)
            }
        }
    }
}
