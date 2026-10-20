import Foundation
import SimpleAudioMCPCore

let base = apiBaseURL()
let server = SimpleAudioMCPServer(transport: urlSessionTransport(base: base), apiBase: base)
server.run()
