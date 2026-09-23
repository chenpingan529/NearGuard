// swift-tools-version:5.9
// 原型验证工具：验证「锁屏状态下模拟输入解锁」与「锁屏状态下检测操作 + 抓拍」是否可行。
import PackageDescription

let package = Package(
    name: "Probe",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Probe",
            path: "Sources/Probe",
            linkerSettings: [
                // 把 Info.plist 嵌入二进制，TCC 请求摄像头权限时需要 NSCameraUsageDescription
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ]),
                .linkedFramework("IOKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
