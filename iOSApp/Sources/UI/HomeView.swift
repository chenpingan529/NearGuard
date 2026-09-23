import GuardKit
import SwiftUI

/// 首页：配对状态、连接状态、信号强度。
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var scanning = false
    @State private var confirmingUnpair = false

    var body: some View {
        NavigationStack {
            List {
                if let error = model.startupError {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                if let mac = model.pairedMac {
                    pairedSection(mac)
                } else {
                    unpairedSection
                }
                Section("关于") {
                    LabeledContent("版本", value: AppVersion.display)
                    LabeledContent("协议", value: "v\(GuardKitInfo.protocolVersion)")
                    LabeledContent("安全芯片", value: SecureEnclaveSigner.isAvailable ? "可用" : "不可用")
                    LabeledContent("本机指纹", value: model.deviceFingerprint).font(.body.monospaced())
                    NavigationLink("调试日志") { DebugView() }
                }
            }
            .navigationTitle("NearGuard")
            .sheet(isPresented: $scanning) {
                ScannerSheet { url in
                    scanning = false
                    model.handle(url: url)
                }
            }
            .sheet(isPresented: pairingPresented) {
                PairingProgressView()
            }
        }
    }

    private var pairingPresented: Binding<Bool> {
        Binding(get: { model.pendingInvite != nil }, set: { if !$0 { model.cancelPairing() } })
    }

    private var unpairedSection: some View {
        Section {
            Label("尚未配对 Mac", systemImage: "laptopcomputer.trianglebadge.exclamationmark")
            Button("扫描 Mac 上的二维码", systemImage: "qrcode.viewfinder") { scanning = true }
            if let error = model.pairingError {
                Text(error).foregroundStyle(.red)
            }
        } footer: {
            Text("在 Mac 菜单栏点 NearGuard →「配对新 iPhone…」显示二维码。也可以直接用系统相机扫描。")
        }
    }

    private func pairedSection(_ mac: PairedMac) -> some View {
        Group {
            Section("已配对") {
                LabeledContent("Mac", value: mac.name)
                LabeledContent("连接", value: model.linkStatus.label)
                LabeledContent("信号", value: model.lastRSSI.map { "\($0) dBm" } ?? "-")
                LabeledContent("平滑后", value: model.smoothedRSSI.map { String(format: "%.1f dBm", $0) } ?? "-")
                LabeledContent("报告", value: "成功 \(model.reportCount) · 失败 \(model.failedCount)")
                if let at = model.lastReportAt {
                    LabeledContent("最近报告") {
                        Text(at, style: .relative)
                    }
                }
            }
            Section {
                Button("解除配对", role: .destructive) { confirmingUnpair = true }
                    .confirmationDialog("解除与「\(mac.name)」的配对？", isPresented: $confirmingUnpair) {
                        Button("解除配对", role: .destructive) { model.unpair() }
                    } message: {
                        Text("Mac 端也需要在菜单里解除配对。")
                    }
            }
        }
    }
}

/// 扫码后连接 Mac、交换密钥的进度。
struct PairingProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large)
            Text("正在与「\(model.pendingInvite?.macName ?? "Mac")」配对").font(.headline)
            Text(model.linkStatus.label).foregroundStyle(.secondary)
            Text("请让 iPhone 靠近 Mac，并保持 Mac 上的配对窗口打开。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = model.pairingError {
                Text(error).foregroundStyle(.red)
            }
            Button("取消") { model.cancelPairing() }
        }
        .padding(32)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}
