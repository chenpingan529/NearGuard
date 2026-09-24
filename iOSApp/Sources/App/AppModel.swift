import Foundation
import GuardKit
import Observation
import UIKit

/// iPhone 端的应用状态：把 BLE 中心、配对流程、测距报告连起来，供界面观察。
@MainActor
@Observable
final class AppModel {
    let log = EventLog()
    private(set) var pairedMac: PairedMac?
    private(set) var linkStatus: CentralLink.Status = .idle
    private(set) var lastRSSI: Int?
    private(set) var smoothedRSSI: Double?
    private(set) var lastReportAt: Date?
    private(set) var reportCount = 0
    private(set) var failedCount = 0
    /// 正在配对的二维码邀请。
    private(set) var pendingInvite: PairingInvite?
    private(set) var pairingError: String?
    private(set) var startupError: String?

    private let identity: DeviceIdentity?
    private let macStore = JSONFileStore<PairedMac>(filename: "mac.json")
    private var reporter: PhoneReporter?
    private var link: CentralLink?

    init() {
        do {
            identity = try DeviceIdentity.loadOrCreate()
        } catch {
            identity = nil
            startupError = "无法创建设备密钥：\(error)"
        }
        let mac = macStore.load()
        pairedMac = mac
        log.log("app", "启动 \(AppVersion.display)，\(mac.map { "已配对 \($0.name)" } ?? "未配对")")
        guard let identity else { return }

        if let mac { reporter = PhoneReporter(macID: mac.macID, deviceID: identity.deviceID, signer: identity.signer) }
        // 必须在启动时立即创建：系统因蓝牙事件在后台拉起 App 时，要尽快接回恢复的连接。
        let link = CentralLink(mode: mac.map { .monitoring(knownPeripheral: $0.peripheralID) } ?? .idle)
        link.handler = self
        self.link = link
    }

    var deviceFingerprint: String {
        identity.map { SignatureVerifier.fingerprint(of: $0.signer.publicKey) } ?? "-"
    }

    // MARK: 配对

    /// 处理二维码链接（App 内扫码或系统相机打开的 `nearguard://pair?...`）。
    func handle(url: URL) {
        do {
            let invite = try PairingInvite(url: url, now: Date())
            pendingInvite = invite
            pairingError = nil
            log.log("pairing", "扫到「\(invite.macName)」的配对码，开始连接")
            link?.setMode(.pairing)
        } catch {
            pairingError = Self.describe(error)
            log.log("pairing", "二维码无效：\(error)")
        }
    }

    func cancelPairing() {
        guard pendingInvite != nil else { return }
        pendingInvite = nil
        link?.setMode(pairedMac.map { .monitoring(knownPeripheral: $0.peripheralID) } ?? .idle)
        log.log("pairing", "取消配对")
    }

    func unpair() {
        guard let mac = pairedMac else { return }
        pairedMac = nil
        reporter = nil
        macStore.remove()
        resetReadings()
        link?.setMode(.idle)
        log.log("pairing", "解除配对：\(mac.name)")
    }

    private func resetReadings() {
        lastRSSI = nil
        smoothedRSSI = nil
        lastReportAt = nil
    }

    private static func describe(_ error: Error) -> String {
        switch error as? GuardKitError {
        case .expired: "二维码已过期，请在 Mac 上重新生成"
        case .unsupportedVersion: "两端版本不兼容，请更新 App"
        case .malformed: "不是 NearGuard 配对二维码"
        default: "\(error)"
        }
    }
}

extension AppModel: CentralLinkHandler {
    func centralLinkStatusChanged(_ status: CentralLink.Status) {
        linkStatus = status
        log.log("ble", "状态：\(status.label)")
    }

    func centralLinkShouldAccept(challenge: Data, from peripheral: UUID) -> Bool {
        let expected = pendingInvite?.macID ?? pairedMac?.macID
        guard let expected, let parsed = try? Wire.decode(Challenge.self, from: challenge), parsed.macID == expected
        else { return false }
        // 测距模式下记住最新的外设标识，下次优先直接连接。
        if pendingInvite == nil, var mac = pairedMac, mac.peripheralID != peripheral {
            mac.peripheralID = peripheral
            save(mac)
        }
        return true
    }

    func centralLinkMakePairingRequest() -> Data? {
        guard let invite = pendingInvite, let identity else { return nil }
        do {
            return try Pairing.makeRequest(
                invite: invite, deviceID: identity.deviceID, deviceName: UIDevice.current.name,
                signer: identity.signer, now: Date()
            ).serialized()
        } catch {
            pairingError = "生成配对请求失败：\(error)"
            return nil
        }
    }

    func centralLinkReceivedPairingResult(_ data: Data, peripheral: UUID) {
        guard let invite = pendingInvite, let identity else { return }
        do {
            try Pairing.verifyAccept(SignedEnvelope(serialized: data), invite: invite, deviceID: identity.deviceID)
        } catch {
            pairingError = "Mac 回执校验失败：\(error)"
            log.log("pairing", "回执校验失败：\(error)")
            return
        }
        let mac = PairedMac(
            macID: invite.macID, name: invite.macName, publicKey: invite.macPublicKey, peripheralID: peripheral,
            pairedAt: Date())
        save(mac)
        pairedMac = mac
        pendingInvite = nil
        reporter = PhoneReporter(macID: mac.macID, deviceID: identity.deviceID, signer: identity.signer)
        resetReadings()
        log.log("pairing", "配对成功：\(mac.name)（\(SignatureVerifier.fingerprint(of: mac.publicKey))）")
        link?.completePairing()
    }

    func centralLinkMakeReport(challenge: Data, rssi: Int) -> Data? {
        guard var reporter else { return nil }
        reporter.record(rssi: rssi)
        defer { self.reporter = reporter }
        lastRSSI = rssi
        smoothedRSSI = reporter.smoothedRSSI
        do {
            let parsed = try reporter.parseChallenge(challenge)
            return try reporter.respond(to: parsed, now: Date())
        } catch {
            log.log("report", "无法生成报告：\(error)", rssi: rssi)
            return nil
        }
    }

    func centralLinkReportWritten(success: Bool) {
        if success {
            reportCount += 1
            lastReportAt = Date()
            log.log("report", "已报告", rssi: lastRSSI)
        } else {
            failedCount += 1
        }
    }

    func centralLinkDisconnected() {
        reporter?.reset()
        smoothedRSSI = nil
    }

    func centralLinkLog(_ message: String) {
        log.log("ble", message)
    }

    private func save(_ mac: PairedMac) {
        do {
            try macStore.save(mac)
            pairedMac = mac
        } catch {
            log.log("error", "保存配对信息失败：\(error)")
        }
    }
}

extension CentralLink.Status {
    var label: String {
        switch self {
        case .bluetoothOff: "蓝牙未开启"
        case .unauthorized: "未授权蓝牙"
        case .idle: "空闲"
        case .searching: "搜索 Mac 中"
        case .connecting: "连接中"
        case .verifying: "验证中"
        case .pairing: "配对中"
        case .connected: "已连接"
        }
    }
}
