import AppKit
import SwiftUI

@MainActor
enum Snapshot {
    static func captureMainWindowPNG(model: AppModel, size: CGSize = CGSize(width: 1280, height: 780)) -> Data? {
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width >= 400 }),
           let contentView = window.contentView {
            contentView.layoutSubtreeIfNeeded()
            contentView.displayIfNeeded()
            if let data = renderPNG(of: contentView) {
                return data
            }
        }
        return renderOffscreenPNG(model: model, size: size)
    }

    static func renderOffscreenPNG(model: AppModel, size: CGSize = CGSize(width: 1280, height: 780)) -> Data? {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.background
        let hosting = NSHostingView(rootView: ContentView(model: model))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        return renderPNG(of: hosting)
    }

    static func renderPNG(of view: NSView) -> Data? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    static func runCLISnapshot(outputPath: String, inputPath: String?) -> Never {
        let model = AppModel()
        if let inputPath, !inputPath.isEmpty {
            let url = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                model.open(url)
            } else {
                model.loadHybridDemoProject()
            }
        } else {
            model.loadHybridDemoProject()
        }
        // Highlight a MIDI track + clip + time selection range so the snapshot shows both Audio waveforms & MIDI Piano-Roll
        if let midiTrack = model.store.project.tracks.first(where: \.isMIDI) {
            model.selectedTrackID = midiTrack.id
            if let firstNote = midiTrack.notes.first {
                model.selectedNotes = [firstNote.id]
            }
        } else if let firstClip = model.store.project.allClips.first?.clip {
            model.selectedClips = [firstClip.id]
        }
        model.selectionRange = 1.0...3.0
        model.seek(to: 2.0)

        guard let png = renderOffscreenPNG(model: model) else {
            fputs("snapshot error: failed to render PNG\n", stderr)
            exit(1)
        }
        let outURL = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: outURL, options: .atomic)
            print("Snapshot written to \(outURL.path) (\(png.count) bytes)")
            exit(0)
        } catch {
            fputs("snapshot error: \(error)\n", stderr)
            exit(1)
        }
    }
}
