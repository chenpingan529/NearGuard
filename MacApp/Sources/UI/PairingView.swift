import CoreImage.CIFilterBuiltins
import GuardKit
import SwiftUI

/// 配对窗口：显示二维码和倒计时，iPhone 扫码后显示结果。
struct PairingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            if let device = model.pairedJustNow {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("已与「\(device.name)」配对").font(.title2)
                Text("公钥指纹 \(SignatureVerifier.fingerprint(of: device.publicKey))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else if let invite = model.pairingInvite, let url = try? invite.url() {
                Text("用 iPhone 相机或 NearGuard App 扫描").font(.headline)
                QRCodeImage(text: url.absoluteString)
                    .frame(width: 260, height: 260)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(invite.expiresAt.timeIntervalSince(context.date)))
                    Text("\(remaining / 60):\(String(format: "%02d", remaining % 60)) 后失效 · 只能使用一次")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Mac 指纹 \(model.macFingerprint)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text("二维码已失效").font(.headline)
            }
            Button(model.pairedJustNow == nil ? "重新生成" : "再配对一台") { model.startPairing() }
        }
        .padding(28)
        .frame(width: 340)
        .onAppear { model.startPairing() }
        .onDisappear { model.cancelPairing() }
    }
}

/// 用 CoreImage 生成二维码。
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Text("二维码生成失败")
        }
    }

    static func render(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
            let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
