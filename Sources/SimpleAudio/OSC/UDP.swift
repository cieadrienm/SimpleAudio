import Darwin
import Foundation

final class UDPListener: @unchecked Sendable {
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "net.cieadrienm.simpleaudio.udp", qos: .userInteractive)
    private(set) var port: UInt16 = 0

    deinit {
        stop()
    }

    @discardableResult
    func start(port requestedPort: UInt16, onPacket: @escaping @Sendable (Data) -> Void) -> Bool {
        stop()
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return false }

        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = requestedPort.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0 else {
            Darwin.close(sock)
            return false
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &boundLen)
            }
        }
        self.port = UInt16(bigEndian: boundAddr.sin_port)
        self.fd = sock

        let src = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        src.setEventHandler {
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = Darwin.recv(sock, &buf, buf.count, 0)
                if n <= 0 { break }
                onPacket(Data(buf[0..<n]))
            }
        }
        src.setCancelHandler {
            Darwin.close(sock)
        }
        self.source = src
        src.resume()
        return true
    }

    func stop() {
        if let source {
            source.cancel()
            self.source = nil
            self.fd = -1
        } else if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        port = 0
    }
}

enum UDPSender {
    static func send(_ data: Data, host: String, port: UInt16) {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr(host))

        data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = Darwin.sendto(sock, base, rawBuf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
