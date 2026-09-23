@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// 扫描配对二维码的页面。
struct ScannerSheet: View {
    let onScan: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var denied = AVCaptureDevice.authorizationStatus(for: .video) == .denied

    var body: some View {
        NavigationStack {
            Group {
                if denied {
                    ContentUnavailableView(
                        "无法使用相机", systemImage: "camera.fill",
                        description: Text("请在「设置 → NearGuard」中允许访问相机，或直接用系统相机扫描二维码。"))
                } else {
                    QRScannerView(onScan: onScan, onDenied: { denied = true })
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("扫描配对二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

/// AVFoundation 二维码扫描，只识别 `nearguard://` 链接。
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (URL) -> Void
    let onDenied: () -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onScan = onScan
        controller.onDenied = onDenied
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((URL) -> Void)?
    var onDenied: (() -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var delivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                onDenied?()
                return
            }
            configure()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input)
        else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
        let session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let values = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        MainActor.assumeIsolated {
            guard !delivered,
                let url = values.compactMap(URL.init(string:)).first(where: { $0.scheme == "nearguard" })
            else { return }
            delivered = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onScan?(url)
        }
    }
}
