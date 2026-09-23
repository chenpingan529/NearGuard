import Foundation

/// BLE 服务和特征的 UUID。Mac 是外设（被连接方），iPhone 是中心设备（主动连接方）。
/// 见 docs/decisions/0001-iphone-as-central.md。
public enum BLEIdentifiers {
    /// NearGuard 服务。
    public static let service = UUID(uuidString: "6E47A7B0-3C1F-4B8E-9F52-2D6A0C9B1E10")!
    /// 读 / 订阅：Mac 发出的挑战（`Challenge`，明文 JSON）。
    public static let challenge = UUID(uuidString: "6E47A7B1-3C1F-4B8E-9F52-2D6A0C9B1E10")!
    /// 写：iPhone 发送的测距报告（`SignedEnvelope<ProximityReport>`）。
    public static let report = UUID(uuidString: "6E47A7B2-3C1F-4B8E-9F52-2D6A0C9B1E10")!
    /// 写：配对请求（`SignedEnvelope<PairingRequest>`）。
    public static let pairingRequest = UUID(uuidString: "6E47A7B3-3C1F-4B8E-9F52-2D6A0C9B1E10")!
    /// 读 / 订阅：配对结果（`SignedEnvelope<PairingAccept>`，Mac 签名）。
    public static let pairingResult = UUID(uuidString: "6E47A7B4-3C1F-4B8E-9F52-2D6A0C9B1E10")!
}
