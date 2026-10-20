import Darwin
import Foundation

struct HTTPRequest: Sendable {
    var method: String
    var rawTarget: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data
}

struct HTTPResponse: Sendable {
    var status: Int
    var contentType: String
    var body: Data

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        .json(["error": message, "status": status], status: status)
    }

    static func png(_ data: Data) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "image/png", body: data)
    }
}

final class HTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse
    typealias SSEHandler = @Sendable (Int32) -> Void

    private var listenFD: Int32 = -1
    private var acceptQueue: DispatchQueue?
    private(set) var port: UInt16 = 0
    private let handler: Handler
    private let sseHandler: SSEHandler?

    init(handler: @escaping Handler, sseHandler: SSEHandler? = nil) {
        self.handler = handler
        self.sseHandler = sseHandler
    }

    deinit {
        stop()
    }

    @discardableResult
    func start(port requestedPort: UInt16) -> Bool {
        stop()
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = requestedPort.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 32) == 0 else {
            Darwin.close(fd)
            return false
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &boundLen)
            }
        }
        self.port = UInt16(bigEndian: boundAddr.sin_port)
        self.listenFD = fd

        let q = DispatchQueue(label: "net.cieadrienm.simpleaudio.http", qos: .userInitiated, attributes: .concurrent)
        self.acceptQueue = q
        q.async { [weak self] in
            self?.acceptLoop(fd: fd)
        }
        return true
    }

    func stop() {
        if listenFD >= 0 {
            Darwin.shutdown(listenFD, SHUT_RDWR)
            Darwin.close(listenFD)
            listenFD = -1
        }
        port = 0
    }

    private func acceptLoop(fd: Int32) {
        while true {
            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(fd, $0, &clientLen)
                }
            }
            if clientFD < 0 { break }
            var yes: Int32 = 1
            setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        guard let req = Self.readRequest(fd: fd) else {
            Darwin.close(fd)
            return
        }
        if req.method == "GET" && (req.path == "/v1/events" || req.path == "/events"), let sseHandler {
            let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
            _ = Self.writeAll(fd: fd, data: Data(header.utf8))
            sseHandler(fd)
            return
        }
        let sem = DispatchSemaphore(value: 0)
        var respBox: HTTPResponse?
        let handler = self.handler
        Task {
            respBox = await handler(req)
            sem.signal()
        }
        sem.wait()
        if let resp = respBox {
            Self.sendResponse(fd: fd, response: resp)
        }
        Darwin.close(fd)
    }

    private static func readRequest(fd: Int32) -> HTTPRequest? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        var headerEndIndex: Int?
        var expectedContentLength = 0

        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])

            if headerEndIndex == nil, let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                headerEndIndex = range.upperBound
                let headerStr = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                for line in headerStr.split(separator: "\r\n").dropFirst() {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                        expectedContentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
            }
            if let end = headerEndIndex, buffer.count >= end + expectedContentLength {
                break
            }
            if buffer.count > 16 * 1024 * 1024 { return nil }
        }

        guard let end = headerEndIndex else { return nil }
        let headerString = String(decoding: buffer[..<(end - 4)], as: UTF8.self)
        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let reqParts = requestLine.split(separator: " ")
        guard reqParts.count >= 2 else { return nil }
        let method = String(reqParts[0]).uppercased()
        let rawTarget = String(reqParts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        let comps = URLComponents(string: "http://localhost" + rawTarget)
        let path = comps?.path ?? rawTarget
        var query: [String: String] = [:]
        for item in comps?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        let bodyEnd = min(buffer.count, end + expectedContentLength)
        let body = end < bodyEnd ? Data(buffer[end..<bodyEnd]) : Data()

        return HTTPRequest(
            method: method,
            rawTarget: rawTarget,
            path: path,
            query: query,
            headers: headers,
            body: body
        )
    }

    private static func sendResponse(fd: Int32, response: HTTPResponse) {
        let statusText: String
        switch response.status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "OK"
        }
        let header = "HTTP/1.1 \(response.status) \(statusText)\r\nContent-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        _ = writeAll(fd: fd, data: Data(header.utf8))
        _ = writeAll(fd: fd, data: response.body)
    }

    @discardableResult
    static func writeAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return true }
            var offset = 0
            while offset < rawBuf.count {
                let n = Darwin.write(fd, base.advanced(by: offset), rawBuf.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }
}
