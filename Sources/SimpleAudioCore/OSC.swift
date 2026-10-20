import Foundation

public enum OSCArgument: Equatable, Sendable {
    case int(Int32)
    case float(Float)
    case string(String)
    case bool(Bool)
    case color(UInt32)

    public var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .float(let v): return Double(v)
        case .bool(let v): return v ? 1 : 0
        case .string(let s): return Double(s)
        case .color: return nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .int(let v): return Int(v)
        case .float(let v): return Int(v.rounded())
        case .bool(let v): return v ? 1 : 0
        case .string(let s): return Int(s)
        case .color: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let v): return String(v)
        case .float(let v): return String(v)
        default: return nil
        }
    }
}

public struct OSCMessage: Equatable, Sendable {
    public var address: String
    public var arguments: [OSCArgument]

    public init(_ address: String, _ arguments: [OSCArgument] = []) {
        self.address = address
        self.arguments = arguments
    }

    public func double(at index: Int) -> Double? {
        guard arguments.indices.contains(index) else { return nil }
        return arguments[index].doubleValue
    }

    public func int(at index: Int) -> Int? {
        guard arguments.indices.contains(index) else { return nil }
        return arguments[index].intValue
    }

    public func string(at index: Int) -> String? {
        guard arguments.indices.contains(index) else { return nil }
        return arguments[index].stringValue
    }

    public func bool(at index: Int) -> Bool? {
        guard arguments.indices.contains(index) else { return nil }
        switch arguments[index] {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .float(let f): return f != 0
        case .string(let s): return s == "true" || s == "1"
        case .color: return nil
        }
    }

    public func encoded() -> Data {
        var data = Data()
        data.appendOSCString(address)
        var tags = ","
        for a in arguments {
            switch a {
            case .int: tags += "i"
            case .float: tags += "f"
            case .string: tags += "s"
            case .bool(let v): tags += v ? "T" : "F"
            case .color: tags += "r"
            }
        }
        data.appendOSCString(tags)
        for a in arguments {
            switch a {
            case .int(let v): data.appendBigEndian(UInt32(bitPattern: v))
            case .float(let v): data.appendBigEndian(v.bitPattern)
            case .string(let s): data.appendOSCString(s)
            case .color(let v): data.appendBigEndian(v)
            case .bool: break
            }
        }
        return data
    }

    /// Decodes a packet into its messages; bundles are flattened.
    public static func decode(_ data: Data) -> [OSCMessage] {
        let bytes = [UInt8](data)
        var out: [OSCMessage] = []
        decodePacket(bytes[...], into: &out)
        return out
    }

    private static func decodePacket(_ bytes: ArraySlice<UInt8>, into out: inout [OSCMessage]) {
        var reader = OSCReader(bytes: bytes)
        guard let head = reader.string() else { return }
        if head == "#bundle" {
            guard reader.skip(8) else { return }
            while let size = reader.uint32(), size > 0, let element = reader.slice(Int(size)) {
                decodePacket(element, into: &out)
            }
            return
        }
        guard head.hasPrefix("/") else { return }
        guard let tags = reader.string(), tags.hasPrefix(",") else {
            out.append(OSCMessage(head))
            return
        }
        var args: [OSCArgument] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "i": guard let v = reader.uint32() else { return }; args.append(.int(Int32(bitPattern: v)))
            case "f": guard let v = reader.uint32() else { return }; args.append(.float(Float(bitPattern: v)))
            case "s": guard let s = reader.string() else { return }; args.append(.string(s))
            case "r": guard let v = reader.uint32() else { return }; args.append(.color(v))
            case "d":
                guard let hi = reader.uint32(), let lo = reader.uint32() else { return }
                args.append(.float(Float(Double(bitPattern: UInt64(hi) << 32 | UInt64(lo)))))
            case "T": args.append(.bool(true))
            case "F": args.append(.bool(false))
            case "N", "I": break
            default: return
            }
        }
        out.append(OSCMessage(head, args))
    }
}

private struct OSCReader {
    var bytes: ArraySlice<UInt8>

    mutating func string() -> String? {
        guard let end = bytes.firstIndex(of: 0) else { return nil }
        let s = String(decoding: bytes[bytes.startIndex..<end], as: UTF8.self)
        let length = end - bytes.startIndex + 1
        let padded = (length + 3) & ~3
        guard skip(min(padded, bytes.count)) else { return nil }
        return s
    }

    mutating func uint32() -> UInt32? {
        guard bytes.count >= 4 else { return nil }
        let i = bytes.startIndex
        let v = UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
        bytes = bytes.dropFirst(4)
        return v
    }

    mutating func slice(_ n: Int) -> ArraySlice<UInt8>? {
        guard n >= 0, bytes.count >= n else { return nil }
        let s = bytes.prefix(n)
        bytes = bytes.dropFirst(n)
        return s
    }

    mutating func skip(_ n: Int) -> Bool {
        slice(n) != nil
    }
}

private extension Data {
    mutating func appendOSCString(_ s: String) {
        let utf8 = Array(s.utf8)
        append(contentsOf: utf8)
        append(contentsOf: [UInt8](repeating: 0, count: 4 - utf8.count % 4))
    }

    mutating func appendBigEndian(_ v: UInt32) {
        append(contentsOf: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)])
    }
}

public enum OSCCodec {
    public static func encode(_ message: OSCMessage) -> Data {
        message.encoded()
    }

    public static func encodeBundle(_ messages: [OSCMessage], timetag: UInt64 = 1) -> Data {
        var data = Data()
        data.appendOSCString("#bundle")
        data.appendBigEndian(UInt32((timetag >> 32) & 0xffffffff))
        data.appendBigEndian(UInt32(timetag & 0xffffffff))
        for msg in messages {
            let encoded = msg.encoded()
            data.appendBigEndian(UInt32(encoded.count))
            data.append(encoded)
        }
        return data
    }

    public static func decodePacket(_ data: Data) throws -> [OSCMessage] {
        OSCMessage.decode(data)
    }
}
