//
//  CameraView.swift
//  FoodVisionLab
//
//  Created by YOOJUN PARK on 10/25/26.
//

@preconcurrency import AVFoundation
import SwiftUI

struct CameraView: View {
    let onCapture: (Data) -> Void
    @State private var camera = Camera()

    var body: some View {
        Group {
            if camera.isAvailable {
                CameraPreview(session: camera.session)
                    .opacity(camera.isRunning ? 1 : 0)
                    .animation(.easeIn(duration: 0.25), value: camera.isRunning)
                    .background(.black)
                    .overlay(alignment: .bottom) {
                        Button {
                            Task { if let data = await camera.capturePhoto() { onCapture(data) } }
                        } label: {
                            Circle()
                                .fill(.white)
                                .frame(width: 64, height: 64)
                                .padding(6)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .accessibilityLabel("사진 촬영")
                        .disabled(!camera.isRunning)
                        .padding(.bottom, 24)
                    }
            } else {
                ContentUnavailableView(
                    "카메라를 사용할 수 없습니다", systemImage: "camera",
                    description: Text("설정에서 카메라 접근을 허용하거나 사진을 선택하세요.")
                )
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}

@Observable
private final class Camera: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private(set) var isAvailable = true
    private(set) var isRunning = false
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.YOOJUN.FoodVisionLab.camera")
    private var isActive = false
    private var continuation: CheckedContinuation<Data?, Never>?

    func start() async {
        isActive = true
        let isAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        guard isActive else { return }
        guard isAuthorized, configure() else {
            isAvailable = false
            return
        }
        let session = session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume()
            }
        }
        isRunning = isActive && session.isRunning
    }

    func stop() {
        isActive = false
        isRunning = false
        let session = session
        sessionQueue.async { session.stopRunning() }
    }

    private func configure() -> Bool {
        guard session.inputs.isEmpty else { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.sessionPreset = .photo
        session.addInput(input)
        session.addOutput(output)
        return true
    }

    func capturePhoto() async -> Data? {
        guard isRunning, continuation == nil else { return nil }
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            continuation?.resume(returning: isActive ? data : nil)
            continuation = nil
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
