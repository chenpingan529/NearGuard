import Foundation

/// BLE 属性读写的分段处理。消息超过一个数据包时，CoreBluetooth 会按偏移分段读写。
public enum ATT {
    /// 单个属性值的上限（ATT 规范）。
    public static let maxAttributeLength = 512

    /// 外设端：把一次长写入收到的多个分段按偏移拼回完整数据。
    /// 分段必须从 0 开始、首尾相接、不重叠，总长度不超过 512 字节。
    public static func assemble(_ parts: [(offset: Int, value: Data)]) throws -> Data {
        var result = Data()
        for part in parts.sorted(by: { $0.offset < $1.offset }) {
            guard part.offset == result.count else { throw GuardKitError.malformed }
            result.append(part.value)
        }
        guard !result.isEmpty, result.count <= maxAttributeLength else { throw GuardKitError.malformed }
        return result
    }

    /// 外设端：响应长读取的某个偏移。偏移超出范围返回 nil（应回复 invalidOffset）。
    public static func slice(_ value: Data, offset: Int) -> Data? {
        guard offset >= 0, offset <= value.count else { return nil }
        return value.subdata(in: (value.startIndex + offset)..<value.endIndex)
    }
}
