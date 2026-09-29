import Foundation

/// The HTTP API. Tap and swipe coordinates are pixels of the screenshot; pass
/// width/height when they refer to a resized screenshot.
enum Routes {
    static func handle(_ request: HTTPRequest) -> HTTPResponse {
        let input = Input.shared
        let body = request.body
        do {
            switch (request.method, request.path) {
            case ("GET", "/"), ("GET", "/status"):
                return status()

            case ("GET", "/screenshot"):
                let png = request.query["format"] == "png"
                let maxWidth = request.query["maxWidth"].flatMap(Int.init)
                guard let size = ScreenCapture.shared.size,
                    let data = ScreenCapture.shared.snapshot(png: png, maxWidth: maxWidth)
                else { return .error("no screen yet: plug the iPhone in over USB and unlock it", status: 503) }
                return HTTPResponse(
                    contentType: png ? "image/png" : "image/jpeg",
                    headers: ["X-Screen-Width": "\(Int(size.width))", "X-Screen-Height": "\(Int(size.height))"],
                    body: data)

            case ("POST", "/tap"):
                let (x, y) = try point(body, "x", "y")
                input.tap(x: x, y: y, hold: (body["hold"] as? Double) ?? 0.08)
                return .json(["ok": true])

            case ("POST", "/swipe"):
                let from = try point(body, "x1", "y1")
                let to = try point(body, "x2", "y2")
                input.swipe(from: from, to: to, duration: (body["duration"] as? Double) ?? 0.3)
                return .json(["ok": true])

            case ("POST", "/move"):
                let (x, y) = try point(body, "x", "y")
                input.move(x: x, y: y)
                return .json(["ok": true])

            case ("POST", "/nudge"):
                input.nudge(
                    dx: (body["dx"] as? Int) ?? 0, dy: (body["dy"] as? Int) ?? 0,
                    click: (body["click"] as? Bool) ?? false)
                return .json(["ok": true])

            case ("POST", "/type"):
                guard let text = body["text"] as? String else { return .error("text is required") }
                try input.type(text)
                return .json(["ok": true])

            case ("POST", "/key"):
                guard let key = body["key"] as? String else { return .error("key is required") }
                try input.key(key, modifiers: (body["modifiers"] as? [String]) ?? [])
                return .json(["ok": true])

            case ("POST", "/home"):
                input.consumer(0x0223)
                return .json(["ok": true])

            default:
                return .error("not found", status: 404)
            }
        } catch {
            return .error("\(error)")
        }
    }

    private static func status() -> HTTPResponse {
        var screen: [String: Any] = [:]
        if let size = ScreenCapture.shared.size {
            screen = ["name": ScreenCapture.shared.deviceName ?? "", "width": size.width, "height": size.height]
        }
        return .json([
            "bluetooth": HIDPeripheral.shared.state,
            "hosts": HIDPeripheral.shared.connectedHosts,
            "screen": screen.isEmpty ? NSNull() as Any : screen as Any,
        ])
    }

    /// Converts pixel coordinates to 0...1 fractions of the screen.
    private static func point(_ body: [String: Any], _ xKey: String, _ yKey: String) throws -> (Double, Double) {
        guard let x = number(body[xKey]), let y = number(body[yKey]) else {
            throw RouteError("\(xKey) and \(yKey) are required")
        }
        if let fraction = body["fraction"] as? Bool, fraction { return (x, y) }
        let size = ScreenCapture.shared.size
        guard let width = number(body["width"]) ?? size.map({ Double($0.width) }),
            let height = number(body["height"]) ?? size.map({ Double($0.height) })
        else { throw RouteError("no screen size yet: pass width and height, or fraction: true") }
        return (x / width, y / height)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    struct RouteError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
