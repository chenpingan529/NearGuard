// swift-tools-version:6.2
// GuardKit：Mac 与 iPhone 两端共用的核心逻辑。
// 这里只放纯逻辑（协议、加密、测距滤波、警戒状态机），不直接调用系统 UI、BLE 或摄像头，便于单元测试。
import PackageDescription

let package = Package(
    name: "GuardKit",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "GuardKit", targets: ["GuardKit"])
    ],
    targets: [
        .target(name: "GuardKit"),
        .testTarget(name: "GuardKitTests", dependencies: ["GuardKit"]),
    ]
)
