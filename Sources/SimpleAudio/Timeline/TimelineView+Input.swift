import AppKit
import SimpleAudioCore

extension TimelineView {
    enum Hit: Equatable {
        case cornerMag
        case overview
        case ruler
        case marker(UUID)
        case header(HeaderControl)
        case rangeEdge(Edge)
        case fadeHandle(clipID: UUID, isIn: Bool)
        case clipEdge(clipID: UUID, edge: Edge)
        case clipBody(clipID: UUID, trackID: UUID)
        case pianoKey(trackID: UUID, pitch: Int)
        case noteEdge(noteID: UUID, edge: Edge)
        case noteBody(noteID: UUID, trackID: UUID)
        case emptyLane(trackID: UUID?)
    }

    func hit(at point: CGPoint) -> Hit {
        let p = project

        // Top-left corner
        if point.x < Metrics.headerWidth && point.y < Metrics.topBarHeight {
            if point.y >= Metrics.overviewHeight && point.x < 46 {
                return .cornerMag
            }
            return .emptyLane(trackID: nil)
        }

        // Overview minimap
        if overviewArea.contains(point) {
            return .overview
        }

        // Ruler & Markers
        if rulerArea.contains(point) {
            for marker in p.markers.reversed() {
                let mx = x(for: marker.time)
                let pill = CGRect(x: mx - 3, y: rulerArea.minY, width: 56, height: rulerArea.height)
                if pill.contains(point) {
                    return .marker(marker.id)
                }
            }
            return .ruler
        }

        let rows = trackRows(for: p)

        // Track headers (left column)
        if point.x < Metrics.headerWidth {
            if let row = rows.first(where: { $0.rect.minY <= point.y && point.y < $0.rect.maxY }) {
                let isMIDI = row.track.isMIDI
                let c = headerControlRects(in: row.rect, isMIDI: isMIDI)
                if c.mute.insetBy(dx: -2, dy: -2).contains(point) { return .header(.mute(row.track.id)) }
                if c.solo.insetBy(dx: -2, dy: -2).contains(point) { return .header(.solo(row.track.id)) }
                if c.third.insetBy(dx: -2, dy: -2).contains(point) {
                    return isMIDI ? .header(.pianoRoll(row.track.id)) : .header(.stereoSplit(row.track.id))
                }
                let minHForPills: CGFloat = isMIDI ? 66 : 54
                if row.rect.height >= minHForPills {
                    if c.gain.contains(point) { return .header(.gain(row.track.id)) }
                    if c.pan.contains(point) { return .header(.pan(row.track.id)) }
                }
                return .header(.title(row.track.id))
            }
            return .emptyLane(trackID: nil)
        }

        // Piano keyboard strip on the left edge of expanded MIDI lane
        if let row = rows.first(where: { $0.rect.minY <= point.y && point.y < $0.rect.maxY }),
           row.track.isMIDI,
           row.showPianoKeys,
           point.x < Metrics.headerWidth + Metrics.pianoKeysWidth {
            let pVal = pitch(forY: point.y, in: row)
            return .pianoKey(trackID: row.track.id, pitch: pVal)
        }

        // Selection range edges in lanes
        if let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-5 {
            let x0 = x(for: range.lowerBound)
            let x1 = x(for: range.upperBound)
            if abs(point.x - x0) <= Metrics.rangeHandleHit {
                return .rangeEdge(.start)
            }
            if abs(point.x - x1) <= Metrics.rangeHandleHit {
                return .rangeEdge(.end)
            }
        }

        guard let row = rows.first(where: { $0.rect.minY <= point.y && point.y < $0.rect.maxY }) else {
            return .emptyLane(trackID: nil)
        }

        if row.track.isMIDI {
            for note in row.track.notes.reversed() {
                let rect = noteRect(note, in: row)
                let expanded = rect.insetBy(dx: -Metrics.edgeOutside, dy: -1.5)
                guard expanded.contains(point) else { continue }

                let insideEdge = min(Metrics.edgeInside, max(rect.width * 0.25, 2.5))
                if point.x <= rect.minX + insideEdge {
                    return .noteEdge(noteID: note.id, edge: .start)
                }
                if point.x >= rect.maxX - insideEdge {
                    return .noteEdge(noteID: note.id, edge: .end)
                }
                return .noteBody(noteID: note.id, trackID: row.track.id)
            }
        } else {
            // Check clips in this track row
            for clip in row.track.clips.reversed() {
                let rect = clipRect(clip, in: row.rect)
                let handles = fadeHandleCenters(for: clip, in: row.rect)
                if hypot(point.x - handles.fadeIn.x, point.y - handles.fadeIn.y) <= Metrics.fadeHit {
                    return .fadeHandle(clipID: clip.id, isIn: true)
                }
                if hypot(point.x - handles.fadeOut.x, point.y - handles.fadeOut.y) <= Metrics.fadeHit {
                    return .fadeHandle(clipID: clip.id, isIn: false)
                }

                let expanded = rect.insetBy(dx: -Metrics.edgeOutside, dy: 0)
                guard expanded.contains(point) else { continue }

                let insideEdge = min(Metrics.edgeInside, max(rect.width * 0.25, 3))
                if point.x <= rect.minX + insideEdge {
                    return .clipEdge(clipID: clip.id, edge: .start)
                }
                if point.x >= rect.maxX - insideEdge {
                    return .clipEdge(clipID: clip.id, edge: .end)
                }
                if rect.contains(point) {
                    return .clipBody(clipID: clip.id, trackID: row.track.id)
                }
            }
        }

        return .emptyLane(trackID: row.track.id)
    }

    func cursor(for hit: Hit, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) -> TimelineCursor {
        switch hit {
        case .cornerMag, .header(.mute), .header(.solo), .header(.stereoSplit), .header(.pianoRoll), .marker, .overview, .pianoKey:
            return .pointing
        case .header(.title):
            return project.tracks.count > 1 ? .openHand : .pointing
        case .header(.gain):
            return .resizeHorizontal
        case .header(.pan):
            return .resizeHorizontal
        case .ruler:
            return .ibeam
        case .rangeEdge:
            return .resizeHorizontal
        case .fadeHandle:
            return .fade
        case .clipEdge(_, let edge), .noteEdge(_, let edge):
            return edge == .start ? .trimLeft : .trimRight
        case .clipBody:
            if modifiers.contains(.shift) {
                return .ibeam
            }
            if modifiers.contains(.option) {
                return .slip
            }
            return .openHand
        case .noteBody:
            return modifiers.contains(.shift) ? .ibeam : .openHand
        case .emptyLane:
            return .ibeam
        }
    }

    func applyCursor(_ cursor: TimelineCursor) {
        currentCursor = cursor
        cursor.nsCursor.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: currentCursor.nsCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor.nsCursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        lastMouse = pt
        updateHover(at: pt, modifiers: event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        lastMouse = nil
        if hoveredClip != nil || hoveredNote != nil || hoverHit != nil {
            hoveredClip = nil
            hoveredNote = nil
            hoverHit = nil
            needsDisplay = true
        }
        applyCursor(.arrow)
    }

    override func flagsChanged(with event: NSEvent) {
        if let pt = lastMouse {
            updateHover(at: pt, modifiers: event.modifierFlags)
        }
    }

    private func updateHover(at pt: CGPoint, modifiers: NSEvent.ModifierFlags) {
        let h = hit(at: pt)
        let newClip: UUID?
        let newNote: UUID?
        switch h {
        case .clipBody(let id, _), .clipEdge(let id, _), .fadeHandle(let id, _):
            newClip = id
            newNote = nil
        case .noteBody(let id, _), .noteEdge(let id, _):
            newClip = nil
            newNote = id
        default:
            newClip = nil
            newNote = nil
        }
        if newClip != hoveredClip || newNote != hoveredNote || h != hoverHit {
            hoveredClip = newClip
            hoveredNote = newNote
            hoverHit = h
            needsDisplay = true
        }
        applyCursor(cursor(for: h, modifiers: modifiers))
    }

    // MARK: Mouse Down / Dragged / Up

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        lastMouse = pt
        let h = hit(at: pt)
        let p = model.store.project

        switch h {
        case .cornerMag:
            model.snapping.toggle()
            needsDisplay = true

        case .overview:
            let clickedTime = overviewTime(for: pt.x)
            let visibleSpan = Double(max(laneWidth - Metrics.leadIn - Metrics.endMargin, 10)) * secondsPerPoint
            if clickedTime >= scrollOffset && clickedTime <= scrollOffset + visibleSpan {
                drag = .overviewPan(grabOffset: clickedTime - scrollOffset)
            } else {
                scrollOffset = max(0, clickedTime - visibleSpan * 0.5)
                clampScroll()
                model.seek(to: clickedTime)
                drag = .overviewPan(grabOffset: visibleSpan * 0.5)
                refresh()
            }

        case .marker(let id):
            model.selectedMarkerID = id
            if let marker = p.markers.first(where: { $0.id == id }) {
                model.statusMessage = L(
                    "Marqueur « \(marker.name) » sélectionné (Z : zoom 15s / zone / piste entière)",
                    "Marker “\(marker.name)” selected (Z: zoom 15s / section / full project)"
                )
                if event.clickCount == 2 {
                    model.seek(to: marker.time)
                    return
                }
                let grab = time(for: pt.x) - marker.time
                drag = .marker(markerID: id, grab: grab, originalTime: marker.time)
            }
            needsDisplay = true

        case .ruler:
            model.selectedMarkerID = nil
            if event.clickCount == 2 {
                let t = max(0, time(for: pt.x))
                model.seek(to: t)
                model.addMarkerAtPlayhead()
                return
            }
            if event.modifierFlags.contains(.shift) {
                let t = max(0, time(for: pt.x))
                model.selectionRange = t...t
                drag = .rangeSelect(originTime: t, trackID: nil)
                needsDisplay = true
            } else {
                drag = .scrub
                scrub(at: pt.x)
            }

        case .header(let ctrl):
            handleHeaderMouseDown(ctrl, point: pt, event: event)

        case .pianoKey(let trackID, let pitch):
            model.selectedTrackID = trackID
            if let ti = p.trackIndex(of: trackID) {
                let track = p.tracks[ti]
                model.engine.previewNote(pitch: pitch, velocity: 100, program: track.program, isDrum: track.isDrum || track.channel == 9)
                model.statusMessage = L("Clavier : \(GeneralMIDI.noteName(pitch)) (MIDI \(pitch))", "Keyboard: \(GeneralMIDI.noteName(pitch)) (MIDI \(pitch))")
            }

        case .rangeEdge(let edge):
            guard let range = model.selectionRange else { return }
            let other = edge == .start ? range.upperBound : range.lowerBound
            drag = .rangeEdge(edge: edge, otherBound: other)
            applyCursor(.resizeHorizontal)

        case .fadeHandle(let clipID, let isIn):
            guard let (ti, ci) = p.clipLocation(of: clipID) else { return }
            let clip = p.tracks[ti].clips[ci]
            guard !p.tracks[ti].locked else { return }
            model.selectedClips = [clipID]
            model.selectedNotes.removeAll()
            model.selectedTrackID = p.tracks[ti].id
            let edgeTime = isIn ? (clip.offset + clip.fadeIn) : (clip.end - clip.fadeOut)
            drag = .fade(clipID: clipID, isIn: isIn, grab: time(for: pt.x) - edgeTime, original: clip)
            applyCursor(.fade)
            needsDisplay = true

        case .clipEdge(let clipID, let edge):
            guard let (ti, ci) = p.clipLocation(of: clipID) else { return }
            let clip = p.tracks[ti].clips[ci]
            guard !p.tracks[ti].locked else { return }
            model.selectedClips = [clipID]
            model.selectedNotes.removeAll()
            model.selectedTrackID = p.tracks[ti].id
            let edgeTime = edge == .start ? clip.offset : clip.end
            drag = .trim(clipID: clipID, edge: edge, grab: time(for: pt.x) - edgeTime, original: clip)
            applyCursor(edge == .start ? .trimLeft : .trimRight)
            needsDisplay = true

        case .clipBody(let clipID, let trackID):
            model.selectedTrackID = trackID
            model.selectedNotes.removeAll()
            if event.clickCount == 2 {
                if let (ti, ci) = p.clipLocation(of: clipID) {
                    let clip = p.tracks[ti].clips[ci]
                    model.selectedClips = [clipID]
                    model.selectionRange = clip.offset...clip.end
                    needsDisplay = true
                }
                return
            }
            if event.modifierFlags.contains(.shift) {
                let t = max(0, time(for: pt.x))
                model.selectionRange = t...t
                drag = .rangeSelect(originTime: t, trackID: trackID)
                applyCursor(.ibeam)
                needsDisplay = true
                return
            }
            if event.modifierFlags.contains(.command) {
                if model.selectedClips.contains(clipID) {
                    model.selectedClips.remove(clipID)
                } else {
                    model.selectedClips.insert(clipID)
                }
            } else if !model.selectedClips.contains(clipID) {
                model.selectedClips = [clipID]
            }
            guard let (ti, ci) = p.clipLocation(of: clipID), !p.tracks[ti].locked else {
                needsDisplay = true
                return
            }
            let clip = p.tracks[ti].clips[ci]
            let slip = event.modifierFlags.contains(.option)
            drag = .press(
                clipID: clipID,
                trackID: trackID,
                start: pt,
                grab: time(for: pt.x) - clip.offset,
                slip: slip
            )
            needsDisplay = true

        case .noteEdge(let noteID, let edge):
            guard let (ti, ni) = p.noteLocation(of: noteID), !p.tracks[ti].locked else { return }
            let note = p.tracks[ti].notes[ni]
            model.selectedNotes = [noteID]
            model.selectedClips.removeAll()
            model.selectedTrackID = p.tracks[ti].id
            let edgeTime = edge == .start ? note.start : note.end
            drag = .trimNote(noteID: noteID, edge: edge, grabTime: time(for: pt.x) - edgeTime, originalNote: note)
            applyCursor(edge == .start ? .trimLeft : .trimRight)
            needsDisplay = true

        case .noteBody(let noteID, let trackID):
            model.selectedTrackID = trackID
            model.selectedClips.removeAll()
            guard let (ti, ni) = p.noteLocation(of: noteID) else { return }
            let track = p.tracks[ti]
            let note = track.notes[ni]

            model.engine.previewNote(
                pitch: note.pitch + ((track.isDrum || track.channel == 9) ? 0 : track.transpose),
                velocity: note.velocity,
                program: track.program,
                isDrum: track.isDrum || track.channel == 9
            )

            if event.clickCount == 2 {
                model.selectedNotes = [noteID]
                model.selectionRange = note.start...note.end
                needsDisplay = true
                return
            }
            if event.modifierFlags.contains(.shift) {
                let t = max(0, time(for: pt.x))
                model.selectionRange = t...t
                drag = .rangeSelect(originTime: t, trackID: trackID)
                applyCursor(.ibeam)
                needsDisplay = true
                return
            }
            if event.modifierFlags.contains(.command) {
                if model.selectedNotes.contains(noteID) {
                    model.selectedNotes.remove(noteID)
                } else {
                    model.selectedNotes.insert(noteID)
                }
            } else if !model.selectedNotes.contains(noteID) {
                model.selectedNotes = [noteID]
            }
            guard !track.locked else {
                needsDisplay = true
                return
            }
            drag = .pressNote(
                noteID: noteID,
                trackID: trackID,
                startPoint: pt,
                grabTime: time(for: pt.x) - note.start,
                originalNote: note
            )
            needsDisplay = true

        case .emptyLane(let trackID):
            if let trackID {
                model.selectedTrackID = trackID
            }
            if (event.clickCount == 2 || event.modifierFlags.contains(.option)),
               let row = trackRow(at: pt, for: p),
               row.track.isMIDI,
               !row.track.locked {
                let rawStart = max(0, time(for: pt.x))
                let targets = snapTargets(in: p)
                let (snappedStart, _) = snap(rawStart, targets: targets)
                let clickedPitch = pitch(forY: pt.y, in: row)
                let defaultDur = max(0.15, p.secondsPerBeat * 0.5)
                var createdID: UUID?
                model.store.perform(L("Créer une note (\(GeneralMIDI.noteName(clickedPitch)))", "Create Note (\(GeneralMIDI.noteName(clickedPitch)))")) { proj in
                    createdID = proj.addNote(
                        toTrack: row.track.id,
                        pitch: clickedPitch,
                        start: snappedStart,
                        duration: defaultDur,
                        velocity: 100
                    )
                }
                if let createdID {
                    model.selectedNotes = [createdID]
                    model.selectedClips.removeAll()
                    model.engine.previewNote(
                        pitch: clickedPitch + ((row.track.isDrum || row.track.channel == 9) ? 0 : row.track.transpose),
                        velocity: 100,
                        program: row.track.program,
                        isDrum: row.track.isDrum || row.track.channel == 9
                    )
                }
                return
            }

            if !event.modifierFlags.contains(.command) {
                model.selectedClips.removeAll()
                model.selectedNotes.removeAll()
                model.selectedMarkerID = nil
            }
            let t = max(0, time(for: pt.x))
            model.seek(to: t)
            model.selectionRange = nil
            drag = .rangeSelect(originTime: t, trackID: trackID)
            applyCursor(.ibeam)
            needsDisplay = true
        }
    }

    private func handleHeaderMouseDown(_ ctrl: HeaderControl, point: CGPoint, event: NSEvent) {
        let p = model.store.project
        switch ctrl {
        case .mute(let id):
            model.selectedTrackID = id
            model.toggleTrackMute(id)
        case .solo(let id):
            model.selectedTrackID = id
            model.toggleTrackSolo(id)
        case .stereoSplit(let id):
            model.selectedTrackID = id
            model.toggleTrackStereoSplit(id)
        case .pianoRoll(let id):
            model.selectedTrackID = id
            model.toggleTrackPianoRoll(id)
        case .gain(let id):
            model.selectedTrackID = id
            guard let ti = p.trackIndex(of: id) else { return }
            if event.clickCount == 2 {
                model.setTrackGain(id, gainDB: 0)
                return
            }
            drag = .trackGain(trackID: id, startY: point.y, originalDB: p.tracks[ti].gainDB)
        case .pan(let id):
            model.selectedTrackID = id
            guard let ti = p.trackIndex(of: id) else { return }
            if event.clickCount == 2 {
                model.setTrackPan(id, pan: 0)
                return
            }
            drag = .trackPan(trackID: id, startX: point.x, originalPan: p.tracks[ti].pan)
        case .title(let id):
            model.selectedTrackID = id
            if event.clickCount == 2, let ti = p.trackIndex(of: id), p.tracks[ti].isMIDI {
                model.toggleTrackPianoRoll(id)
                return
            }
            if p.tracks.count > 1 {
                drag = .pressTrack(trackID: id, startY: point.y)
            }
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        lastMouse = pt
        let base = model.store.project

        switch drag {
        case .none:
            break

        case .overviewPan(let grabOffset):
            let t = overviewTime(for: pt.x)
            scrollOffset = max(0, t - grabOffset)
            clampScroll()
            refresh()

        case .scrub:
            scrub(at: pt.x)

        case .marker(let markerID, let grab, _):
            let rawTime = max(0, time(for: pt.x) - grab)
            let targets = snapTargets(in: base)
            let (snappedTime, guide) = snap(rawTime, targets: targets)
            snapGuide = guide
            stage(L("Déplacer le marqueur", "Move Marker"), on: base) { proj in
                try? Operations.moveMarker(&proj, id: markerID, to: snappedTime)
            }
            showTip(TimeFormat.timecode(snappedTime), at: pt)

        case .rangeSelect(let originTime, _):
            let rawTime = max(0, time(for: pt.x))
            if abs(pt.x - x(for: originTime)) >= Metrics.dragThreshold {
                let targets = snapTargets(in: base)
                let (snapped, guide) = snap(rawTime, targets: targets)
                snapGuide = guide
                let a = min(originTime, snapped)
                let b = max(originTime, snapped)
                model.selectionRange = a...b
                showTip("\(TimeFormat.timecode(a)) → \(TimeFormat.timecode(b)) (\(TimeFormat.shortDuration(b - a)))", at: pt)
                needsDisplay = true
            }

        case .rangeEdge(let edge, let otherBound):
            let rawTime = max(0, time(for: pt.x))
            let targets = snapTargets(in: base)
            let (snapped, guide) = snap(rawTime, targets: targets)
            snapGuide = guide
            let a = min(otherBound, snapped)
            let b = max(otherBound, snapped)
            model.selectionRange = a...b
            let currentEdge = edge == .start ? a : b
            showTip(L("Plage \(TimeFormat.timecode(currentEdge)) (\(TimeFormat.shortDuration(b - a)))", "Range \(TimeFormat.timecode(currentEdge)) (\(TimeFormat.shortDuration(b - a)))"), at: pt)
            needsDisplay = true

        case .press(let clipID, let trackID, let start, let grab, let slip):
            guard hypot(pt.x - start.x, pt.y - start.y) >= Metrics.dragThreshold,
                  let (ti, ci) = base.clipLocation(of: clipID) else { return }
            let clip = base.tracks[ti].clips[ci]
            if slip {
                drag = .slip(clipID: clipID, grab: time(for: start.x), original: clip)
                applyCursor(.slip)
            } else {
                drag = .move(
                    clipID: clipID,
                    grab: grab,
                    originalOffset: clip.offset,
                    originalTrackID: trackID,
                    current: pt
                )
                applyCursor(.closedHand)
            }
            mouseDragged(with: event)

        case .move(let clipID, let grab, _, let originalTrackID, _):
            guard let (ti, ci) = base.clipLocation(of: clipID) else { return }
            let clip = base.tracks[ti].clips[ci]
            let rawStart = max(0, time(for: pt.x) - grab)
            let targets = snapTargets(in: base, excludingClip: clipID)
            let (snappedStart, guide) = snapSpan(start: rawStart, duration: clip.duration, targets: targets)
            snapGuide = guide

            let hoveredTrack = trackRow(at: pt, for: base)?.track
            let targetTrackID = (hoveredTrack != nil && !hoveredTrack!.isMIDI) ? hoveredTrack!.id : originalTrackID
            drag = .move(
                clipID: clipID,
                grab: grab,
                originalOffset: clip.offset,
                originalTrackID: originalTrackID,
                current: pt
            )
            stage(L("Déplacer le clip", "Move Clip"), on: base) { proj in
                try? Operations.moveClip(&proj, id: clipID, toTrack: targetTrackID, offset: snappedStart)
            }
            showTip("\(TimeFormat.timecode(snappedStart))", at: pt)

        case .slip(let clipID, let grab, let original):
            let dt = time(for: pt.x) - grab
            let maxStart = max(0, original.sourceDuration - original.duration)
            let newSourceStart = min(max(0, original.sourceStart - dt), maxStart)
            stage(L("Glisser la source", "Slip Source"), on: base) { proj in
                try? Operations.slipClip(&proj, id: clipID, toSourceStart: newSourceStart)
            }
            showTip("Source \(TimeFormat.timecode(newSourceStart))", at: pt)

        case .trim(let clipID, let edge, let grab, let original):
            let rawEdge = max(0, time(for: pt.x) - grab)
            let targets = snapTargets(in: base, excludingClip: clipID)
            let (snappedEdge, guide) = snap(rawEdge, targets: targets)
            snapGuide = guide

            switch edge {
            case .start:
                let minOffset = max(0, original.offset - original.sourceStart)
                let maxOffset = original.end - AudioClip.minDuration
                let clampedOffset = min(max(snappedEdge, minOffset), maxOffset)
                let delta = clampedOffset - original.offset
                let newSourceStart = original.sourceStart + delta
                let newDuration = original.duration - delta
                stage(L("Rogner l'entrée", "Trim In"), on: base) { proj in
                    try? Operations.trimClip(
                        &proj,
                        id: clipID,
                        offset: clampedOffset,
                        sourceStart: newSourceStart,
                        duration: newDuration
                    )
                }
                showTip(L("Entrée \(TimeFormat.timecode(clampedOffset)) (\(TimeFormat.shortDuration(newDuration)))", "In \(TimeFormat.timecode(clampedOffset)) (\(TimeFormat.shortDuration(newDuration)))"), at: pt)

            case .end:
                let minEnd = original.offset + AudioClip.minDuration
                let maxEnd = original.offset + (original.sourceDuration - original.sourceStart)
                let clampedEnd = min(max(snappedEdge, minEnd), maxEnd)
                let newDuration = clampedEnd - original.offset
                stage(L("Rogner la sortie", "Trim Out"), on: base) { proj in
                    try? Operations.trimClip(
                        &proj,
                        id: clipID,
                        offset: original.offset,
                        sourceStart: original.sourceStart,
                        duration: newDuration
                    )
                }
                showTip(L("Sortie \(TimeFormat.timecode(clampedEnd)) (\(TimeFormat.shortDuration(newDuration)))", "Out \(TimeFormat.timecode(clampedEnd)) (\(TimeFormat.shortDuration(newDuration)))"), at: pt)
            }

        case .fade(let clipID, let isIn, let grab, let original):
            let t = time(for: pt.x) - grab
            let rawLength = isIn ? (t - original.offset) : (original.end - t)
            let maxLength = isIn
                ? max(0, original.duration - original.fadeOut)
                : max(0, original.duration - original.fadeIn)
            let length = min(max(0, rawLength), maxLength)
            stage(isIn ? L("Fondu d'entrée", "Fade In") : L("Fondu de sortie", "Fade Out"), on: base) { proj in
                try? Operations.setFade(
                    &proj,
                    id: clipID,
                    fadeIn: isIn ? length : nil,
                    fadeOut: isIn ? nil : length
                )
            }
            let label = isIn ? L("Fondu d'entrée", "Fade In") : L("Fondu de sortie", "Fade Out")
            showTip("\(label) \(TimeFormat.shortDuration(length)) (\(original.fadeShape.label))", at: pt)

        case .pressNote(let noteID, let trackID, let startPoint, let grabTime, let originalNote):
            guard hypot(pt.x - startPoint.x, pt.y - startPoint.y) >= Metrics.dragThreshold else { return }
            drag = .moveNote(
                noteID: noteID,
                trackID: trackID,
                grabTime: grabTime,
                originalNote: originalNote,
                lastPreviewPitch: originalNote.pitch
            )
            applyCursor(.closedHand)
            mouseDragged(with: event)

        case .moveNote(let noteID, let trackID, let grabTime, let originalNote, let lastPreviewPitch):
            let rawStart = max(0, time(for: pt.x) - grabTime)
            let targets = snapTargets(in: base, excludingNote: noteID)
            let (snappedStart, guide) = snap(rawStart, targets: targets)
            snapGuide = guide

            let rows = trackRows(for: base)
            let currentRow = rows.first { $0.track.id == trackID }
            let newPitch = currentRow.map { pitch(forY: pt.y, in: $0) } ?? originalNote.pitch

            if newPitch != lastPreviewPitch, let tr = currentRow?.track {
                model.engine.previewNote(
                    pitch: newPitch + ((tr.isDrum || tr.channel == 9) ? 0 : tr.transpose),
                    velocity: originalNote.velocity,
                    program: tr.program,
                    isDrum: tr.isDrum || tr.channel == 9,
                    duration: 0.14
                )
                drag = .moveNote(
                    noteID: noteID,
                    trackID: trackID,
                    grabTime: grabTime,
                    originalNote: originalNote,
                    lastPreviewPitch: newPitch
                )
            }

            stage(L("Déplacer la note", "Move Note"), on: base) { proj in
                proj.moveNote(noteID, toStart: snappedStart, pitch: newPitch)
            }
            let bb = base.barBeat(forSeconds: snappedStart)
            showTip(L(
                "\(GeneralMIDI.noteName(newPitch)) (\(newPitch)) · \(TimeFormat.timecode(snappedStart)) · Mes \(bb.bar).\(bb.beat)",
                "\(GeneralMIDI.noteName(newPitch)) (\(newPitch)) · \(TimeFormat.timecode(snappedStart)) · Bar \(bb.bar).\(bb.beat)"
            ), at: pt)

        case .trimNote(let noteID, let edge, let grabTime, let originalNote):
            let rawEdge = max(0, time(for: pt.x) - grabTime)
            let targets = snapTargets(in: base, excludingNote: noteID)
            let (snappedEdge, guide) = snap(rawEdge, targets: targets)
            snapGuide = guide

            switch edge {
            case .start:
                let clampedStart = min(max(0, snappedEdge), originalNote.end - MIDINote.minDuration)
                let newDuration = originalNote.end - clampedStart
                stage(L("Rogner le début de la note", "Trim Note Start"), on: base) { proj in
                    proj.trimNote(noteID, start: clampedStart, duration: newDuration)
                }
                showTip(L("Début \(TimeFormat.timecode(clampedStart)) (\(TimeFormat.shortDuration(newDuration)))", "Start \(TimeFormat.timecode(clampedStart)) (\(TimeFormat.shortDuration(newDuration)))"), at: pt)

            case .end:
                let clampedEnd = max(originalNote.start + MIDINote.minDuration, snappedEdge)
                let newDuration = clampedEnd - originalNote.start
                stage(L("Ajuster la durée de la note", "Trim Note Duration"), on: base) { proj in
                    proj.trimNote(noteID, start: originalNote.start, duration: newDuration)
                }
                showTip(L("Durée \(TimeFormat.shortDuration(newDuration))", "Duration \(TimeFormat.shortDuration(newDuration))"), at: pt)
            }

        case .trackGain(let trackID, let startY, let originalDB):
            let dy = startY - pt.y
            let newDB = min(max(originalDB + Double(dy) * 0.2, -60), 24)
            stage(L("Gain de la piste", "Track Gain"), on: base) { proj in
                try? Operations.setTrackGain(&proj, id: trackID, gainDB: newDB)
            }
            showTip("Gain \(TimeFormat.decibels(newDB))", at: pt)

        case .trackPan(let trackID, let startX, let originalPan):
            let dx = pt.x - startX
            let newPan = min(max(originalPan + Double(dx) * 0.015, -1), 1)
            stage(L("Panoramique de la piste", "Track Pan"), on: base) { proj in
                try? Operations.setTrackPan(&proj, id: trackID, pan: newPan)
            }
            showTip("Pan \(TimeFormat.pan(newPan))", at: pt)

        case .pressTrack(let trackID, let startY):
            guard abs(pt.y - startY) >= Metrics.dragThreshold,
                  let initialIdx = base.trackIndex(of: trackID),
                  base.tracks.count > 1 else { return }
            drag = .moveTrack(trackID: trackID, targetIndex: initialIdx)
            applyCursor(.closedHand)
            mouseDragged(with: event)

        case .moveTrack(let trackID, _):
            guard let originalIdx = base.trackIndex(of: trackID), base.tracks.count > 1 else { return }
            let rows = trackRows(for: base)
            var targetIdx = rows.count - 1
            for (idx, row) in rows.enumerated() {
                if pt.y < row.rect.midY {
                    targetIdx = idx
                    break
                }
            }
            drag = .moveTrack(trackID: trackID, targetIndex: targetIdx)
            if targetIdx != originalIdx {
                stage(L("Réordonner la piste", "Reorder Track"), on: base) { proj in
                    proj.moveTrack(trackID, to: targetIdx)
                }
            } else {
                preview = nil
                pendingEdit = nil
                pendingLabel = ""
                model.playback.schedule(project: base)
                refresh()
            }
            let trackName = base.tracks[originalIdx].name
            showTip(L("\(trackName) → piste \(targetIdx + 1)/\(base.tracks.count)", "\(trackName) → track \(targetIdx + 1)/\(base.tracks.count)"), at: CGPoint(x: max(pt.x, Metrics.headerWidth + 44), y: pt.y))
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        lastMouse = pt

        switch drag {
        case .press, .pressNote:
            model.seek(to: max(0, time(for: pt.x)))
        case .marker(_, _, let originalTime) where pendingEdit == nil:
            model.seek(to: originalTime)
        default:
            break
        }

        if let edit = pendingEdit {
            let label = pendingLabel
            preview = nil
            pendingEdit = nil
            pendingLabel = ""
            model.store.perform(label, edit)
        } else {
            preview = nil
        }

        drag = .none
        snapGuide = nil
        hideTip()
        updateHover(at: pt, modifiers: event.modifierFlags)
        refresh()
    }

    private func stage(_ label: String, on base: AudioProject, _ mutate: @escaping (inout AudioProject) -> Void) {
        var copy = base
        mutate(&copy)
        preview = copy
        pendingEdit = mutate
        pendingLabel = label
        model.playback.schedule(project: copy)
        refresh()
    }

    private func scrub(at viewX: CGFloat) {
        let t = min(max(0, time(for: viewX)), contentDuration)
        model.seek(to: t)
        updatePlayhead(t)
    }

    private func showTip(_ text: String, at point: CGPoint) {
        let size = tipView.show(text)
        let x = min(max(Metrics.headerWidth + 4, point.x - size.width / 2), bounds.maxX - size.width - 4)
        let y = max(Metrics.topBarHeight + 4, point.y - size.height - 12)
        tipView.frame = CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
        tipView.isHidden = false
    }

    private func hideTip() {
        tipView.isHidden = true
    }

    // MARK: Scroll & Zoom Gestures

    override func scrollWheel(with event: NSEvent) {
        hideTip()
        let flags = event.modifierFlags
        if flags.contains(.command) || flags.contains(.option) {
            let pt = convert(event.locationInWindow, from: nil)
            let anchorX = max(pt.x, Metrics.headerWidth + Metrics.leadIn)
            let rawDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            let delta = event.hasPreciseScrollingDeltas ? rawDelta : rawDelta * 8
            let factor = exp(delta * 0.012)
            if event.hasPreciseScrollingDeltas {
                elasticZoom(by: factor, around: anchorX, phase: event.phase, momentum: event.momentumPhase)
            } else {
                zoom(by: factor, at: anchorX)
            }
            return
        }

        var dx = event.scrollingDeltaX
        var dy = event.scrollingDeltaY
        if flags.contains(.shift) && abs(dx) < abs(dy) {
            dx = dy
            dy = 0
        }

        guard event.hasPreciseScrollingDeltas else {
            dx *= 10
            dy *= 10
            if abs(dx) > 0.01 {
                scrollOffset -= Double(dx) * secondsPerPoint
            }
            if abs(dy) > 0.01 && project.tracks.count > 1 {
                verticalScroll -= dy
            }
            clampScroll()
            refresh()
            return
        }

        elasticScroll(dx: dx, dy: dy, phase: event.phase, momentum: event.momentumPhase)
    }

    override func magnify(with event: NSEvent) {
        hideTip()
        let pt = convert(event.locationInWindow, from: nil)
        let anchorX = max(pt.x, Metrics.headerWidth + Metrics.leadIn)
        elasticZoom(by: max(0.2, 1 + event.magnification), around: anchorX, phase: event.phase, momentum: [])
    }

    // MARK: Keyboard Navigation & Shortcuts

    override func keyDown(with event: NSEvent) {
        if model.handleKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}
