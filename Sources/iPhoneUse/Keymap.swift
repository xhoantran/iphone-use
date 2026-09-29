/// US keyboard layout, HID usage page 0x07.
enum Keymap {
    struct Stroke {
        let code: UInt8
        let modifiers: UInt8
    }

    static let shift: UInt8 = 0x02

    static let modifiers: [String: UInt8] = [
        "ctrl": 0x01, "control": 0x01,
        "shift": 0x02,
        "alt": 0x04, "option": 0x04,
        "cmd": 0x08, "command": 0x08,
    ]

    static let named: [String: UInt8] = [
        "enter": 0x28, "return": 0x28, "escape": 0x29, "esc": 0x29,
        "backspace": 0x2A, "delete": 0x2A, "tab": 0x2B, "space": 0x2C,
        "right": 0x4F, "left": 0x50, "down": 0x51, "up": 0x52,
        "forwarddelete": 0x4C, "home": 0x4A, "end": 0x4D, "pageup": 0x4B, "pagedown": 0x4E,
    ]

    private static let plain: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() { map[c] = 0x04 + UInt8(i) }
        for (i, c) in "1234567890".enumerated() { map[c] = 0x1E + UInt8(i) }
        let rest: [(Character, UInt8)] = [
            ("\n", 0x28), ("\t", 0x2B), (" ", 0x2C), ("-", 0x2D), ("=", 0x2E), ("[", 0x2F), ("]", 0x30),
            ("\\", 0x31), (";", 0x33), ("'", 0x34), ("`", 0x35), (",", 0x36), (".", 0x37), ("/", 0x38),
        ]
        for (c, code) in rest { map[c] = code }
        return map
    }()

    private static let shifted: [Character: Character] = {
        var map: [Character: Character] = [:]
        for c in "abcdefghijklmnopqrstuvwxyz" { map[Character(c.uppercased())] = c }
        let pairs = Array(zip("!@#$%^&*()_+{}|:\"~<>?", "1234567890-=[]\\;'`,./"))
        for (upper, lower) in pairs { map[upper] = lower }
        return map
    }()

    static func stroke(for character: Character) -> Stroke? {
        if let code = plain[character] { return Stroke(code: code, modifiers: 0) }
        if let base = shifted[character], let code = plain[base] { return Stroke(code: code, modifiers: shift) }
        return nil
    }
}
