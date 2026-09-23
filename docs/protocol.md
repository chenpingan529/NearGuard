# 通信协议（v1）

协议版本：`GuardKitInfo.protocolVersion = 1`。不兼容改动必须加 1，并在 CHANGELOG 中标注 `BREAKING`。

## 1. 密钥

| 设备 | 算法 | 保存位置 |
|---|---|---|
| iPhone | P-256 ECDSA | 安全芯片（`SecureEnclaveSigner`），私钥不可导出 |
| Mac | P-256 ECDSA | 钥匙串（`SoftwareSigner.rawRepresentation`），仅本 App 可读 |

公钥：X9.63 格式，65 字节。签名：raw 格式，64 字节。

## 2. 签名封包 `SignedEnvelope`

```
[1 字节 封包版本 = 1][2 字节 载荷长度，大端][载荷][64 字节 签名]
载荷 = JSON {"k": 消息类型, "b": 消息体}，键排序，日期为毫秒时间戳，二进制为 base64
```

- 签名覆盖载荷原始字节；接收方对收到的字节验签，不重新编码。
- `k`（消息类型）在签名范围内，一种消息的签名不能挪给另一种用。
- 先验签，再解析消息体。

## 3. 配对

```
Mac                                               iPhone
 │ 生成 PairingInvite（Mac 公钥 + 16 字节配对码 + 5 分钟有效期）
 │ 显示二维码 nearguard://pair?d=<base64url(JSON)>
 │                                  ◀──── 扫码 ────│
 │                                                 │ 生成安全芯片私钥
 │                                                 │ proof = HMAC-SHA256(配对码,
 │                                                 │   "nearguard-pairing-v1" ‖ 手机公钥 ‖ macID ‖ deviceID)
 │ ◀── BLE 写 pairingRequest：SignedEnvelope<PairingRequest>（手机私钥签名）
 │ 校验：二维码未过期 → macID → 用消息中的公钥验签 → proof → 时间偏差 ≤ 120 秒
 │ 保存 PairedDevice，作废本次二维码
 │ ── BLE 通知 pairingResult：SignedEnvelope<PairingAccept>（Mac 私钥签名）──▶
 │                                                 │ 用二维码里的 Mac 公钥验签
```

安全性要点：

- 配对码只在二维码里出现，BLE 上只传 HMAC，旁路监听者拿不到配对码。
- 请求用手机自己的私钥签名，替换请求中的公钥会导致验签失败。
- iPhone 用二维码中的 Mac 公钥校验回执，防止假冒 Mac。
- 二维码一次有效，Mac 完成一次配对后立即作废。

## 4. 测距（BLE）

服务与特征 UUID 见 `BLEIdentifiers`。Mac 为外设，iPhone 为中心设备。

| 特征 | 方向 | 内容 |
|---|---|---|
| `challenge` | Mac → iPhone（读 / 通知） | `Challenge`（明文 JSON：16 字节随机数 + 时间） |
| `report` | iPhone → Mac（写，带响应） | `SignedEnvelope<ProximityReport>` |

- Mac 的 `ChallengeBook`：随机数有效期 10 秒，只能核销一次，最多同时保留 8 个。
- 报告必须满足：签名有效、`macID` 与 `deviceID` 匹配、随机数由本机签发且未使用。
- 封包约 250 字节，在 BLE 单次长写（512 字节）范围内。

## 5. 远程指令（CloudKit）

记录结构见 `CloudSchema`，容器 `iCloud.com.nearguard`，私有数据库，自定义区 `NearGuard`。

| 记录 | 方向 | 内容 |
|---|---|---|
| `Incident` | Mac → iPhone | 事件时间、触发原因、处理状态、照片（CKAsset） |
| `Command` | iPhone → Mac | `SignedEnvelope<RemoteCommand>` 序列化字节 |
| `Device` | 双向 | 已配对设备信息 |

远程指令无法做挑战应答，采用 `ReplayGuard`：`issuedAt` 与 Mac 当前时间相差不超过 120 秒，且 16 字节随机数在窗口内未出现过。

`RemoteCommand.Action`：

- `lockNow`：锁屏并抓拍；有观察中的事件时立即上报。
- `confirmItsMe(incidentID)`：确认是本人，撤销对应事件。

iPhone 发送指令前要求 Face ID 验证。
