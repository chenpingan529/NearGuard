import Foundation
import AVFoundation

/// 用内置摄像头抓拍一张照片保存为 JPEG。
final class Camera: NSObject, AVCapturePhotoCaptureDelegate {
    private let outputDir: URL
    private let queue = DispatchQueue(label: "probe.camera")
    private var session: AVCaptureSession?
    private var pendingURL: URL?
    private var completion: ((URL?) -> Void)?

    init(outputDir: URL) {
        self.outputDir = outputDir
        super.init()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    var isBusy: Bool { session != nil }

    /// 请求摄像头权限（首次会弹窗）。
    static func requestAccess(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: done(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video, completionHandler: done)
        default: done(false)
        }
    }

    static func authorizationDescription() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "已授权"
        case .notDetermined: return "未请求"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        @unknown default: return "未知"
        }
    }

    /// 抓拍；完成后回调照片路径（失败为 nil）。忙碌时直接回调 nil。
    func capture(tag: String, completion: @escaping (URL?) -> Void) {
        queue.async { [self] in
            guard session == nil else { return completion(nil) }
            // 只用内置摄像头，避免选中「连续互通相机」（iPhone）
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
            guard let device = discovery.devices.first ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                log("摄像头：找不到可用设备或无法打开")
                return completion(nil)
            }
            let session = AVCaptureSession()
            session.sessionPreset = .photo
            let output = AVCapturePhotoOutput()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                log("摄像头：无法配置采集会话")
                return completion(nil)
            }
            session.addInput(input)
            session.addOutput(output)
            session.startRunning()
            self.session = session
            self.completion = completion
            self.pendingURL = outputDir.appendingPathComponent("\(Self.timestamp())-\(tag).jpg")

            // 等待自动曝光稳定，否则第一帧通常是黑的
            queue.asyncAfter(deadline: .now() + 1.5) {
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async { [self] in
            var saved: URL?
            if let error {
                log("摄像头：拍照失败 \(error.localizedDescription)")
            } else if let data = photo.fileDataRepresentation(), let url = pendingURL {
                do {
                    try data.write(to: url)
                    saved = url
                } catch {
                    log("摄像头：保存失败 \(error.localizedDescription)")
                }
            }
            session?.stopRunning()
            session = nil
            let done = completion
            completion = nil
            done?(saved)
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
