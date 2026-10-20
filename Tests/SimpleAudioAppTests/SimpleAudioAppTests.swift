import Foundation
import Testing
@testable import SimpleAudio
@testable import SimpleAudioCore

@Suite("SimpleAudioApp Tests")
struct SimpleAudioAppTests {
    @Test("End-to-end SelfTest suite (TimelineView, Waveforms, Fades, Range Edits, Export, API, OSC)")
    @MainActor
    func testEndToEndSelfTest() throws {
        try SelfTest.run()
    }
}
