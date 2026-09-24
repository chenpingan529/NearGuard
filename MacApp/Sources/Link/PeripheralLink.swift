import CoreBluetooth
import Foundation
import GuardKit

/// PeripheralLink 把收到的字节交给它处理。所有判断逻辑都在 GuardKit 里，这里只做转发。
@MainActor
protocol PeripheralLinkHandler: AnyObject {
    func peripheralLinkStateChanged(_ state: CBManagerState)
    /// 生成一个新挑战的字节。
    func peripheralLinkMakeChallenge() -> Data?
    /// 收到测距报告，返回是否校验通过。
    func peripheralLinkReceivedReport(_ data: Data) -> Bool
    /// 收到配对请求，成功时返回要让 iPhone 读取的配对回执。
    func peripheralLinkReceivedPairingRequest(_ data: Data) -> Data?
    func peripheralLinkSubscribersChanged(count: Int, lost: Bool)
    func peripheralLinkLog(_ message: String)
}

/// Mac 端 BLE 外设：广播 NearGuard 服务，定时向订阅者推送挑战，接收报告和配对请求。
/// 见 docs/protocol.md。
@MainActor
final class PeripheralLink: NSObject {
    weak var handler: PeripheralLinkHandler?
    /// 推送挑战的间隔，也就是 iPhone 报告的频率。
    let pushInterval: TimeInterval = 2

    private var manager: CBPeripheralManager!
    private let challengeCharacteristic = CBMutableCharacteristic(
        type: CBUUID(nsuuid: BLEIdentifiers.challenge), properties: [.read, .notify], value: nil,
        permissions: [.readable])
    private let reportCharacteristic = CBMutableCharacteristic(
        type: CBUUID(nsuuid: BLEIdentifiers.report), properties: [.write], value: nil, permissions: [.writeable])
    private let pairingRequestCharacteristic = CBMutableCharacteristic(
        type: CBUUID(nsuuid: BLEIdentifiers.pairingRequest), properties: [.write], value: nil,
        permissions: [.writeable])
    private let pairingResultCharacteristic = CBMutableCharacteristic(
        type: CBUUID(nsuuid: BLEIdentifiers.pairingResult), properties: [.read], value: nil, permissions: [.readable])

    private var subscribers: [UUID: CBCentral] = [:]
    /// 长读取时后续分段必须返回同一份数据，按 central 缓存。
    private var challengeReads: [UUID: Data] = [:]
    private var pairingResults: [UUID: Data] = [:]
    private var pushTimer: Timer?
    private var pendingNotification: Data?

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    var isAdvertising: Bool { manager.isAdvertising }

    private func publish() {
        manager.removeAllServices()
        let service = CBMutableService(type: CBUUID(nsuuid: BLEIdentifiers.service), primary: true)
        service.characteristics = [
            challengeCharacteristic, reportCharacteristic, pairingRequestCharacteristic, pairingResultCharacteristic,
        ]
        manager.add(service)
    }

    private func updatePushTimer() {
        if subscribers.isEmpty {
            pushTimer?.invalidate()
            pushTimer = nil
        } else if pushTimer == nil {
            pushTimer = Timer.scheduledTimer(withTimeInterval: pushInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pushChallenge() }
            }
            pushChallenge()
        }
    }

    /// 推送新挑战。数据放不进一个通知包时，只推送 1 字节提示，让 iPhone 主动读取。
    private func pushChallenge() {
        guard let data = handler?.peripheralLinkMakeChallenge() else { return }
        let limit = subscribers.values.map(\.maximumUpdateValueLength).min() ?? 0
        let payload = data.count <= limit ? data : Data([0])
        if !manager.updateValue(payload, for: challengeCharacteristic, onSubscribedCentrals: nil) {
            pendingNotification = payload
        }
    }
}

extension PeripheralLink: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        handler?.peripheralLinkStateChanged(peripheral.state)
        if peripheral.state == .poweredOn {
            publish()
        } else {
            subscribers.removeAll()
            updatePushTimer()
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            handler?.peripheralLinkLog("添加服务失败：\(error.localizedDescription)")
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(nsuuid: BLEIdentifiers.service)],
            CBAdvertisementDataLocalNameKey: "NearGuard",
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        handler?.peripheralLinkLog(error.map { "广播失败：\($0.localizedDescription)" } ?? "开始广播")
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid == challengeCharacteristic.uuid else { return }
        subscribers[central.identifier] = central
        handler?.peripheralLinkLog("iPhone 已订阅，通知最大长度 \(central.maximumUpdateValueLength) 字节")
        handler?.peripheralLinkSubscribersChanged(count: subscribers.count, lost: false)
        updatePushTimer()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard characteristic.uuid == challengeCharacteristic.uuid else { return }
        subscribers.removeValue(forKey: central.identifier)
        challengeReads.removeValue(forKey: central.identifier)
        handler?.peripheralLinkSubscribersChanged(count: subscribers.count, lost: true)
        updatePushTimer()
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let payload = pendingNotification else { return }
        if peripheral.updateValue(payload, for: challengeCharacteristic, onSubscribedCentrals: nil) {
            pendingNotification = nil
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let central = request.central.identifier
        let value: Data?
        switch request.characteristic.uuid {
        case challengeCharacteristic.uuid:
            if request.offset == 0 { challengeReads[central] = handler?.peripheralLinkMakeChallenge() }
            value = challengeReads[central]
        case pairingResultCharacteristic.uuid:
            value = pairingResults[central]
        default:
            value = nil
        }
        guard let value else {
            peripheral.respond(to: request, withResult: .readNotPermitted)
            return
        }
        guard let slice = ATT.slice(value, offset: request.offset) else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = slice
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let first = requests.first else { return }
        let parts = requests.map { (offset: $0.offset, value: $0.value ?? Data()) }
        guard requests.allSatisfy({ $0.characteristic.uuid == first.characteristic.uuid }),
            let data = try? ATT.assemble(parts)
        else {
            peripheral.respond(to: first, withResult: .invalidAttributeValueLength)
            return
        }
        let accepted: Bool
        switch first.characteristic.uuid {
        case reportCharacteristic.uuid:
            accepted = handler?.peripheralLinkReceivedReport(data) ?? false
        case pairingRequestCharacteristic.uuid:
            if let result = handler?.peripheralLinkReceivedPairingRequest(data) {
                pairingResults[first.central.identifier] = result
                accepted = true
            } else {
                accepted = false
            }
        default:
            accepted = false
        }
        peripheral.respond(to: first, withResult: accepted ? .success : .insufficientAuthorization)
    }
}
