import Foundation

/// CloudKit 私有数据库的记录结构。两端必须使用同一份定义。
/// 具体读写在 M3 实现，这里先固定命名，避免两端各写各的。
public enum CloudSchema {
    public static let containerID = "iCloud.com.nearguard"
    /// 自定义记录区，便于用 `CKFetchRecordZoneChangesOperation` 增量同步。
    public static let zoneName = "NearGuard"

    /// Mac → iPhone：一次报警事件。iPhone 订阅它并弹出带按钮的通知。
    public enum Incident {
        public static let recordType = "Incident"
        public static let macID = "macID"
        public static let macName = "macName"
        public static let startedAt = "startedAt"
        public static let trigger = "trigger"  // CaptureReason.rawValue
        public static let status = "status"  // IncidentStatus.rawValue
        public static let photo = "photo"  // CKAsset，JPEG
    }

    /// iPhone → Mac：远程指令。Mac 订阅它（静默推送）。
    public enum Command {
        public static let recordType = "Command"
        public static let macID = "macID"
        /// `SignedEnvelope.serialized()`，Mac 收到后用已配对的公钥验签。
        public static let envelope = "envelope"
    }

    /// 已配对的设备，用于多设备管理和在新设备上显示配对关系。
    public enum Device {
        public static let recordType = "Device"
        public static let deviceID = "deviceID"
        public static let name = "name"
        public static let publicKey = "publicKey"
        public static let role = "role"  // "mac" / "phone"
    }
}

/// 报警事件的处理状态。
public enum IncidentStatus: String, Codable, Sendable {
    /// 已上报，等待手机处理。
    case open
    /// 手机上确认是本人。
    case confirmedOwner
    /// 手机上选择了立即锁定。
    case lockedRemotely
}
