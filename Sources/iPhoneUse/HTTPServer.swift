import Foundation
import Network

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let body: [String: Any]
}

struct HTTPResponse {
    var status: Int = 200
    var contentType = "application/json"
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, body: data)
    }

    static func error(_ message: String, status: Int = 400) -> HTTPResponse {
        json(["error": message], status: status)
    }
}

/// A tiny HTTP/1.1 server on localhost. One request per connection.
final class HTTPServer {
    private let port: NWEndpoint.Port
    private let handler: (HTTPRequest) -> HTTPResponse
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "iphone-use.http", attributes: .concurrent)

    init(port: UInt16, handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.handler = handler
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in log("http \(state)") }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                let response = self.handler(request)
                self.send(response, on: connection)
            } else if done || error != nil || buffer.count > 8 << 20 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        head += "Content-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n"
        for (name, value) in response.headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Nil until the headers and the whole body have arrived.
    private static func parse(_ data: Data) -> HTTPRequest? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)),
            let head = String(data: data[..<split.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].lowercased() == "content-length" {
                length = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = split.upperBound
        guard data.count - bodyStart >= length else { return nil }
        let bodyData = data[bodyStart..<(bodyStart + length)]
        let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]

        let components = URLComponents(string: String(parts[1]))
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return HTTPRequest(
            method: String(parts[0]), path: components?.path ?? String(parts[1]), query: query, body: body)
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 503: "Service Unavailable"
        default: "Error"
        }
    }
}
