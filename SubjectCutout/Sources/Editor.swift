//
//  Editor.swift
//  SubjectCutout
//
//  Created by YOOJUN PARK on 10/23/26.
//

import SwiftUI
import Vision

@MainActor
public struct CutoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: CutoutSession
    @State private var stroke: [CGPoint] = []
    private let directory: URL
    private let onComplete: ([Cutout]) -> Void

    public init(
        image: UIImage, directory: URL,
        quality: GenerateIterativeSegmentationRequest.QualityLevel = .balanced,
        onComplete: @escaping ([Cutout]) -> Void
    ) {
        self.init(
            session: CutoutSession(image: image, quality: quality), directory: directory,
            onComplete: onComplete
        )
    }

    public init(
        session: CutoutSession, directory: URL,
        onComplete: @escaping ([Cutout]) -> Void
    ) {
        _session = State(initialValue: session)
        self.directory = directory
        self.onComplete = onComplete
    }

    public var body: some View {
        GeometryReader { geometry in
            let layout = ImageLayout(imageSize: session.image.size, availableSize: geometry.size)
            let inputLayout = ImageLayout(imageSize: session.image.size, availableSize: layout.rect.size)
            PhotoCanvas(
                content: AnyView(photo(in: layout)),
                contentSize: layout.rect.size,
                isEnabled: session.isReady && !session.isBusy,
                allowsDrawing: !isEditing,
                onTap: { location in
                    if let point = inputLayout.normalizedPoint(location) { session.tap(point) }
                },
                onStroke: { points, finished in
                    guard let first = points.first, inputLayout.normalizedPoint(first) != nil else {
                        stroke = []
                        return
                    }
                    stroke = points.compactMap { inputLayout.normalizedPoint($0) }
                    if finished {
                        session.scribble(stroke)
                        if !session.isBusy { stroke = [] }
                    }
                }
            )
            .accessibilityLabel("음식 선택 사진")
            .accessibilityHint(instruction)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .background(.background)
        .navigationTitle(isEditing ? "범위 보정" : "음식 선택")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("닫기", systemImage: "xmark") {
                    if isEditing { session.mode = .selecting }
                    else { dismiss() }
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarLeading)
            ToolbarItem(placement: .topBarLeading) {
                Button("실행 취소", systemImage: "arrow.uturn.backward", action: session.undo)
                    .disabled(!session.canUndo)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("완료") {
                    if isEditing { session.mode = .selecting }
                    else { session.save(to: directory, completion: onComplete) }
                }
                .disabled(!session.isReady || session.isSaving || (isEditing && session.isBusy))
            }
        }
        .task { await session.prepare() }
        .onDisappear {
            session.cancel()
            session.mode = .selecting
        }
        .onChange(of: session.isBusy) { _, isBusy in
            if !isBusy { stroke = [] }
        }
        .sensoryFeedback(.selection, trigger: session.changeCount)
        .sensoryFeedback(.error, trigger: session.error != nil) { _, hasError in hasError }
        .alert("작업을 완료하지 못했습니다", isPresented: Binding(
            get: { session.error != nil },
            set: { if !$0 { session.error = nil } }
        )) {
            if !session.isReady { Button("다시 시도") { Task { await session.prepare() } } }
            Button("확인", role: .cancel) { session.error = nil }
        } message: {
            Text(session.error ?? "")
        }
    }

    private var isEditing: Bool {
        if case .editing = session.mode { true } else { false }
    }

    private var instruction: String {
        if isEditing {
            return session.isExcluding ? "추가로 제외할 부분을 탭하세요." : "추가로 포함할 부분을 탭하세요."
        }
        return "\(Self.addInstruction) \(Self.removeInstruction)"
    }

    private static let addInstruction = "분석할 음식을 문지르거나 접시를 탭하여 추가하세요."
    private static let removeInstruction = "선택된 음식을 다시 탭하여 제거하세요."

    private static let outlineColors = [Color.orange, .pink, .purple, .blue, .mint, .yellow, .orange]
        .map { $0.mix(with: .white, by: 0.5) }

    private func photo(in layout: ImageLayout) -> some View {
        ZStack {
            Image(uiImage: session.image).resizable()
            ForEach(session.subjects) { subject in
                let isDimmed = isEditing && session.mode != .editing(subject.id)
                Color.white.opacity(isDimmed ? 0.1 : 0.4)
                    .mask { Image(decorative: subject.mask.overlay, scale: 1).resizable() }
                TimelineView(.animation(paused: isDimmed || reduceMotion)) { context in
                    SelectionOutline(mask: subject.mask)
                        .foregroundStyle(AngularGradient(
                            colors: Self.outlineColors,
                            center: UnitPoint(x: subject.mask.bounds.midX, y: subject.mask.bounds.midY),
                            angle: .degrees(context.date.timeIntervalSinceReferenceDate * 60)
                        ))
                }
                .opacity(isDimmed ? 0.35 : 1)
                .shadow(color: .black.opacity(0.5), radius: 2)
            }
            inputOverlay(in: layout.rect.size)
        }
        .frame(width: layout.rect.width, height: layout.rect.height)
        .clipped()
        .transaction { $0.animation = nil }
    }

    private func inputOverlay(in size: CGSize) -> some View {
        Canvas { context, _ in
            guard let first = stroke.first else { return }
            var path = Path()
            path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
            for point in stroke.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
            }
            context.stroke(path, with: .color(.white.opacity(0.7)), style: StrokeStyle(
                lineWidth: 2 * min(size.width, size.height) / CGFloat(Mask.outlineScale), lineCap: .round, lineJoin: .round
            ))
        }
        .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            ZStack {
                VStack(alignment: .leading, spacing: 8) {
                    Label(Self.addInstruction, systemImage: "hand.draw")
                        .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)))
                    Label(Self.removeInstruction, systemImage: "hand.tap")
                        .symbolEffect(.bounce, options: .repeat(.periodic(delay: 2)))
                }
                .opacity(session.isBusy || isEditing ? 0 : 1)
                Label(instruction, systemImage: "hand.tap")
                    .opacity(isEditing && !session.isBusy ? 1 : 0)
                Label { Text(session.status) } icon: { ProgressView().controlSize(.small) }
                    .opacity(session.isBusy ? 1 : 0)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .symbolEffectsRemoved(reduceMotion)
            .padding(.horizontal, 24)
            .opacity(session.isReady ? 1 : 0)

            Group {
                if !session.isReady, session.isBusy {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(session.status)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassEffect(in: .rect(cornerRadius: 24))
                    .padding(.horizontal, 32)
                } else if isEditing {
                    Picker("범위 보정", selection: $session.isExcluding) {
                        Label("포함", systemImage: "plus.circle").tag(false)
                        Label("제외", systemImage: "minus.circle").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(session.isBusy)
                    .padding(.horizontal, 32)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(session.subjects) { subject in
                                Menu {
                                    Button("범위 보정", systemImage: "slider.horizontal.3") { session.edit(subject.id) }
                                    Button("선택 해제", systemImage: "minus.circle", role: .destructive) {
                                        session.remove(subject.id)
                                    }
                                } label: {
                                    SelectionThumbnail(source: session.image.cgImage, mask: subject.mask)
                                        .frame(width: 56, height: 56)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("선택한 음식")
                                .accessibilityHint("범위 보정 또는 선택 해제")
                                .disabled(session.isBusy)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.center, for: .alignment)
                    .defaultScrollAnchor(.trailing, for: .sizeChanges)
                }
            }
            .frame(height: 68)
        }
        .padding(.vertical, 16)
        .transaction { $0.animation = nil }
    }
}

private struct SelectionOutline: View {
    let mask: Mask
    @State private var outline: CGImage?

    var body: some View {
        Group {
            if let outline {
                Image(decorative: outline, scale: 1).resizable().renderingMode(.template)
            } else { Color.clear }
        }
        .task(id: ObjectIdentifier(mask.image), priority: .utility) {
            outline = nil
            let result = try? await mask.makeOutline()
            if !Task.isCancelled { outline = result }
        }
    }
}

private struct SelectionThumbnail: View {
    let source: CGImage?
    let mask: Mask
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else { Color.clear }
        }
        .task(id: ObjectIdentifier(mask.image), priority: .utility) {
            image = nil
            guard let source else { return }
            let result = try? await mask.makeThumbnail(from: source)
            if !Task.isCancelled { image = result }
        }
    }
}

struct PhotoCanvas: UIViewControllerRepresentable {
    let content: AnyView
    let contentSize: CGSize
    let isEnabled: Bool
    let allowsDrawing: Bool
    let onTap: (CGPoint) -> Void
    let onStroke: ([CGPoint], Bool) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(canvas: self) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        let sizeChanged = controller.canvas.contentSize != contentSize
        controller.canvas = self
        controller.host.rootView = content
        controller.tap.isEnabled = isEnabled
        controller.drawing.isEnabled = isEnabled && allowsDrawing
        if sizeChanged { controller.view.setNeedsLayout() }
    }

    final class Controller: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var canvas: PhotoCanvas
        let scrollView = UIScrollView()
        let host: UIHostingController<AnyView>
        let tap = UITapGestureRecognizer()
        let drawing = UIPanGestureRecognizer()
        private var points: [CGPoint] = []
        private var interrupted = false
        private var viewport = CGSize.zero
        private var photoSize = CGSize.zero

        init(canvas: PhotoCanvas) {
            self.canvas = canvas
            host = UIHostingController(rootView: canvas.content)
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            scrollView.backgroundColor = .clear
            scrollView.delegate = self
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 5
            scrollView.bouncesZoom = true
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(navigate(_:)))
            scrollView.pinchGestureRecognizer?.addTarget(self, action: #selector(navigate(_:)))
            view.addSubview(scrollView)
            addChild(host)
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
            scrollView.addSubview(host.view)
            host.didMove(toParent: self)

            tap.addTarget(self, action: #selector(tapped(_:)))
            tap.delegate = self
            tap.require(toFail: drawing)
            drawing.maximumNumberOfTouches = 1
            drawing.delegate = self
            drawing.addTarget(self, action: #selector(drew(_:)))
            scrollView.addGestureRecognizer(tap)
            scrollView.addGestureRecognizer(drawing)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scrollView.frame = view.bounds
            guard viewport != view.bounds.size || photoSize != canvas.contentSize else { return }
            viewport = view.bounds.size
            photoSize = canvas.contentSize
            scrollView.setZoomScale(1, animated: false)
            host.view.frame = CGRect(origin: .zero, size: canvas.contentSize)
            scrollView.contentSize = canvas.contentSize
            centerPhoto()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }

        private func centerPhoto() {
            let horizontal = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let vertical = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal,
                                                 bottom: vertical, right: horizontal)
            var offset = scrollView.contentOffset
            if scrollView.contentSize.width <= scrollView.bounds.width { offset.x = -horizontal }
            if scrollView.contentSize.height <= scrollView.bounds.height { offset.y = -vertical }
            if offset != scrollView.contentOffset { scrollView.contentOffset = offset }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            canvas.isEnabled && (gestureRecognizer !== drawing || canvas.allowsDrawing)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let navigation = [scrollView.panGestureRecognizer, scrollView.pinchGestureRecognizer]
            return navigation.contains { $0 === gestureRecognizer || $0 === otherGestureRecognizer }
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, !scrollView.isZooming, !scrollView.isDragging else { return }
            canvas.onTap(gesture.location(in: host.view))
        }

        @objc private func navigate(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began {
                interrupted = true
                points = []
                canvas.onStroke([], false)
            }
        }

        @objc private func drew(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                interrupted = gesture.numberOfTouches != 1
                let location = gesture.location(in: host.view)
                let translation = gesture.translation(in: host.view)
                points = [CGPoint(x: location.x - translation.x, y: location.y - translation.y)]
                fallthrough
            case .changed:
                guard !interrupted, gesture.numberOfTouches == 1 else {
                    interrupted = true
                    canvas.onStroke([], false)
                    return
                }
                let point = gesture.location(in: host.view)
                if let last = points.last,
                   hypot(point.x - last.x, point.y - last.y) >= 1 / scrollView.zoomScale {
                    points.append(point)
                }
                canvas.onStroke(points, false)
            case .ended:
                if !interrupted { canvas.onStroke(points, true) }
                points = []
            case .cancelled, .failed:
                points = []
                canvas.onStroke([], false)
            default: break
            }
        }
    }
}

struct ImageLayout {
    let rect: CGRect

    init(imageSize: CGSize, availableSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { rect = .zero; return }
        let scale = min(availableSize.width / imageSize.width, availableSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        rect = CGRect(
            x: (availableSize.width - size.width) / 2,
            y: (availableSize.height - size.height) / 2, width: size.width, height: size.height
        )
    }

    func normalizedPoint(_ point: CGPoint) -> CGPoint? {
        guard !rect.isEmpty, rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }

    func displayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
}
