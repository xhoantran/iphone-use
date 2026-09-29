import Foundation

/// `iphone-use mcp`: an MCP server over stdio that forwards to the running app's HTTP API.
/// Screenshots are scaled so the long edge is at most `longEdge`; tap and swipe
/// coordinates are read in that scaled image's pixels.
enum MCPServer {
    static let longEdge = 1200
    static var base = URL(string: "http://127.0.0.1:7390")!

    static let device: [String: Any] = [
        "type": "string",
        "description": "Which iPhone (id or name from list_devices). Only needed when several are connected.",
    ]

    static let tools: [[String: Any]] = [
        tool("list_devices", "List the connected iPhones.", [:]),
        tool("screenshot", "Take a screenshot of the iPhone screen.", ["device": device]),
        tool(
            "tap", "Tap a point on the iPhone screen. Coordinates are pixels of the latest screenshot.",
            ["x": number("X in screenshot pixels"), "y": number("Y in screenshot pixels"), "device": device],
            required: ["x", "y"]),
        tool(
            "long_press", "Press and hold a point, e.g. to open a context menu.",
            [
                "x": number("X in screenshot pixels"), "y": number("Y in screenshot pixels"),
                "seconds": number("How long to hold (default 1)"), "device": device,
            ], required: ["x", "y"]),
        tool(
            "swipe", "Drag from one point to another, e.g. to scroll. Coordinates are screenshot pixels.",
            [
                "x1": number("Start X"), "y1": number("Start Y"), "x2": number("End X"), "y2": number("End Y"),
                "seconds": number("Duration (default 0.3)"), "device": device,
            ], required: ["x1", "y1", "x2", "y2"]),
        tool(
            "type_text", "Type text into the focused field with the Bluetooth keyboard (US layout, ASCII only).",
            ["text": ["type": "string"], "device": device], required: ["text"]),
        tool(
            "press_key",
            "Press a key, optionally with modifiers. Keys: enter, escape, backspace, tab, space, up, down, left, right, or a character. Modifiers: cmd, shift, alt, ctrl. cmd+space opens Spotlight.",
            [
                "key": ["type": "string"], "modifiers": ["type": "array", "items": ["type": "string"]],
                "device": device,
            ],
            required: ["key"]),
        tool("home", "Go to the Home Screen.", ["device": device]),
    ]

    static func run() -> Never {
        if let port = ProcessInfo.processInfo.environment["IPHONE_USE_PORT"] {
            base = URL(string: "http://127.0.0.1:\(port)")!
        }
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            handle(message)
        }
        exit(0)
    }

    private static func handle(_ message: [String: Any]) {
        guard let id = message["id"], let method = message["method"] as? String else { return }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            reply(id, [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "iphone-use", "version": "0.2.0"],
                "instructions":
                    "Controls real iPhones. Take a screenshot first, then tap using pixel coordinates from the most recent screenshot of that phone. Take another screenshot to check the result. With several phones connected, call list_devices and pass device to every tool.",
            ])
        case "tools/list":
            reply(id, ["tools": tools])
        case "tools/call":
            reply(id, call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:]))
        case "ping":
            reply(id, [:])
        default:
            let error: [String: Any] = ["code": -32601, "message": "method not found: \(method)"]
            write(["jsonrpc": "2.0", "id": id, "error": error])
        }
    }

    private static func call(_ name: String, _ args: [String: Any]) -> [String: Any] {
        let device = args["device"] as? String
        do {
            switch name {
            case "list_devices":
                let (data, _) = try get("/devices")
                return ["content": [["type": "text", "text": String(decoding: data, as: UTF8.self)]]]
            case "screenshot":
                return try screenshot(device)
            case "tap":
                try post("/tap", scaled(args, ["x", "y"]))
            case "long_press":
                var body = try scaled(args, ["x", "y"])
                body["hold"] = args["seconds"] ?? 1.0
                try post("/tap", body)
            case "swipe":
                var body = try scaled(args, ["x1", "y1", "x2", "y2"])
                body["duration"] = args["seconds"] ?? 0.3
                try post("/swipe", body)
            case "type_text":
                try post("/type", withDevice(["text": args["text"] ?? ""], device))
            case "press_key":
                try post("/key", withDevice(["key": args["key"] ?? "", "modifiers": args["modifiers"] ?? []], device))
            case "home":
                try post("/home", withDevice([:], device))
            default:
                return failure("unknown tool \(name)")
            }
            Thread.sleep(forTimeInterval: 0.6)
            return try screenshot(device)
        } catch {
            return failure("\(error)")
        }
    }

    private static func screenshot(_ device: String?) throws -> [String: Any] {
        var path = "/screenshot?maxEdge=\(longEdge)"
        if let device, let encoded = device.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&device=\(encoded)"
        }
        let (image, response) = try get(path)
        let width = response.value(forHTTPHeaderField: "X-Image-Width") ?? "?"
        let height = response.value(forHTTPHeaderField: "X-Image-Height") ?? "?"
        let id = response.value(forHTTPHeaderField: "X-Device") ?? ""
        return [
            "content": [
                ["type": "image", "data": image.base64EncodedString(), "mimeType": "image/jpeg"],
                ["type": "text", "text": "Screenshot of \(id), \(width)x\(height) px. Use these pixels for tap and swipe."],
            ]
        ]
    }

    /// Coordinates arrive in screenshot pixels; `maxEdge` tells the app how that screenshot was scaled.
    private static func scaled(_ args: [String: Any], _ keys: [String]) throws -> [String: Any] {
        var body: [String: Any] = ["maxEdge": longEdge]
        for key in keys {
            guard let value = args[key] else { throw MCPError("\(key) is required") }
            body[key] = value
        }
        return withDevice(body, args["device"] as? String)
    }

    private static func withDevice(_ body: [String: Any], _ device: String?) -> [String: Any] {
        guard let device else { return body }
        return body.merging(["device": device]) { $1 }
    }

    private static func get(_ path: String) throws -> (Data, HTTPURLResponse) {
        try request(URLRequest(url: URL(string: path, relativeTo: base)!))
    }

    @discardableResult
    private static func post(_ path: String, _ body: [String: Any]) throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try self.request(request).0
    }

    private static func request(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        var result: Result<(Data, HTTPURLResponse), Error> = .failure(MCPError("no response"))
        let done = DispatchSemaphore(value: 0)
        var request = request
        request.timeoutInterval = 60
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(MCPError("iPhone Use app is not running (\(error.localizedDescription))"))
            } else if let data, let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    result = .success((data, http))
                } else {
                    let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"]
                    result = .failure(MCPError(message as? String ?? "HTTP \(http.statusCode)"))
                }
            }
            done.signal()
        }.resume()
        done.wait()
        return try result.get()
    }

    private static func reply(_ id: Any, _ result: [String: Any]) {
        write(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private static func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    private static func failure(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }

    private static func tool(
        _ name: String, _ description: String, _ properties: [String: Any], required: [String] = []
    ) -> [String: Any] {
        [
            "name": name, "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required],
        ]
    }

    private static func number(_ description: String) -> [String: Any] {
        ["type": "number", "description": description]
    }

    struct MCPError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
