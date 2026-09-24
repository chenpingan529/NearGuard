import CoreBluetooth
import Foundation
import GuardKit
import Observation

/// Mac 端的应用状态：把 BLE 外设、配对会话、测距会话连起来，供界面观察。
@MainActor
@Observable
final class AppModel {
    let log = EventLog()
    private(set) var devices: [PairedDevice] = []
    private(set) var proximity: ProximityState = .unknown
    private(set) var lastRSSI: Int?
    private(set) var lastReportAt: Date?
    private(set) var reportCount = 0
    private(set) var rejectedCount = 0
    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var subscriberCount = 0
    private(set) var pairingInvite: PairingInvite?
    private(set) var pairedJustNow: PairedDevice?
    private(set) var startupError: String?

    private let identity: MacIdentity?
    private let deviceStore = JSONFileStore<[PairedDevice]>(filename: "devices.json")
    private var session: MacLinkSession
    private var pairing = PairingSession()
    private var link: PeripheralLink?
    private var tickTimer: Timer?

    init() {
        do {
            identity = try MacIdentity.loadOrCreate()
        } catch {
            identity = nil
            startupError = "无法读取钥匙串：\(error)"
        }
        let devices = deviceStore.load() ?? []
        self.devices = devices
        session = MacLinkSession(macID: identity?.macID ?? UUID(), devices: devices)
        log.log("app", "启动 \(AppVersion.display)，已配对 \(devices.count) 台设备")
        guard identity != nil else { return }

        let link = PeripheralLink()
        link.handler = self
        self.link = link
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    var macFingerprint: String {
        identity.map { SignatureVerifier.fingerprint(of: $0.signer.publicKey) } ?? "-"
    }

    // MARK: 配对

    func startPairing() {
        guard let identity else { return }
        pairedJustNow = nil
        pairingInvite = pairing.start(
            macID: identity.macID, macName: MacIdentity.computerName, macPublicKey: identity.signer.publicKey,
            now: Date())
        log.log("pairing", "生成配对二维码")
    }

    func cancelPairing() {
        pairing.cancel()
        pairingInvite = nil
    }

    func unpair(_ device: PairedDevice) {
        devices.removeAll { $0.deviceID == device.deviceID }
        saveDevices()
        log.log("pairing", "解除配对：\(device.name)")
    }

    private func saveDevices() {
        do {
            try deviceStore.save(devices)
        } catch {
            log.log("error", "保存设备列表失败：\(error)")
        }
        session.setDevices(devices)
        if devices.isEmpty {
            proximity = .unknown
            lastRSSI = nil
            lastReportAt = nil
        }
    }

    // MARK: 定时

    private func tick() {
        if pairingInvite != nil, !pairing.isActive(now: Date()) {
            pairingInvite = nil
            log.log("pairing", "配对二维码已过期")
        }
        if let change = session.tick(now: Date()) {
            apply(change, reason: "超过 \(Int(session.classifier.config.absentTimeout)) 秒没有报告")
        }
    }

    private func apply(_ change: ProximityState, reason: String) {
        proximity = change
        log.log("proximity", "距离状态 → \(change.label)（\(reason)）", rssi: lastRSSI, state: change.rawValue)
    }
}

extension AppModel: PeripheralLinkHandler {
    func peripheralLinkStateChanged(_ state: CBManagerState) {
        bluetoothState = state
        log.log("ble", "蓝牙状态：\(state.label)")
    }

    /// 未配对时也要能发挑战：iPhone 配对前先读挑战里的 macID，确认连的是二维码上那台 Mac。
    func peripheralLinkMakeChallenge() -> Data? {
        try? session.nextChallenge(now: Date())
    }

    func peripheralLinkReceivedReport(_ data: Data) -> Bool {
        do {
            let (report, change) = try session.receiveReport(data, now: Date())
            reportCount += 1
            lastRSSI = report.rssi
            lastReportAt = Date()
            log.log("report", "报告", rssi: report.rssi, state: session.proximity.rawValue)
            if let change { apply(change, reason: "信号 \(report.rssi) dBm") }
            return true
        } catch {
            rejectedCount += 1
            log.log("report", "拒绝报告：\(error)")
            return false
        }
    }

    func peripheralLinkReceivedPairingRequest(_ data: Data) -> Data? {
        guard let identity else { return nil }
        do {
            let now = Date()
            let device = try pairing.complete(try SignedEnvelope(serialized: data), now: now)
            let accept = try Pairing.makeAccept(
                device: device, macID: identity.macID, signer: identity.signer, now: now)
            devices.removeAll { $0.deviceID == device.deviceID }
            devices.append(device)
            saveDevices()
            pairingInvite = nil
            pairedJustNow = device
            log.log("pairing", "配对成功：\(device.name)（\(SignatureVerifier.fingerprint(of: device.publicKey))）")
            return accept.serialized()
        } catch {
            log.log("pairing", "拒绝配对请求：\(error)")
            return nil
        }
    }

    func peripheralLinkSubscribersChanged(count: Int, lost: Bool) {
        subscriberCount = count
        log.log("ble", "订阅数：\(count)")
        if lost, count == 0, let change = session.linkLost() {
            apply(change, reason: "iPhone 取消订阅")
        }
    }

    func peripheralLinkLog(_ message: String) {
        log.log("ble", message)
    }
}

extension ProximityState {
    var label: String {
        switch self {
        case .unknown: "未知"
        case .near: "靠近"
        case .far: "远离"
        case .absent: "不在"
        }
    }
}

extension CBManagerState {
    var label: String {
        switch self {
        case .poweredOn: "已开启"
        case .poweredOff: "已关闭"
        case .unauthorized: "未授权"
        case .unsupported: "不支持"
        case .resetting: "重置中"
        case .unknown: "未知"
        @unknown default: "未知"
        }
    }
}
