import Foundation

public let simpleAudioToolDefinitions: [[String: Any]] = [
    [
        "name": "simpleaudio_state",
        "description": "Returns the current state of SimpleAudio: file, dirty, changeCount, playing, time, duration, loopRange, selectionRange, selectedClips, selectedTrack, peakLeft, peakRight, oscInPort, apiPort, undoLabel, redoLabel, version.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simpleaudio_document",
        "description": "Returns the complete AudioProject JSON document (tracks, clips, fades, gains, pan, markers, sampleRate).",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simpleaudio_help",
        "description": "Returns the full HTTP API, batch edit operations, and OSC address reference.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simpleaudio_edit",
        "description": """
        Applies an atomic batch of editing operations to the active SimpleAudio document as ONE undo step.
        Operations (indices are 0-based track/clip indices or UUID strings):
        - {"op":"track.add", "name"?:s, "at"?:i}
        - {"op":"track.remove", "track":i|uuid}
        - {"op":"track.duplicate", "track":i|uuid}
        - {"op":"track.set", "track":i|uuid, "name"?:s, "gainDB"?:n, "pan"?:n, "mute"?:b, "solo"?:b, "locked"?:b, "stereoSplit"?:b}
        - {"op":"clip.add", "track"?:i|uuid, "path":s, "offset"?:n, "sourceStart"?:n, "duration"?:n, "gainDB"?:n, "fadeIn"?:n, "fadeOut"?:n, "fadeShape"?:s}
        - {"op":"clip.trim", "clip":uuid, "start"?:n, "end"?:n}
        - {"op":"clip.move", "clip":uuid, "offset":n, "track"?:i|uuid}
        - {"op":"clip.slip", "clip":uuid, "by":n}
        - {"op":"clip.split", "clip"?:uuid, "at":n}
        - {"op":"clip.remove", "clips":[uuid], "ripple"?:b}
        - {"op":"clip.duplicate", "clips":[uuid]}
        - {"op":"clip.fades", "clip":uuid, "fadeIn"?:n, "fadeOut"?:n, "shape"?:"cosine"|"linear"|"exponential"|"logarithmic"}
        - {"op":"clip.gain", "clip":uuid, "db":n}
        - {"op":"clip.normalize", "clip":uuid, "targetDB"?:n}
        - {"op":"clip.reverse", "clip":uuid, "reversed"?:b}
        - {"op":"clip.mute", "clip":uuid, "mute":b}
        - {"op":"clip.crossfade", "clipA":uuid, "clipB":uuid, "duration"?:n}
        - {"op":"range.cut", "start":n, "end":n, "ripple"?:b}
        - {"op":"range.copy", "start":n, "end":n}
        - {"op":"range.paste", "at":n, "track"?:i|uuid, "ripple"?:b}
        - {"op":"range.delete", "start":n, "end":n, "ripple"?:b}
        - {"op":"range.crop", "start":n, "end":n}
        - {"op":"range.silence", "start":n, "end":n}
        - {"op":"range.fadeIn", "start":n, "end":n, "shape"?:s}
        - {"op":"range.fadeOut", "start":n, "end":n, "shape"?:s}
        - {"op":"marker.add", "name"?:s, "time":n}
        - {"op":"marker.remove", "marker":i|uuid}
        - {"op":"master.gain", "db":n}
        """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "label": ["type": "string", "description": "Optional undo label"],
                "ops": ["type": "array", "items": ["type": "object"], "description": "Operations to apply atomically"],
            ],
            "required": ["ops"],
        ],
    ],
    [
        "name": "simpleaudio_replace_document",
        "description": "Replaces the whole AudioProject JSON as a single undo step.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "document": ["type": "object"],
                "save": ["type": "boolean"],
            ],
            "required": ["document"],
        ],
    ],
    [
        "name": "simpleaudio_open",
        "description": "Opens an audio file (.wav, .aiff, .flac, .m4a, .mp3, .caf…) or a .simpleaudio project file.",
        "inputSchema": [
            "type": "object",
            "properties": ["path": ["type": "string"]],
            "required": ["path"],
        ],
    ],
    [
        "name": "simpleaudio_import",
        "description": "Imports an audio file onto an existing track (or creates a new track when track is omitted).",
        "inputSchema": [
            "type": "object",
            "properties": [
                "path": ["type": "string"],
                "track": ["type": "integer", "description": "0-based track index; omit to create a new track"],
                "at": ["type": "number", "description": "Start time in seconds (default 0)"],
            ],
            "required": ["path"],
        ],
    ],
    [
        "name": "simpleaudio_export",
        "description": "Exports the project (or a time range) to an audio file in wav, aiff, caf, m4a, alac, flac, or mp3 format.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Destination file path"],
                "format": ["type": "string", "enum": ["wav", "aiff", "caf", "m4a", "alac", "flac", "mp3"]],
                "sampleRate": ["type": "number", "description": "44100, 48000, or 96000 (default 48000)"],
                "bitDepth": ["type": "integer", "description": "16, 24, or 32 (default 24)"],
                "bitRateKbps": ["type": "integer", "description": "128, 192, 256, or 320 for m4a/mp3 (default 256)"],
                "channels": ["type": "integer", "description": "1 (mono) or 2 (stereo, default)"],
                "normalization": ["type": "string", "enum": ["none", "peak", "lufs"]],
                "range": ["type": "array", "items": ["type": "number"], "description": "Optional [start, end] in seconds"],
                "stems": ["type": "boolean", "description": "When true, exports one file per track into the directory of path"],
            ],
            "required": ["path"],
        ],
    ],
    [
        "name": "simpleaudio_transport",
        "description": "Controls playback transport: play, pause, toggle, stop, rewind, seek, loop, loopOff.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "action": ["type": "string", "enum": ["play", "pause", "toggle", "stop", "rewind", "seek", "loop", "loopOff"]],
                "time": ["type": "number"],
                "range": ["type": "array", "items": ["type": "number"]],
            ],
            "required": ["action"],
        ],
    ],
    [
        "name": "simpleaudio_select",
        "description": "Selects clips (UUID strings), a track (0-based index), and/or a time range [start, end]; fit=true zooms to fit.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "clips": ["type": "array", "items": ["type": "string"]],
                "track": ["type": "integer"],
                "range": ["type": "array", "items": ["type": "number"]],
                "fit": ["type": "boolean"],
            ],
        ],
    ],
    [
        "name": "simpleaudio_undo",
        "description": "Undoes the last editing operation.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simpleaudio_redo",
        "description": "Redoes the last undone editing operation.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simpleaudio_save",
        "description": "Saves the current project to disk (optionally at a new path).",
        "inputSchema": [
            "type": "object",
            "properties": ["path": ["type": "string"]],
        ],
    ],
    [
        "name": "simpleaudio_snapshot",
        "description": "Captures the SimpleAudio window as a PNG image.",
        "inputSchema": ["type": "object", "properties": [:] as [String: Any]],
    ],
    [
        "name": "simpleaudio_waveform",
        "description": "Returns the peak and RMS envelope of a source file so an agent can inspect amplitude profiles.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "Source path as stored in a clip, or absolute path"],
                "bins": ["type": "integer", "description": "Number of downsampled bins to return (default 200)"],
            ],
            "required": ["path"],
        ],
    ],
    [
        "name": "simpleaudio_silences",
        "description": "Detects silent intervals in a source audio file for clean cuts.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "path": ["type": "string"],
                "thresholdDB": ["type": "number", "description": "dBFS threshold (default -42)"],
                "minDuration": ["type": "number", "description": "Minimum silence duration in seconds (default 0.15)"],
            ],
            "required": ["path"],
        ],
    ],
]
