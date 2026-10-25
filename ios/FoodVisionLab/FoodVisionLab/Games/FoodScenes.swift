//
//  FoodScenes.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

import SpriteKit
import UIKit

class FoodScene: SKScene, SKPhysicsContactDelegate {
    var draw: MenuDraw?
    private(set) var items: [(food: Recap.Food, texture: SKTexture)] = []
    private var impact: UIImpactFeedbackGenerator?
    private var notification: UINotificationFeedbackGenerator?
    private var lastImpact = TimeInterval.zero

    override func sceneDidLoad() {
        scaleMode = .resizeFill
        backgroundColor = .clear
        physicsWorld.contactDelegate = self
    }

    override func didMove(to view: SKView) {
        impact = UIImpactFeedbackGenerator(style: .rigid, view: view)
        notification = UINotificationFeedbackGenerator(view: view)
    }

    func load(_ foods: [Recap.Food]) async {
        for food in foods.prefix(24) {
            guard !Task.isCancelled else { return }
            guard let image = await FoodThumbnails.image(of: food.cutout) else { continue }
            guard !Task.isCancelled else { return }
            items.append((food, SKTexture(image: image)))
        }
        while size == .zero {
            do { try await Task.sleep(for: .milliseconds(16)) }
            catch { return }
        }
        guard !Task.isCancelled else { return }
        didLoad()
    }

    func didLoad() {}

    func play() {}

    func didBegin(_ contact: SKPhysicsContact) {
        let speed = contact.collisionImpulse / max(contact.bodyA.mass, contact.bodyB.mass, 0.001)
        if speed > 1 { tap(min(speed / 5, 0.7)) }
    }

    func sprite(_ texture: SKTexture, length: CGFloat) -> SKSpriteNode {
        let size = texture.size()
        let scale = length / max(size.width, size.height, 1)
        return SKSpriteNode(texture: texture, size: CGSize(width: size.width * scale, height: size.height * scale))
    }

    func tap(_ intensity: CGFloat) {
        let now = CACurrentMediaTime()
        guard now - lastImpact > 0.05 else { return }
        lastImpact = now
        impact?.impactOccurred(intensity: intensity)
    }

    func finish(with food: Recap.Food) {
        notification?.notificationOccurred(.success)
        draw?.finish(with: food)
    }
}

// MARK: - Lottery

final class LottoScene: FoodScene {
    private let drum = SKShapeNode()
    private let stand = SKShapeNode()
    private let base = SKShapeNode()
    private let lights = [SKShapeNode(), SKShapeNode(), SKShapeNode()]
    private let crank = SKShapeNode()
    private var balls: [(food: Recap.Food, node: SKNode)] = []
    private var chosen: SKNode?
    private var isMixing = false

    private var radius: CGFloat { min(size.width * 0.4, size.height * 0.37) }
    private var center: CGPoint { CGPoint(x: size.width / 2, y: radius * 1.55) }

    override func sceneDidLoad() {
        super.sceneDidLoad()
        drum.fillColor = .white.withAlphaComponent(0.12)
        drum.strokeColor = .systemYellow
        drum.lineWidth = 4
        stand.fillColor = UIColor(white: 0.92, alpha: 1)
        stand.strokeColor = .clear
        base.fillColor = .systemPink
        base.strokeColor = .white
        base.lineWidth = 1.5
        crank.fillColor = .systemYellow
        crank.strokeColor = .white
        crank.lineWidth = 1.5
        crank.zPosition = 3
        for (light, color) in zip(lights, [UIColor.systemYellow, .systemMint, .systemOrange]) {
            light.fillColor = color
            light.strokeColor = .white
            light.zPosition = 1
            base.addChild(light)
        }
        for node in [stand, base, drum, crank] { addChild(node) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let radius = radius
        let path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        drum.path = path
        drum.position = center
        drum.physicsBody = SKPhysicsBody(edgeLoopFrom: path)
        stand.path = CGPath(rect: CGRect(x: -radius * 0.2, y: 0, width: radius * 0.4, height: radius * 0.4), transform: nil)
        stand.position = CGPoint(x: center.x, y: radius * 0.3)
        base.path = CGPath(roundedRect: CGRect(x: -radius * 0.9, y: 0, width: radius * 1.8, height: radius * 0.42), cornerWidth: radius * 0.18, cornerHeight: radius * 0.18, transform: nil)
        base.position = CGPoint(x: center.x, y: 0)
        for (index, light) in lights.enumerated() {
            light.path = CGPath(ellipseIn: CGRect(x: -radius * 0.07, y: -radius * 0.07, width: radius * 0.14, height: radius * 0.14), transform: nil)
            light.position = CGPoint(x: radius * (CGFloat(index) - 1) * 0.45, y: radius * 0.21)
        }
        let crankPath = CGMutablePath()
        crankPath.addRoundedRect(in: CGRect(x: -radius * 0.04, y: -radius * 0.04, width: radius * 0.34, height: radius * 0.08), cornerWidth: radius * 0.04, cornerHeight: radius * 0.04)
        crankPath.addEllipse(in: CGRect(x: radius * 0.24, y: -radius * 0.08, width: radius * 0.16, height: radius * 0.16))
        crank.path = crankPath
        crank.position = CGPoint(x: center.x + radius + radius * 0.06, y: center.y)
    }

    override func didLoad() {
        let ballRadius = radius * 0.17
        for (index, item) in items.prefix(14).enumerated() {
            let ball = SKNode()
            let shell = SKShapeNode(circleOfRadius: ballRadius)
            shell.name = "shell"
            shell.fillColor = UIColor(hue: CGFloat(index) / 14, saturation: 0.45, brightness: 1, alpha: 0.9)
            shell.strokeColor = .white
            shell.lineWidth = 1.5
            let shine = SKShapeNode(ellipseOf: CGSize(width: ballRadius * 0.8, height: ballRadius * 0.4))
            shine.fillColor = .white.withAlphaComponent(0.55)
            shine.strokeColor = .clear
            shine.position = CGPoint(x: -ballRadius * 0.3, y: ballRadius * 0.55)
            shine.zRotation = 0.5
            shine.zPosition = 2
            shell.addChild(shine)
            ball.addChild(shell)
            let food = sprite(item.texture, length: ballRadius * 1.5)
            food.zPosition = 1
            ball.addChild(food)
            ball.position = CGPoint(x: center.x + .random(in: -radius...radius) * 0.4, y: center.y + .random(in: -radius...radius) * 0.4)
            let body = SKPhysicsBody(circleOfRadius: ballRadius)
            body.restitution = 0.6
            body.friction = 0.2
            body.contactTestBitMask = 1
            ball.physicsBody = body
            addChild(ball)
            balls.append((item.food, ball))
        }
    }

    override func play() {
        guard !balls.isEmpty else { return }
        if let chosen {
            chosen.childNode(withName: "shell")?.run(.group([.scale(to: 1, duration: 0.2), .fadeIn(withDuration: 0.2)]))
            chosen.run(.scale(to: 1, duration: 0.3)) { chosen.physicsBody?.isDynamic = true }
        }
        chosen = nil
        isMixing = true
        tap(1)
        crank.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 0.5)), withKey: "turn")
        for (index, light) in lights.enumerated() {
            light.run(.repeatForever(.sequence([.wait(forDuration: Double(index) * 0.1), .fadeAlpha(to: 0.3, duration: 0.15), .fadeIn(withDuration: 0.15)])), withKey: "blink")
        }
        run(.sequence([.wait(forDuration: 2.6), .run { [unowned self] in reveal() }]))
    }

    override func update(_ currentTime: TimeInterval) {
        let charge = draw?.charge
        let energy = isMixing ? sqrt(draw?.strength ?? 1) : chosen != nil ? 0 : charge?.isCharging == true ? 0.2 + (charge?.level ?? 0) * 1.1 : 0.12
        guard energy > 0 else { return }
        let speed = radius * 4 * energy
        for (_, ball) in balls {
            guard let body = ball.physicsBody else { continue }
            let dx = ball.position.x - center.x
            let dy = ball.position.y - center.y
            let distance = max(hypot(dx, dy), 1)
            let target = CGVector(
                dx: -dy / distance * speed + .random(in: -speed...speed) * 0.7,
                dy: dx / distance * speed + .random(in: -speed...speed) * 0.7
            )
            body.velocity = CGVector(dx: body.velocity.dx * 0.9 + target.dx * 0.1, dy: body.velocity.dy * 0.9 + target.dy * 0.1)
        }
    }

    override func didBegin(_ contact: SKPhysicsContact) {
        if isMixing { super.didBegin(contact) }
    }

    private func reveal() {
        isMixing = false
        crank.removeAction(forKey: "turn")
        for light in lights {
            light.removeAction(forKey: "blink")
            light.alpha = 1
        }
        guard let (food, ball) = balls.randomElement() else { return }
        chosen = ball
        ball.physicsBody?.isDynamic = false
        ball.zPosition = 2
        let rise = SKAction.group([
            .move(to: center, duration: 0.7),
            .rotate(toAngle: 0, duration: 0.7, shortestUnitArc: true),
            .scale(to: 2.4, duration: 0.7)
        ])
        rise.timingMode = .easeInEaseOut
        ball.run(.sequence([
            rise,
            .run {
                ball.childNode(withName: "shell")?.run(.group([.scale(to: 1.6, duration: 0.25), .fadeOut(withDuration: 0.25)]))
            },
            .scale(to: 2.8, duration: 0.12),
            .scale(to: 2.5, duration: 0.18)
        ])) { [unowned self] in finish(with: food) }
    }
}

final class BlowerScene: FoodScene {
    private let drum = SKShapeNode()
    private let stream = SKSpriteNode()
    private let breeze = SKEmitterNode()
    private let plate = SKShapeNode()
    private var foods: [(food: Recap.Food, node: SKSpriteNode)] = []
    private var held: SKSpriteNode?
    private var chosen: SKSpriteNode?
    private var lastMove = CGVector.zero
    private var isOverPlate = false
    private var power: CGFloat = 1
    private var center = CGPoint.zero
    private var radius: CGFloat = 0
    private var outlet = CGPoint.zero
    private var outletWidth: CGFloat = 0

    private var plateCenter: CGPoint { CGPoint(x: size.width / 2, y: 40) }
    private var home: CGPoint { center }
    private var ventRect: CGRect {
        CGRect(x: outlet.x - outletWidth * 0.8, y: outlet.y - 30, width: outletWidth * 1.6, height: 56)
    }

    override func sceneDidLoad() {
        super.sceneDidLoad()
        drum.fillColor = .white.withAlphaComponent(0.12)
        drum.strokeColor = .systemYellow
        drum.lineWidth = 8
        drum.glowWidth = 4
        drum.zPosition = -1
        stream.zPosition = 1.5
        stream.anchorPoint = CGPoint(x: 0.5, y: 0)
        stream.blendMode = .add
        stream.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.5), .fadeAlpha(to: 0.85, duration: 0.5)])))
        plate.fillColor = .white.withAlphaComponent(0.1)
        plate.strokeColor = .white.withAlphaComponent(0.5)
        plate.lineWidth = 2
        plate.zPosition = 5
        breeze.particleTexture = SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width: 3, height: 22)).image { context in
            let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.5, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 22), options: [])
            }
        })
        breeze.particleColor = .white
        breeze.particleColorBlendFactor = 1
        breeze.particleBlendMode = .add
        breeze.particleAlpha = 0.35
        breeze.particleAlphaSpeed = -0.4
        breeze.particleLifetime = 0.8
        breeze.particleScaleRange = 0.4
        breeze.emissionAngle = .pi / 2
        breeze.emissionAngleRange = .pi / 12
        breeze.particleSpeed = 480
        breeze.particleSpeedRange = 160
        breeze.particleBirthRate = 45
        breeze.zPosition = 2
        for node in [drum, stream, breeze, plate] { addChild(node) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        radius = size.width * 0.8
        outlet = CGPoint(x: size.width / 2, y: 112)
        outletWidth = size.width * 0.12
        center = CGPoint(x: size.width / 2, y: outlet.y - 10 + radius)
        let path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        drum.path = path
        drum.position = center
        drum.physicsBody = SKPhysicsBody(edgeLoopFrom: path)

        let width = outletWidth
        stream.texture = SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width: 120, height: 240)).image { context in
            let clear = UIColor.white.withAlphaComponent(0).cgColor
            guard let across = CGGradient(colorsSpace: nil, colors: [clear, UIColor.white.withAlphaComponent(0.35).cgColor, clear] as CFArray, locations: [0, 0.5, 1]),
                  let along = CGGradient(colorsSpace: nil, colors: [clear, UIColor.white.cgColor] as CFArray, locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(across, start: .zero, end: CGPoint(x: 120, y: 0), options: [])
            context.cgContext.setBlendMode(.destinationIn)
            context.cgContext.drawLinearGradient(along, start: .zero, end: CGPoint(x: 0, y: 240), options: [])
        })
        stream.size = CGSize(width: width * 3, height: min(size.height - outlet.y, 340))
        stream.position = CGPoint(x: outlet.x, y: outlet.y - 10)
        breeze.position = CGPoint(x: outlet.x, y: outlet.y - 6)
        breeze.particlePositionRange = CGVector(dx: width * 0.8, dy: 0)
        plate.path = CGPath(ellipseIn: CGRect(x: -size.width * 0.18, y: -13, width: size.width * 0.36, height: 26), transform: nil)
        plate.position = plateCenter
        physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: -100, width: size.width, height: size.height + 100))
        for (_, node) in foods where node !== chosen {
            fit(node)
            node.position = CGPoint(x: home.x + .random(in: -1...1) * radius * 0.4, y: home.y + .random(in: -1...1) * radius * 0.3)
        }
    }

    override func didLoad() {
        for item in items.prefix(14) {
            let node = SKSpriteNode(texture: item.texture)
            node.zPosition = 3
            fit(node)
            node.position = CGPoint(x: home.x + .random(in: -1...1) * size.width * 0.3, y: home.y + .random(in: -1...1) * 60)
            addChild(node)
            foods.append((item.food, node))
        }
    }

    override func play() {
        if let chosen {
            release(chosen)
            self.chosen = nil
        }
        highlightPlate(false)
        power = 1.3 + 0.3 * (draw?.strength ?? 1)
        breeze.particleBirthRate = 240
        stream.run(.scale(to: 1.3, duration: 0.3))
        let rumble = SKAction.sequence((0..<8).map { step in
            .sequence([.run { [unowned self] in tap(0.3 + Double(step) * 0.08) }, .wait(forDuration: 0.05)])
        })
        run(.sequence([
            rumble,
            .wait(forDuration: 2.2),
            .run { [unowned self] in
                power = 1
                breeze.particleBirthRate = 45
                stream.run(.scale(to: 1, duration: 0.6))
            }
        ]))
    }

    override func update(_ currentTime: TimeInterval) {
        if let charge = draw?.charge, charge.isCharging {
            power = 1 + charge.level * 0.7
            breeze.particleBirthRate = 45 + 200 * charge.level
            stream.setScale(1 + charge.level * 0.3)
        }
        let gravity = abs(physicsWorld.gravity.dy) * 150
        let visible = size.height - outlet.y
        for (_, node) in foods where node !== held && node !== chosen {
            guard let body = node.physicsBody, ventRect.contains(node.position), body.velocity.dy < 200 else { continue }
            let height = min(visible * .random(in: 0.55...1.05) * power, radius * 1.6)
            body.velocity = CGVector(dx: .random(in: -1...1) * size.width * 0.5, dy: sqrt(2 * gravity * height))
            body.angularVelocity = .random(in: -9...9)
            tap(0.25 * power)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        held = foods
            .filter { $0.node !== chosen }
            .min { hypot($0.node.position.x - point.x, $0.node.position.y - point.y) < hypot($1.node.position.x - point.x, $1.node.position.y - point.y) }
            .flatMap { hypot($0.node.position.x - point.x, $0.node.position.y - point.y) < size.width * 0.12 ? $0.node : nil }
        guard let held else { return }
        held.physicsBody?.isDynamic = false
        held.zPosition = 6
        held.run(.scale(to: 1.15, duration: 0.1))
        tap(0.5)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let held, let touch = touches.first else { return }
        let point = touch.location(in: self)
        let previous = touch.previousLocation(in: self)
        lastMove = CGVector(dx: point.x - previous.x, dy: point.y - previous.y)
        held.position = point
        let isOver = abs(point.x - plateCenter.x) < size.width * 0.24 && point.y < plateCenter.y + 64
        if isOver != isOverPlate {
            highlightPlate(isOver)
            if isOver { tap(0.7) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let held else { return }
        self.held = nil
        if isOverPlate {
            serve(held)
        } else if hypot(held.position.x - center.x, held.position.y - center.y) > radius - 30 {
            release(held)
        } else {
            held.zPosition = 3
            held.run(.scale(to: 1, duration: 0.1))
            held.physicsBody?.isDynamic = true
            held.physicsBody?.velocity = CGVector(dx: lastMove.dx * 40, dy: lastMove.dy * 40)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let held else { return }
        self.held = nil
        highlightPlate(false)
        release(held)
    }

    private func release(_ node: SKSpriteNode) {
        node.run(.group([.move(to: home, duration: 0.3), .scale(to: 1, duration: 0.3)])) {
            node.zPosition = 3
            node.physicsBody?.isDynamic = true
        }
    }

    private func serve(_ node: SKSpriteNode) {
        guard let food = foods.first(where: { $0.node === node })?.food else { return }
        chosen = node
        let settle = SKAction.group([
            .move(to: CGPoint(x: plateCenter.x, y: plateCenter.y + 22), duration: 0.3),
            .rotate(toAngle: 0, duration: 0.3, shortestUnitArc: true),
            .scale(to: 1.4, duration: 0.3)
        ])
        settle.timingMode = .easeOut
        node.run(settle) { [unowned self] in finish(with: food) }
    }

    private func fit(_ node: SKSpriteNode) {
        guard let texture = node.texture else { return }
        let scale = size.width * 0.15 / max(texture.size().width, texture.size().height, 1)
        node.size = CGSize(width: texture.size().width * scale, height: texture.size().height * scale)
        let body = SKPhysicsBody(circleOfRadius: size.width * 0.06)
        body.restitution = 0.35
        body.friction = 0.05
        body.contactTestBitMask = 1
        body.usesPreciseCollisionDetection = true
        body.isDynamic = node.physicsBody?.isDynamic ?? true
        node.physicsBody = body
    }

    private func highlightPlate(_ isOver: Bool) {
        isOverPlate = isOver
        plate.strokeColor = isOver ? .systemYellow : .white.withAlphaComponent(0.5)
        plate.glowWidth = isOver ? 8 : 0
    }
}

// MARK: - Crocodile

final class CrocScene: FoodScene {
    private let isExpanded: Bool
    private let croc = SKNode()
    private let upperJaw = SKNode()
    private let lowerJaw = SKNode()
    private let mouth = SKShapeNode()
    private let toast = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private var ball: (food: Recap.Food, node: SKNode)?
    private var flicked: CGPoint?
    private var isOpen = false
    private var headWidth: CGFloat = 0
    private var openHeight: CGFloat = 0

    private var mouthCenter: CGPoint { croc.position }
    private var ballHome: CGPoint { CGPoint(x: size.width / 2, y: size.height * (isExpanded ? 0.16 : 0.15)) }
    private var ballRadius: CGFloat { size.width * (isExpanded ? 0.09 : 0.085) }

    init(isExpanded: Bool) {
        self.isExpanded = isExpanded
        super.init(size: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sceneDidLoad() {
        super.sceneDidLoad()
        mouth.fillColor = UIColor(red: 0.45, green: 0.08, blue: 0.14, alpha: 1)
        mouth.strokeColor = .clear
        mouth.yScale = 0.05
        toast.fontSize = 22
        toast.fontColor = .white
        toast.alpha = 0
        toast.zPosition = 10
        for node in [mouth, lowerJaw, upperJaw] { croc.addChild(node) }
        for node in [croc, toast] { addChild(node) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        headWidth = size.width * (isExpanded ? 0.62 : 0.44)
        openHeight = headWidth * 0.3
        croc.position = CGPoint(x: size.width / 2, y: size.height * (isExpanded ? 0.62 : 0.5))
        toast.position = CGPoint(x: size.width / 2, y: size.height - (isExpanded ? 130 : 14))
        toast.fontSize = isExpanded ? 26 : 13
        drawCroc()
        ball?.node.position = ballHome
    }

    override func didLoad() {
        spawnBall()
        scheduleMouth()
    }

    override func play() {
        draw?.release()
        let error = CGFloat.random(in: -1...1) * headWidth * 0.25 / CGFloat(draw?.strength ?? 1)
        throwBall(to: CGPoint(x: mouthCenter.x + error, y: mouthCenter.y), speed: CGFloat(draw?.strength ?? 1))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self), let ball else { return }
        flicked = hypot(point.x - ball.node.position.x, point.y - ball.node.position.y) < ballRadius * 2.2 ? point : nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let start = flicked, let point = touches.first?.location(in: self) else { return }
        flicked = nil
        let dx = point.x - start.x
        let dy = point.y - start.y
        guard dy > 30 else { return }
        let x = ballHome.x + dx / dy * (mouthCenter.y - ballHome.y)
        throwBall(to: CGPoint(x: x, y: mouthCenter.y), speed: min(max(dy / 120, 0.8), 2))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        flicked = nil
    }

    private func drawCroc() {
        let width = headWidth
        let green = UIColor(red: 0.3, green: 0.68, blue: 0.36, alpha: 1)
        let darkGreen = UIColor(red: 0.2, green: 0.5, blue: 0.27, alpha: 1)
        mouth.path = CGPath(roundedRect: CGRect(x: -width * 0.42, y: -openHeight / 2, width: width * 0.84, height: openHeight), cornerWidth: openHeight * 0.4, cornerHeight: openHeight * 0.4, transform: nil)
        mouth.removeAllChildren()
        let tongue = SKShapeNode(ellipseOf: CGSize(width: width * 0.4, height: openHeight * 0.45))
        tongue.fillColor = UIColor(red: 0.93, green: 0.42, blue: 0.5, alpha: 1)
        tongue.strokeColor = .clear
        tongue.position = CGPoint(x: 0, y: -openHeight * 0.2)
        mouth.addChild(tongue)

        upperJaw.removeAllChildren()
        let snout = SKShapeNode(rect: CGRect(x: -width / 2, y: 0, width: width, height: width * 0.26), cornerRadius: width * 0.12)
        snout.fillColor = green
        snout.strokeColor = darkGreen
        snout.lineWidth = 2
        upperJaw.addChild(snout)
        for side in [-1.0, 1.0] {
            let bump = SKShapeNode(circleOfRadius: width * 0.12)
            bump.fillColor = green
            bump.strokeColor = darkGreen
            bump.lineWidth = 2
            bump.position = CGPoint(x: side * width * 0.3, y: width * 0.27)
            let eye = SKShapeNode(circleOfRadius: width * 0.075)
            eye.fillColor = .white
            eye.strokeColor = .clear
            let pupil = SKShapeNode(ellipseOf: CGSize(width: width * 0.04, height: width * 0.07))
            pupil.fillColor = .black
            pupil.strokeColor = .clear
            eye.addChild(pupil)
            bump.addChild(eye)
            upperJaw.addChild(bump)
            let nostril = SKShapeNode(ellipseOf: CGSize(width: width * 0.04, height: width * 0.025))
            nostril.fillColor = darkGreen
            nostril.strokeColor = .clear
            nostril.position = CGPoint(x: side * width * 0.08, y: width * 0.19)
            upperJaw.addChild(nostril)
        }
        upperJaw.addChild(teeth(width: width, pointingDown: true))

        lowerJaw.removeAllChildren()
        let chin = SKShapeNode(rect: CGRect(x: -width * 0.46, y: -width * 0.16, width: width * 0.92, height: width * 0.16), cornerRadius: width * 0.08)
        chin.fillColor = green
        chin.strokeColor = darkGreen
        chin.lineWidth = 2
        lowerJaw.addChild(chin)
        lowerJaw.addChild(teeth(width: width * 0.92, pointingDown: false))
        setJaws(open: isOpen ? 1 : 0)
    }

    private func teeth(width: CGFloat, pointingDown: Bool) -> SKNode {
        let path = CGMutablePath()
        let size = width / 10
        for index in 0..<8 {
            let x = -width * 0.4 + CGFloat(index) * width * 0.8 / 7
            path.move(to: CGPoint(x: x - size / 2, y: 0))
            path.addLine(to: CGPoint(x: x, y: pointingDown ? -size * 0.8 : size * 0.8))
            path.addLine(to: CGPoint(x: x + size / 2, y: 0))
            path.closeSubpath()
        }
        let node = SKShapeNode(path: path)
        node.fillColor = .white
        node.strokeColor = .clear
        return node
    }

    private func setJaws(open: CGFloat) {
        upperJaw.position = CGPoint(x: 0, y: openHeight * 0.5 * open)
        lowerJaw.position = CGPoint(x: 0, y: -openHeight * 0.5 * open)
        mouth.yScale = max(open, 0.05)
    }

    private func animateJaws(to open: CGFloat, duration: TimeInterval) {
        let from = mouth.yScale <= 0.05 ? 0 : mouth.yScale
        croc.run(.customAction(withDuration: duration) { [unowned self] _, time in
            let progress = duration > 0 ? time / CGFloat(duration) : 1
            setJaws(open: from + (open - from) * progress)
        }, withKey: "jaws")
    }

    private func scheduleMouth() {
        let isFake = Double.random(in: 0...1) < 0.3
        croc.run(.sequence([
            .wait(forDuration: .random(in: 0.3...2.4)),
            .run { [unowned self] in
                isOpen = !isFake
                animateJaws(to: isFake ? 0.35 : 1, duration: 0.12)
            },
            .wait(forDuration: isFake ? .random(in: 0.15...0.3) : .random(in: 0.3...1.1)),
            .run { [unowned self] in
                isOpen = false
                animateJaws(to: 0, duration: 0.1)
                scheduleMouth()
            }
        ]), withKey: "mouth")
    }

    private func spawnBall() {
        guard let item = items.randomElement() else { return }
        let node = SKNode()
        let shell = SKShapeNode(circleOfRadius: ballRadius)
        shell.fillColor = UIColor(hue: .random(in: 0...1), saturation: 0.45, brightness: 1, alpha: 0.95)
        shell.strokeColor = .white
        shell.lineWidth = 2
        node.addChild(shell)
        let food = sprite(item.texture, length: ballRadius * 1.5)
        food.zPosition = 1
        node.addChild(food)
        let shine = SKShapeNode(ellipseOf: CGSize(width: ballRadius * 0.8, height: ballRadius * 0.4))
        shine.fillColor = .white.withAlphaComponent(0.5)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -ballRadius * 0.3, y: ballRadius * 0.55)
        shine.zRotation = 0.5
        shine.zPosition = 2
        node.addChild(shine)
        node.position = ballHome
        node.zPosition = 5
        node.setScale(0.2)
        node.run(.scale(to: 1, duration: 0.18))
        addChild(node)
        ball = (item.food, node)
    }

    private func throwBall(to target: CGPoint, speed: CGFloat) {
        guard let (food, node) = ball else { return }
        ball = nil
        tap(0.5)
        spawnBall()
        let start = node.position
        let duration = 0.55 / Double(speed)
        let arc = (target.y - start.y) * 0.35
        let flight = SKAction.customAction(withDuration: duration) { node, time in
            let t = time / CGFloat(duration)
            node.position = CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t + arc * 4 * t * (1 - t))
            node.setScale(1 - 0.45 * t)
            node.zRotation = -t * 3
        }
        node.run(flight) { [unowned self] in land(node, food: food) }
    }

    private func land(_ node: SKNode, food: Recap.Food) {
        if isOpen && abs(node.position.x - mouthCenter.x) < headWidth * 0.38 {
            node.zPosition = 0.5
            node.run(.group([.move(to: mouthCenter, duration: 0.1), .scale(to: 0.1, duration: 0.12)])) { node.removeFromParent() }
            isOpen = false
            croc.removeAction(forKey: "mouth")
            animateJaws(to: 0, duration: 0.08)
            croc.run(.sequence([.scaleX(to: 1.08, y: 0.92, duration: 0.08), .scale(to: 1, duration: 0.18)])) { [unowned self] in scheduleMouth() }
            show("냠! \(food.name)")
            finish(with: food)
        } else {
            let side: CGFloat = node.position.x < mouthCenter.x ? -1 : 1
            node.zPosition = 6
            node.run(.sequence([
                .group([
                    .moveBy(x: side * size.width * 0.25, y: -size.height * 0.35, duration: 0.5),
                    .rotate(byAngle: side * 4, duration: 0.5),
                    .fadeOut(withDuration: 0.5)
                ]),
                .removeFromParent()
            ]))
            tap(0.9)
            show(isOpen ? "빗나갔어요" : "앗, 입을 닫았어요")
        }
    }

    private func show(_ text: String) {
        toast.text = text
        toast.removeAllActions()
        toast.setScale(0.8)
        toast.run(.sequence([
            .group([.fadeIn(withDuration: 0.12), .scale(to: 1, duration: 0.12)]),
            .wait(forDuration: 0.8),
            .fadeOut(withDuration: 0.25)
        ]))
    }
}
