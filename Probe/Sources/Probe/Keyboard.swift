import Foundation
import CoreGraphics
import ApplicationServices

/// 通过 CGEvent 模拟键盘输入。需要「辅助功能」权限。
enum Keyboard {
    enum Mode: String {
        /// 用 Unicode 字符串直接注入，不依赖键盘布局。
        case unicode
        /// 按美式键盘布局映射成真实键码（部分锁屏实现只认真实键码）。
        case keycode
    }

    /// 检查辅助功能权限；prompt 为 true 时会弹出系统授权引导。
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// 输入字符串；返回 false 表示有字符无法映射。
    static func type(_ text: String, mode: Mode) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        for char in text {
            switch mode {
            case .unicode:
                postUnicode(char, source: source)
            case .keycode:
                guard let (code, shift) = usKeyMap[char] else { return false }
                postKey(code, shift: shift, source: source)
            }
            usleep(25_000)
        }
        return true
    }

    static func pressReturn() {
        postKey(36, shift: false, source: CGEventSource(stateID: .hidSystemState))
    }

    /// 按一下 Shift，用来唤出锁屏的密码输入框，不会输入任何字符。
    static func tapShift() {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: true)?.post(tap: .cghidEventTap)
        usleep(20_000)
        CGEvent(keyboardEventSource: source, virtualKey: 56, keyDown: false)?.post(tap: .cghidEventTap)
    }

    private static func postUnicode(_ char: Character, source: CGEventSource?) {
        let utf16 = Array(String(char).utf16)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
            event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func postKey(_ code: CGKeyCode, shift: Bool, source: CGEventSource?) {
        let flags: CGEventFlags = shift ? .maskShift : []
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// 美式 ANSI 键盘：字符 -> (键码, 是否需要 Shift)
    private static let usKeyMap: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [:]
        let letters: [(Character, CGKeyCode)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
            ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15),
            ("y", 16), ("t", 17), ("o", 31), ("u", 32), ("i", 34), ("p", 35), ("l", 37),
            ("j", 38), ("k", 40), ("n", 45), ("m", 46),
        ]
        for (c, code) in letters {
            map[c] = (code, false)
            map[Character(c.uppercased())] = (code, true)
        }
        let plain: [(Character, CGKeyCode)] = [
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24),
            ("9", 25), ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30), ("[", 33),
            ("'", 39), (";", 41), ("\\", 42), (",", 43), ("/", 44), (".", 47), ("`", 50), (" ", 49),
        ]
        let shifted: [(Character, CGKeyCode)] = [
            ("!", 18), ("@", 19), ("#", 20), ("$", 21), ("^", 22), ("%", 23), ("+", 24),
            ("(", 25), ("&", 26), ("_", 27), ("*", 28), (")", 29), ("}", 30), ("{", 33),
            ("\"", 39), (":", 41), ("|", 42), ("<", 43), ("?", 44), (">", 47), ("~", 50),
        ]
        for (c, code) in plain { map[c] = (code, false) }
        for (c, code) in shifted { map[c] = (code, true) }
        return map
    }()
}
