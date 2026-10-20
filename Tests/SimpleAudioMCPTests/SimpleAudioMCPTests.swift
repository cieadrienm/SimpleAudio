import Foundation
import Testing
@testable import SimpleAudioMCPCore

@Suite("SimpleAudioMCP Tests")
struct SimpleAudioMCPTests {
    @Test("MCP JSON-RPC initialize, tools/list, and tools/call routing")
    func testMCPServerRouting() throws {
        var lastMethod = ""
        var lastPath = ""
        let server = SimpleAudioMCPServer(transport: { method, path, body in
            lastMethod = method
            lastPath = path
            if path.hasSuffix("/snapshot.png") {
                return APIResponse(status: 200, data: Data([0x89, 0x50, 0x4E, 0x47]), contentType: "image/png")
            }
            let payload: [String: Any] = ["ok": true, "method": method, "path": path, "bodySize": body?.count ?? 0]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
            return APIResponse(status: 200, data: data, contentType: "application/json")
        })

        // 1. initialize
        let initResp = server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#)
        #expect(initResp?.contains("simpleaudio") == true)

        // 2. tools/list
        let listResp = server.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        #expect(listResp?.contains("simpleaudio_edit") == true)
        #expect(listResp?.contains("simpleaudio_export") == true)

        // 3. tools/call simpleaudio_edit
        let editResp = server.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"simpleaudio_edit","arguments":{"ops":[{"op":"master.gain","db":-2.0}]}}}"#)
        #expect(lastMethod == "POST")
        #expect(lastPath == "/v1/edit")
        #expect(editResp?.contains("/v1/edit") == true)

        // 4. tools/call simpleaudio_snapshot
        let snapResp = server.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"simpleaudio_snapshot","arguments":{}}}"#)
        #expect(lastMethod == "GET")
        #expect(lastPath == "/v1/snapshot.png")
        #expect(snapResp?.contains("\"type\":\"image\"") == true)
    }
}
