import CoreBluetooth
import Foundation
import GuardKit

/// CentralLink 的事件回调。判断逻辑在 GuardKit（PhoneReporter / Pairing）和 AppModel 里。
@MainActor
protocol CentralLinkHandler: AnyObject {
    func centralLinkStatusChanged(_ status: CentralLink.Status)
    /// 连接上某台 NearGuard Mac 并读到挑战后调用：返回 true 继续，false 断开并忽略这台设备。
    func centralLinkShouldAccept(challenge: Data, from peripheral: UUID) -> Bool
    /// 配对模式：返回要写入的配对请求。
    func centralLinkMakePairingRequest() -> Data?
    /// 配对模式：收到 Mac 的配对回执。
    func centralLinkReceivedPairingResult(_ data: Data, peripheral: UUID)
    /// 测距模式：收到挑战和信号强度，返回要写入的报告（nil 表示本轮不报告）。
    func centralLinkMakeReport(challenge: Data, rssi: Int) -> Data?
    func centralLinkReportWritten(success: Bool)
    func centralLinkDisconnected()
    func centralLinkLog(_ message: String)
}

/// iPhone 端 BLE 中心：发现并连接 Mac，完成配对，之后订阅挑战并回复签名报告。
///
/// 后台策略（见 docs/decisions/0001-iphone-as-central.md）：
/// - 使用状态恢复，App 被系统终止后，蓝牙事件会重新拉起 App；
/// - 断开后立即发起不超时的连接请求，手机回到 Mac 附近时由系统完成连接并唤醒 App；
/// - 同时按服务 UUID 扫描，应对 Mac 蓝牙地址轮换导致旧标识失效。
@MainActor
final class CentralLink: NSObject {
    enum Mode: Equatable {
        case idle
        case pairing
        case monitoring(knownPeripheral: UUID?)
    }

    enum Status: Equatable {
        case bluetoothOff
        case unauthorized
        case idle
        case searching
        case connecting
        case verifying
        case pairing
        case connected
    }

    weak var handler: CentralLinkHandler?
    private(set) var status: Status = .idle {
        didSet { if status != oldValue { handler?.centralLinkStatusChanged(status) } }
    }
    private var mode: Mode = .idle
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var verified = false
    private var pendingChallenge: Data?
    /// 本次会话中确认不是目标的外设（例如附近另一台 Mac），不再连接。
    private var ignored: Set<UUID> = []

    private static let restoreID = "com.nearguard.central"
    private static let serviceUUID = CBUUID(nsuuid: BLEIdentifiers.service)
    private static let characteristicUUIDs = [
        BLEIdentifiers.challenge, BLEIdentifiers.report, BLEIdentifiers.pairingRequest, BLEIdentifiers.pairingResult,
    ].map { CBUUID(nsuuid: $0) }

    /// 初始模式直接传入，不走 setMode（避免在系统恢复连接之前把它断开）。
    init(mode: Mode) {
        self.mode = mode
        super.init()
        manager = CBCentralManager(
            delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID])
    }

    /// 切换模式。配对和测距互斥，切换时断开当前连接重新开始。
    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        ignored.removeAll()
        disconnect()
        proceed()
    }

    /// 配对成功：在当前连接上直接切换到测距模式。
    func completePairing() {
        guard let peripheral else { return }
        mode = .monitoring(knownPeripheral: peripheral.identifier)
        startSession(on: peripheral)
    }

    private func disconnect() {
        manager.stopScan()
        if let peripheral { manager.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        characteristics.removeAll()
        verified = false
        pendingChallenge = nil
    }

    /// 根据当前模式决定下一步：复用已有连接 → 连接已知外设 → 扫描。
    private func proceed() {
        guard manager.state == .poweredOn else { return }
        if mode == .idle {
            status = .idle
            return
        }
        if let peripheral {
            if peripheral.state == .connected {
                discover(peripheral)
            } else {
                manager.connect(peripheral)
                status = .connecting
            }
            return
        }
        if let connected = manager.retrieveConnectedPeripherals(withServices: [Self.serviceUUID])
            .first(where: { !ignored.contains($0.identifier) })
        {
            connect(connected)
            return
        }
        if case .monitoring(let known?) = mode, let known = manager.retrievePeripherals(withIdentifiers: [known]).first
        {
            connect(known)
        }
        manager.scanForPeripherals(withServices: [Self.serviceUUID])
        if peripheral == nil { status = .searching }
    }

    private func connect(_ target: CBPeripheral) {
        peripheral = target
        target.delegate = self
        manager.connect(target)
        status = .connecting
    }

    private func discover(_ peripheral: CBPeripheral) {
        status = .verifying
        peripheral.discoverServices([Self.serviceUUID])
    }

    private func reject(_ peripheral: CBPeripheral, reason: String) {
        handler?.centralLinkLog("忽略设备 \(peripheral.identifier.uuidString.prefix(8))：\(reason)")
        ignored.insert(peripheral.identifier)
        disconnect()
        proceed()
    }

    private func characteristic(_ uuid: UUID) -> CBCharacteristic? {
        characteristics[CBUUID(nsuuid: uuid)]
    }

    /// 已确认是目标 Mac：配对模式写入请求，测距模式订阅挑战。
    private func startSession(on peripheral: CBPeripheral) {
        verified = true
        switch mode {
        case .pairing:
            guard let request = handler?.centralLinkMakePairingRequest(),
                let target = characteristic(BLEIdentifiers.pairingRequest)
            else { return }
            status = .pairing
            peripheral.writeValue(request, for: target, type: .withResponse)
        case .monitoring:
            guard let challenge = characteristic(BLEIdentifiers.challenge) else { return }
            manager.stopScan()
            status = .connected
            peripheral.setNotifyValue(true, for: challenge)
        case .idle:
            break
        }
    }
}

extension CentralLink: @preconcurrency CBCentralManagerDelegate {
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        handler?.centralLinkLog("系统恢复蓝牙状态，外设 \(restored.count) 个")
        if let first = restored.first {
            peripheral = first
            first.delegate = self
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            proceed()
        case .unauthorized:
            status = .unauthorized
        default:
            status = .bluetoothOff
            characteristics.removeAll()
            verified = false
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !ignored.contains(peripheral.identifier) else { return }
        if let current = self.peripheral {
            // 已连接，或正在连接的就是这台：不用处理。
            if current.state == .connected || current.identifier == peripheral.identifier { return }
            // 正在等一个旧标识的连接（Mac 蓝牙地址可能已轮换）：改连正在广播的这台，验证失败会被忽略并重试。
            manager.cancelPeripheralConnection(current)
            self.peripheral = nil
        }
        handler?.centralLinkLog("发现 Mac，信号 \(RSSI) dBm")
        connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        handler?.centralLinkLog("已连接")
        discover(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        handler?.centralLinkLog("连接失败：\(error?.localizedDescription ?? "未知")")
        self.peripheral = nil
        proceed()
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        guard peripheral == self.peripheral else { return }
        handler?.centralLinkLog("连接断开\(error.map { "：\($0.localizedDescription)" } ?? "")")
        characteristics.removeAll()
        verified = false
        pendingChallenge = nil
        handler?.centralLinkDisconnected()
        // 保留 peripheral：proceed() 会对它发起不超时的重连，同时扫描。
        if case .monitoring = mode {
            manager.connect(peripheral)
            manager.scanForPeripherals(withServices: [Self.serviceUUID])
            status = .searching
        } else {
            self.peripheral = nil
            proceed()
        }
    }
}

extension CentralLink: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            reject(peripheral, reason: "没有 NearGuard 服务")
            return
        }
        peripheral.discoverCharacteristics(Self.characteristicUUIDs, for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
        }
        guard let challenge = characteristic(BLEIdentifiers.challenge) else {
            reject(peripheral, reason: "缺少特征")
            return
        }
        // 先读一次挑战，确认 macID。
        peripheral.readValue(for: challenge)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            handler?.centralLinkLog("读取失败：\(error.localizedDescription)")
            return
        }
        guard let value = characteristic.value else { return }
        switch characteristic.uuid {
        case CBUUID(nsuuid: BLEIdentifiers.challenge):
            // Mac 推送的是 1 字节提示时，主动读取完整挑战。
            if value.count <= 1 {
                peripheral.readValue(for: characteristic)
                return
            }
            if !verified {
                guard handler?.centralLinkShouldAccept(challenge: value, from: peripheral.identifier) == true else {
                    reject(peripheral, reason: "不是已配对的 Mac")
                    return
                }
                startSession(on: peripheral)
                if case .monitoring = mode { receive(challenge: value, from: peripheral) }
                return
            }
            receive(challenge: value, from: peripheral)
        case CBUUID(nsuuid: BLEIdentifiers.pairingResult):
            handler?.centralLinkReceivedPairingResult(value, peripheral: peripheral.identifier)
        default:
            break
        }
    }

    private func receive(challenge: Data, from peripheral: CBPeripheral) {
        pendingChallenge = challenge
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard let challenge = pendingChallenge else { return }
        pendingChallenge = nil
        if let error {
            handler?.centralLinkLog("读取信号强度失败：\(error.localizedDescription)")
            return
        }
        guard let report = handler?.centralLinkMakeReport(challenge: challenge, rssi: RSSI.intValue),
            let target = characteristic(BLEIdentifiers.report)
        else {
            handler?.centralLinkLog("本轮未报告：没有生成报告或缺少报告特征")
            return
        }
        peripheral.writeValue(report, for: target, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        switch characteristic.uuid {
        case CBUUID(nsuuid: BLEIdentifiers.report):
            handler?.centralLinkReportWritten(success: error == nil)
            if let error { handler?.centralLinkLog("报告被拒绝：\(error.localizedDescription)") }
        case CBUUID(nsuuid: BLEIdentifiers.pairingRequest):
            if let error {
                handler?.centralLinkLog("配对请求被拒绝：\(error.localizedDescription)")
                status = .verifying
                return
            }
            if let result = self.characteristic(BLEIdentifiers.pairingResult) {
                peripheral.readValue(for: result)
            }
        default:
            break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
    ) {
        if let error {
            handler?.centralLinkLog("订阅失败：\(error.localizedDescription)")
        } else {
            handler?.centralLinkLog(characteristic.isNotifying ? "已订阅挑战" : "已取消订阅")
        }
    }
}
