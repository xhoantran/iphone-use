import Foundation

/// Turns taps, swipes and text into HID reports. Runs on one serial queue so gestures
/// from concurrent requests never interleave.
final class Input {
    static let shared = Input()

    private let queue = DispatchQueue(label: "iphone-use.input")
    private let hid = HIDPeripheral.shared
    private var buttons: UInt8 = 0

    /// Seconds between reports. BLE connection intervals are ~15-30 ms.
    var step: TimeInterval = 0.03

    /// Coordinates are fractions of the screen, 0...1 from the top-left corner.
    func tap(x: Double, y: Double, hold: TimeInterval = 0.08) {
        queue.sync {
            pointer(x, y)
            pause(step * 2)
            button(down: true)
            pause(hold)
            button(down: false)
            pause(step)
        }
    }

    func swipe(from: (Double, Double), to: (Double, Double), duration: TimeInterval) {
        queue.sync {
            let steps = max(2, Int(duration / step))
            pointer(from.0, from.1)
            pause(step * 2)
            button(down: true)
            pause(step)
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                pointer(from.0 + (to.0 - from.0) * t, from.1 + (to.1 - from.1) * t)
                pause(duration / Double(steps))
            }
            button(down: false)
            pause(step)
        }
    }

    func move(x: Double, y: Double) {
        queue.sync {
            pointer(x, y)
            pause(step)
        }
    }

    /// Relative mouse, for testing hosts that ignore the absolute pointer.
    func nudge(dx: Int, dy: Int, click: Bool) {
        queue.sync {
            var remainingX = dx
            var remainingY = dy
            while remainingX != 0 || remainingY != 0 {
                let sx = max(-127, min(127, remainingX))
                let sy = max(-127, min(127, remainingY))
                hid.send(.relativeMouse, [0, UInt8(bitPattern: Int8(sx)), UInt8(bitPattern: Int8(sy)), 0])
                remainingX -= sx
                remainingY -= sy
                pause(step)
            }
            if click {
                hid.send(.relativeMouse, [1, 0, 0, 0])
                pause(0.08)
                hid.send(.relativeMouse, [0, 0, 0, 0])
                pause(step)
            }
        }
    }

    func type(_ text: String) throws {
        let strokes = try text.map { character -> Keymap.Stroke in
            guard let stroke = Keymap.stroke(for: character) else { throw InputError.untypeable(character) }
            return stroke
        }
        queue.sync {
            for stroke in strokes {
                press(stroke)
            }
        }
    }

    /// A named key with optional modifiers, e.g. key("h", modifiers: ["cmd"]).
    func key(_ name: String, modifiers: [String]) throws {
        guard let code = Keymap.named[name.lowercased()] ?? Keymap.stroke(for: Character(name))?.code
        else { throw InputError.unknownKey(name) }
        var mask: UInt8 = 0
        for modifier in modifiers {
            guard let bit = Keymap.modifiers[modifier.lowercased()] else { throw InputError.unknownKey(modifier) }
            mask |= bit
        }
        queue.sync { press(Keymap.Stroke(code: code, modifiers: mask)) }
    }

    func consumer(_ usage: UInt16) {
        queue.sync {
            hid.send(.consumer, [UInt8(usage & 0xFF), UInt8(usage >> 8)])
            pause(0.08)
            hid.send(.consumer, [0, 0])
            pause(step)
        }
    }

    private func press(_ stroke: Keymap.Stroke) {
        if stroke.modifiers != 0 {
            hid.send(.keyboard, [stroke.modifiers, 0, 0, 0, 0, 0, 0, 0])
            pause(step)
        }
        hid.send(.keyboard, [stroke.modifiers, 0, stroke.code, 0, 0, 0, 0, 0])
        pause(step)
        hid.send(.keyboard, [stroke.modifiers, 0, 0, 0, 0, 0, 0, 0])
        pause(step)
        if stroke.modifiers != 0 {
            hid.send(.keyboard, [0, 0, 0, 0, 0, 0, 0, 0])
            pause(step)
        }
    }

    /// iOS positions the pointer from the absolute report but ignores its buttons,
    /// so clicks go through the relative mouse.
    private func pointer(_ x: Double, _ y: Double) {
        let max = Double(HIDReportMap.absoluteMax)
        let px = UInt16(Swift.max(0, Swift.min(max, (x * max).rounded())))
        let py = UInt16(Swift.max(0, Swift.min(max, (y * max).rounded())))
        hid.send(.absolutePointer, [buttons, UInt8(px & 0xFF), UInt8(px >> 8), UInt8(py & 0xFF), UInt8(py >> 8)])
    }

    private func button(down: Bool) {
        buttons = down ? 1 : 0
        hid.send(.relativeMouse, [buttons, 0, 0, 0])
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    enum InputError: Error, CustomStringConvertible {
        case untypeable(Character)
        case unknownKey(String)

        var description: String {
            switch self {
            case .untypeable(let c): "cannot type \(String(reflecting: c)) with a US keyboard"
            case .unknownKey(let k): "unknown key \(k)"
            }
        }
    }
}
