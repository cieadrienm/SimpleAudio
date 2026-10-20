import Foundation
import Observation

/// The single write path for the audio document. Every edit from UI, HTTP API, MCP or OSC goes through
/// `perform`, which records a snapshot for undo and bumps `changeCount` so the timeline and audio engine
/// update immediately.
@MainActor
@Observable
public final class DocumentStore {
    public private(set) var project: AudioProject
    /// The `.simpleaudio` project file on disk, or the single opened audio file when editing directly.
    public private(set) var url: URL?
    /// True when `url` is a `.simpleaudio` / `.json` project file, false when opened directly from an audio file.
    public private(set) var isProjectFile = false
    public private(set) var isDirty = false
    /// Increments on every `perform`, `undo`, `redo`, or `replace`.
    public private(set) var changeCount = 0
    public private(set) var lastEditLabel: String?

    private var undoStack: [(label: String, project: AudioProject)] = []
    private var redoStack: [(label: String, project: AudioProject)] = []
    public var undoLimit = 200

    public init(project: AudioProject = AudioProject(), url: URL? = nil, isProjectFile: Bool = false) {
        self.project = project
        self.url = url
        self.isProjectFile = isProjectFile
    }

    public var projectDir: URL? { url?.deletingLastPathComponent() }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoLabel: String? { undoStack.last?.label }
    public var redoLabel: String? { redoStack.last?.label }

    /// Applies an edit as one undoable step. A no-op edit records nothing.
    public func perform(_ label: String, _ edit: (inout AudioProject) -> Void) {
        var next = project
        edit(&next)
        guard next != project else { return }
        undoStack.append((label, project))
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        project = next
        lastEditLabel = label
        isDirty = true
        changeCount += 1
    }

    public func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((last.label, project))
        project = last.project
        isDirty = true
        changeCount += 1
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((next.label, project))
        project = next.project
        isDirty = true
        changeCount += 1
    }

    /// Replaces the document wholesale (open, new, revert). Clears undo history.
    public func replace(project: AudioProject, url: URL?, isProjectFile: Bool) {
        self.project = project
        self.url = url
        self.isProjectFile = isProjectFile
        undoStack.removeAll()
        redoStack.removeAll()
        isDirty = false
        lastEditLabel = nil
        changeCount += 1
    }

    public func markSaved(at url: URL, isProjectFile: Bool = true) {
        self.url = url
        self.isProjectFile = isProjectFile
        isDirty = false
    }

    // MARK: Serialization

    public func save(to url: URL) throws {
        let data = try Self.encode(project)
        try data.write(to: url, options: .atomic)
        markSaved(at: url, isProjectFile: true)
    }

    nonisolated public static func encode(_ project: AudioProject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(project)
    }

    nonisolated public static func decode(_ data: Data) throws -> AudioProject {
        try JSONDecoder().decode(AudioProject.self, from: data)
    }
}
