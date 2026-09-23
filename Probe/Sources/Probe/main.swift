import Foundation
import AppKit

let usage = """
用法：
  swift run Probe status                                  查看权限和系统状态
  swift run Probe snap                                    立即抓拍一张（测试摄像头权限）
  swift run Probe lock                                    立即锁屏
  swift run Probe unlock-test [--delay 5] [--mode unicode|keycode]
                                                          验证 1：锁屏后自动输入密码解锁
  swift run Probe watch [--always]                        验证 2：锁屏时检测操作并抓拍
"""

func option(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let command = CommandLine.arguments.dropFirst().first ?? "help"

switch command {
case "status":
    print("锁屏状态：\(SystemState.isScreenLocked())")
    print("空闲时间：\(SystemState.hidIdleSeconds().map { String(format: "%.2f 秒", $0) } ?? "读取失败")")
    print("合盖状态：\(SystemState.isClamshellClosed().map { $0 ? "合上" : "打开" } ?? "未知")")
    print("辅助功能权限：\(Keyboard.isTrusted(prompt: false) ? "已授权" : "未授权")")
    print("摄像头权限：\(Camera.authorizationDescription())")
    print("输出目录：\(outputDir.path)")

case "snap":
    let camera = Camera(outputDir: outputDir.appendingPathComponent("captures"))
    Camera.requestAccess { granted in
        guard granted else {
            log("❌ 摄像头权限被拒绝")
            exit(1)
        }
        camera.capture(tag: "manual") { url in
            log(url.map { "📸 已保存：\($0.path)" } ?? "❌ 抓拍失败")
            exit(url == nil ? 1 : 0)
        }
    }
    RunLoop.main.run()

case "lock":
    exit(SystemState.lockScreen() ? 0 : 1)

case "unlock-test":
    let delay = option("--delay").flatMap(Double.init) ?? 5
    let mode = option("--mode").flatMap(Keyboard.Mode.init(rawValue:)) ?? .unicode
    exit(UnlockTest.run(delay: delay, mode: mode))

case "watch":
    let watcher = Watcher(alwaysGuard: CommandLine.arguments.contains("--always"))
    signal(SIGINT) { _ in
        log("结束监听")
        exit(0)
    }
    watcher.start()
    withExtendedLifetime(watcher) { RunLoop.main.run() }

default:
    print(usage)
}
