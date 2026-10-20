import Darwin
import Foundation

final class APIEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [Int32] = []

    deinit {
        closeAll()
    }

    func addClient(fd: Int32) {
        lock.lock()
        clients.append(fd)
        lock.unlock()
    }

    func broadcast(event: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes]) else { return }
        let jsonStr = String(decoding: data, as: UTF8.self)
        let message = Data("event: \(event)\ndata: \(jsonStr)\n\n".utf8)

        lock.lock()
        var alive: [Int32] = []
        for fd in clients {
            if HTTPServer.writeAll(fd: fd, data: message) {
                alive.append(fd)
            } else {
                Darwin.close(fd)
            }
        }
        clients = alive
        lock.unlock()
    }

    func closeAll() {
        lock.lock()
        for fd in clients {
            Darwin.close(fd)
        }
        clients.removeAll()
        lock.unlock()
    }
}
