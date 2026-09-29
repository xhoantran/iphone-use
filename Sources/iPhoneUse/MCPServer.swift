import Foundation

/// `iphone-use mcp`: an MCP server over stdio that forwards to the running app's HTTP API.
/// Screenshots are scaled so the long edge is at most `longEdge`; tap and swipe
/// coordinates are read in that scaled image's pixels.
enum MCPServer {
    static let longEdge = 1200.0
    static var base = URL(string: "http://127.0.0.1:7390")!

    static let tools: [[String: Any]] = [
        tool("screenshot", "Take a screenshot of the iPhone screen.", [:]),
        tool(
            "tap", "Tap a point on the iPhone screen. Coordinates are pixels of the latest screenshot.",
            ["x": number("X in screenshot pixels"), "y": number("Y in screenshot pixels")], required: ["x", "y"]),
        tool(
            "long_press", "Press and hold a point, e.g. to open a context menu.",
            [
                "x": number("X in screenshot pixels"), "y": number("Y in screenshot pixels"),
                "seconds": number("How long to hold (default 1)"),
            ], required: ["x", "y"]),
        tool(
            "swipe", "Drag from one point to another, e.g. to scroll. Coordinates are screenshot pixels.",
            [
                "x1": number("Start X"), "y1": number("Start Y"), "x2": number("End X"), "y2": number("End Y"),
                "seconds": number("Duration (default 0.3)"),
            ], required: ["x1", "y1", "x2", "y2"]),
        tool(
            "type_text", "Type text into the focused field with the Bluetooth keyboard (US layout, ASCII only).",
            ["text": ["type": "string"]], required: ["text"]),
        tool(
            "press_key",
            "Press a key, optionally with modifiers. Keys: enter, escape, backspace, tab, space, up, down, left, right, or a character. Modifiers: cmd, shift, alt, ctrl. cmd+space opens Spotlight.",
            ["key": ["type": "string"], "modifiers": ["type": "array", "items": ["type": "string"]]],
            required: ["key"]),
        tool("home", "Go to the Home Screen.", [:]),
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
                "serverInfo": ["name": "iphone-use", "version": "0.1.0"],
                "instructions":
                    "Controls a real iPhone. Take a screenshot first, then tap using pixel coordinates from the most recent screenshot. Take another screenshot to check the result.",
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
        do {
            switch name {
            case "screenshot":
                return try screenshot()
            case "tap":
                try post("/tap", scaled(args, ["x": "x", "y": "y"]))
            case "long_press":
                var body = try scaled(args, ["x": "x", "y": "y"])
                body["hold"] = args["seconds"] ?? 1.0
                try post("/tap", body)
            case "swipe":
                var body = try scaled(args, ["x1": "x1", "y1": "y1", "x2": "x2", "y2": "y2"])
                body["duration"] = args["seconds"] ?? 0.3
                try post("/swipe", body)
            case "type_text":
                try post("/type", ["text": args["text"] ?? ""])
            case "press_key":
                try post("/key", ["key": args["key"] ?? "", "modifiers": args["modifiers"] ?? []])
            case "home":
                try post("/home", [:])
            default:
                return failure("unknown tool \(name)")
            }
            Thread.sleep(forTimeInterval: 0.6)
            return try screenshot()
        } catch {
            return failure("\(error)")
        }
    }

    private static func screenshot() throws -> [String: Any] {
        let status = try get("/status")
        guard let screen = (try JSONSerialization.jsonObject(with: status.0) as? [String: Any])?["screen"]
            as? [String: Any], let width = screen["width"] as? Double, let height = screen["height"] as? Double
        else { throw MCPError("no iPhone screen: plug the iPhone in over USB and unlock it") }
        let scale = min(1, longEdge / max(width, height))
        let (image, _) = try get("/screenshot?maxWidth=\(Int((width * scale).rounded()))")
        let size = "\(Int((width * scale).rounded()))x\(Int((height * scale).rounded()))"
        return [
            "content": [
                ["type": "image", "data": image.base64EncodedString(), "mimeType": "image/jpeg"],
                ["type": "text", "text": "Screenshot \(size) px. Use these pixels for tap and swipe."],
            ]
        ]
    }

    /// Adds the scaled screenshot size so the app maps coordinates back to the full screen.
    private static func scaled(_ args: [String: Any], _ keys: [String: String]) throws -> [String: Any] {
        let (status, _) = try get("/status")
        guard let screen = (try JSONSerialization.jsonObject(with: status) as? [String: Any])?["screen"]
            as? [String: Any], let width = screen["width"] as? Double, let height = screen["height"] as? Double
        else { throw MCPError("no iPhone screen: plug the iPhone in over USB and unlock it") }
        let scale = min(1, longEdge / max(width, height))
        var body: [String: Any] = ["width": width * scale, "height": height * scale]
        for (from, to) in keys {
            guard let value = args[from] else { throw MCPError("\(from) is required") }
            body[to] = value
        }
        return body
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
