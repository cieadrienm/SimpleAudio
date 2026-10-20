import Foundation

public final class SimpleAudioMCPServer {
    let transport: Transport
    let apiBase: String
    let version: String

    public init(transport: @escaping Transport, apiBase: String = "http://127.0.0.1:17910", version: String = "0.9.0") {
        self.transport = transport
        self.apiBase = apiBase
        self.version = version
    }

    public func run() {
        while let line = readLine(strippingNewline: true) {
            if let response = handle(line: line) { Self.write(response) }
        }
    }

    static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let message = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
        }
        guard let method = message["method"] as? String else { return nil }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        var result: [String: Any]?
        var failure: (code: Int, message: String)?

        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "simpleaudio", "version": version],
                "instructions": "Controls the SimpleAudio macOS audio editor (waveforms, fades, copy-paste, multitrack, multi-format export, OSC). Call simpleaudio_state first; edit live with simpleaudio_edit (one undo step per batch); inspect silences with simpleaudio_silences; export with simpleaudio_export; check visually with simpleaudio_snapshot.",
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": simpleAudioToolDefinitions]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard simpleAudioToolDefinitions.contains(where: { $0["name"] as? String == name }) else {
                failure = (-32602, "unknown tool: \(name)")
                break
            }
            do {
                result = try callTool(name, params["arguments"] as? [String: Any] ?? [:])
            } catch {
                result = ["content": [["type": "text", "text": "\(error)"]], "isError": true]
            }
        default:
            failure = (-32601, "method not found: \(method)")
        }

        if let result { return encode(["jsonrpc": "2.0", "id": id, "result": result]) }
        let f = failure ?? (-32601, "method not found: \(method)")
        return encode(["jsonrpc": "2.0", "id": id, "error": ["code": f.code, "message": f.message]])
    }

    func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func textResult(_ response: APIResponse) -> [String: Any] {
        ["content": [["type": "text", "text": String(decoding: response.data, as: UTF8.self)]], "isError": response.status >= 400]
    }

    func imageResult(_ response: APIResponse, caption: String) -> [String: Any] {
        guard response.status == 200, !response.contentType.lowercased().contains("json") else { return textResult(response) }
        let mime = response.contentType.lowercased().hasPrefix("image/") ? String(response.contentType.split(separator: ";")[0]) : "image/png"
        return [
            "content": [
                ["type": "image", "data": response.data.base64EncodedString(), "mimeType": mime],
                ["type": "text", "text": caption],
            ]
        ]
    }

    func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    func call(_ method: String, _ path: String, body: Any? = nil) throws -> APIResponse {
        try transport(method, "/v1" + path, try body.map(json))
    }

    func callTool(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
        func string(_ key: String) throws -> String {
            guard let v = args[key] as? String, !v.isEmpty else { throw ProxyError.badArguments("missing argument '\(key)'") }
            return v
        }
        func encodedQuery(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .replacingOccurrences(of: "&", with: "%26")
                .replacingOccurrences(of: "+", with: "%2B") ?? value
        }

        switch name {
        case "simpleaudio_state":
            return textResult(try call("GET", "/state"))
        case "simpleaudio_document":
            return textResult(try call("GET", "/document"))
        case "simpleaudio_help":
            return textResult(try call("GET", "/help"))
        case "simpleaudio_edit":
            guard let ops = args["ops"] as? [Any] else { throw ProxyError.badArguments("missing argument 'ops'") }
            var body: [String: Any] = ["ops": ops]
            if let label = args["label"] as? String, !label.isEmpty { body["label"] = label }
            return textResult(try call("POST", "/edit", body: body))
        case "simpleaudio_replace_document":
            guard let document = args["document"] as? [String: Any] else { throw ProxyError.badArguments("missing argument 'document'") }
            let save = (args["save"] as? Bool) == true
            return textResult(try call("PUT", "/document" + (save ? "?save=1" : ""), body: document))
        case "simpleaudio_open":
            return textResult(try call("POST", "/open", body: ["path": try string("path")]))
        case "simpleaudio_import":
            var body: [String: Any] = ["path": try string("path")]
            if let t = args["track"] { body["track"] = t }
            if let at = args["at"] { body["at"] = at }
            return textResult(try call("POST", "/import", body: body))
        case "simpleaudio_export":
            var body: [String: Any] = ["path": try string("path")]
            for k in ["format", "sampleRate", "bitDepth", "bitRateKbps", "channels", "normalization", "range", "stems"] {
                if let v = args[k] { body[k] = v }
            }
            return textResult(try call("POST", "/export", body: body))
        case "simpleaudio_transport":
            let action = try string("action")
            var body: [String: Any] = ["action": action]
            if let t = args["time"] { body["time"] = t }
            if let r = args["range"] { body["range"] = r }
            return textResult(try call("POST", "/transport", body: body))
        case "simpleaudio_select":
            var body: [String: Any] = [:]
            for k in ["clips", "track", "range", "fit"] { if let v = args[k] { body[k] = v } }
            return textResult(try call("POST", "/select", body: body))
        case "simpleaudio_undo":
            return textResult(try call("POST", "/undo"))
        case "simpleaudio_redo":
            return textResult(try call("POST", "/redo"))
        case "simpleaudio_save":
            var body: [String: Any] = [:]
            if let p = args["path"] as? String, !p.isEmpty { body["path"] = p }
            return textResult(try call("POST", "/save", body: body))
        case "simpleaudio_snapshot":
            let response = try call("GET", "/snapshot.png")
            return imageResult(response, caption: "Snapshot of the SimpleAudio window.")
        case "simpleaudio_waveform":
            let path = try string("path")
            var q = "?path=\(encodedQuery(path))"
            if let bins = args["bins"] { q += "&bins=\(bins)" }
            return textResult(try call("GET", "/waveform" + q))
        case "simpleaudio_silences":
            let path = try string("path")
            var q = "?path=\(encodedQuery(path))"
            if let th = args["thresholdDB"] { q += "&thresholdDB=\(th)" }
            if let md = args["minDuration"] { q += "&minDuration=\(md)" }
            return textResult(try call("GET", "/silences" + q))
        default:
            throw ProxyError.badArguments("unknown tool \(name)")
        }
    }
}
