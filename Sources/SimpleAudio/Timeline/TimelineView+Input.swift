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
                let c = headerControlRects(in: row.rect)
                if c.mute.insetBy(dx: -2, dy: -2).contains(point) { return .header(.mute(row.track.id)) }
                if c.solo.insetBy(dx: -2, dy: -2).contains(point) { return .header(.solo(row.track.id)) }
                if c.stereo.insetBy(dx: -2, dy: -2).contains(point) { return .header(.stereoSplit(row.track.id)) }
                if row.rect.height >= 54 {
                    if c.gain.contains(point) { return .header(.gain(row.track.id)) }
                    if c.pan.contains(point) { return .header(.pan(row.track.id)) }
                }
                return .header(.title(row.track.id))
            }
            return .emptyLane(trackID: nil)
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

        return .emptyLane(trackID: row.track.id)
    }

    func cursor(for hit: Hit, modifiers: NSEvent.ModifierFlags = NSEvent.modifierFlags) -> TimelineCursor {
        switch hit {
        case .cornerMag, .header(.mute), .header(.solo), .header(.stereoSplit), .header(.title), .marker, .overview:
            return .pointing
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
        case .clipEdge(_, let edge):
            return edge == .start ? .trimLeft : .trimRight
        case .clipBody:
            if modifiers.contains(.shift) {
                return .ibeam
            }
            if modifiers.contains(.option) {
                return .slip
            }
            return .openHand
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
        if hoveredClip != nil || hoverHit != nil {
            hoveredClip = nil
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
        switch h {
        case .clipBody(let id, _), .clipEdge(let id, _), .fadeHandle(let id, _):
            newClip = id
        default:
            newClip = nil
        }
        if newClip != hoveredClip || h != hoverHit {
            hoveredClip = newClip
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
            if event.clickCount == 2 {
                if let marker = p.markers.first(where: { $0.id == id }) {
                    model.seek(to: marker.time)
                }
                return
            }
            if let marker = p.markers.first(where: { $0.id == id }) {
                let grab = time(for: pt.x) - marker.time
                drag = .marker(markerID: id, grab: grab, originalTime: marker.time)
            }
            needsDisplay = true

        case .ruler:
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
            model.selectedTrackID = p.tracks[ti].id
            let edgeTime = edge == .start ? clip.offset : clip.end
            drag = .trim(clipID: clipID, edge: edge, grab: time(for: pt.x) - edgeTime, original: clip)
            applyCursor(edge == .start ? .trimLeft : .trimRight)
            needsDisplay = true

        case .clipBody(let clipID, let trackID):
            model.selectedTrackID = trackID
            // Double-click on a clip selects its time range for instant range editing
            if event.clickCount == 2 {
                if let (ti, ci) = p.clipLocation(of: clipID) {
                    let clip = p.tracks[ti].clips[ci]
                    model.selectedClips = [clipID]
                    model.selectionRange = clip.offset...clip.end
                    needsDisplay = true
                }
                return
            }
            // Shift-drag on a clip sweeps out a time range selection (waveform editor style)
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

        case .emptyLane(let trackID):
            if let trackID {
                model.selectedTrackID = trackID
            }
            if !event.modifierFlags.contains(.command) {
                model.selectedClips.removeAll()
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
            stage("Déplacer le marqueur", on: base) { proj in
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
            showTip("Plage \(TimeFormat.timecode(currentEdge)) (\(TimeFormat.shortDuration(b - a)))", at: pt)
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

            let targetTrackID = trackRow(at: pt, for: base)?.track.id ?? originalTrackID
            drag = .move(
                clipID: clipID,
                grab: grab,
                originalOffset: clip.offset,
                originalTrackID: originalTrackID,
                current: pt
            )
            stage("Déplacer le clip", on: base) { proj in
                try? Operations.moveClip(&proj, id: clipID, toTrack: targetTrackID, offset: snappedStart)
            }
            showTip("\(TimeFormat.timecode(snappedStart))", at: pt)

        case .slip(let clipID, let grab, let original):
            let dt = time(for: pt.x) - grab
            let maxStart = max(0, original.sourceDuration - original.duration)
            let newSourceStart = min(max(0, original.sourceStart - dt), maxStart)
            stage("Glisser la source", on: base) { proj in
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
                stage("Rogner l'entrée", on: base) { proj in
                    try? Operations.trimClip(
                        &proj,
                        id: clipID,
                        offset: clampedOffset,
                        sourceStart: newSourceStart,
                        duration: newDuration
                    )
                }
                showTip("Entrée \(TimeFormat.timecode(clampedOffset)) (\(TimeFormat.shortDuration(newDuration)))", at: pt)

            case .end:
                let minEnd = original.offset + AudioClip.minDuration
                let maxEnd = original.offset + (original.sourceDuration - original.sourceStart)
                let clampedEnd = min(max(snappedEdge, minEnd), maxEnd)
                let newDuration = clampedEnd - original.offset
                stage("Rogner la sortie", on: base) { proj in
                    try? Operations.trimClip(
                        &proj,
                        id: clipID,
                        offset: original.offset,
                        sourceStart: original.sourceStart,
                        duration: newDuration
                    )
                }
                showTip("Sortie \(TimeFormat.timecode(clampedEnd)) (\(TimeFormat.shortDuration(newDuration)))", at: pt)
            }

        case .fade(let clipID, let isIn, let grab, let original):
            let t = time(for: pt.x) - grab
            let rawLength = isIn ? (t - original.offset) : (original.end - t)
            let maxLength = isIn
                ? max(0, original.duration - original.fadeOut)
                : max(0, original.duration - original.fadeIn)
            let length = min(max(0, rawLength), maxLength)
            stage(isIn ? "Fondu d'entrée" : "Fondu de sortie", on: base) { proj in
                try? Operations.setFade(
                    &proj,
                    id: clipID,
                    fadeIn: isIn ? length : nil,
                    fadeOut: isIn ? nil : length
                )
            }
            let label = isIn ? "Fondu d'entrée" : "Fondu de sortie"
            showTip("\(label) \(TimeFormat.shortDuration(length)) (\(original.fadeShape.label))", at: pt)

        case .trackGain(let trackID, let startY, let originalDB):
            let dy = startY - pt.y
            let newDB = min(max(originalDB + Double(dy) * 0.2, -60), 24)
            stage("Gain de la piste", on: base) { proj in
                try? Operations.setTrackGain(&proj, id: trackID, gainDB: newDB)
            }
            showTip("Gain \(TimeFormat.decibels(newDB))", at: pt)

        case .trackPan(let trackID, let startX, let originalPan):
            let dx = pt.x - startX
            let newPan = min(max(originalPan + Double(dx) * 0.015, -1), 1)
            stage("Panoramique de la piste", on: base) { proj in
                try? Operations.setTrackPan(&proj, id: trackID, pan: newPan)
            }
            showTip("Pan \(TimeFormat.pan(newPan))", at: pt)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        lastMouse = pt

        // If user clicked a clip without dragging, also move playhead to click position
        if case .press = drag {
            model.seek(to: max(0, time(for: pt.x)))
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
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let pt = convert(event.locationInWindow, from: nil)
            let anchorX = max(pt.x, Metrics.headerWidth + Metrics.leadIn)
            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            let factor = pow(1.015, delta)
            zoom(by: factor, at: anchorX)
            return
        }

        var dx = event.scrollingDeltaX
        var dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas {
            dx *= 10
            dy *= 10
        }
        if event.modifierFlags.contains(.shift) && abs(dx) < abs(dy) {
            dx = dy
            dy = 0
        }
        if abs(dx) > 0.01 {
            scrollOffset -= Double(dx) * secondsPerPoint
        }
        if abs(dy) > 0.01 && project.tracks.count > 1 {
            verticalScroll -= dy
        }
        clampScroll()
        refresh()
    }

    override func magnify(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let anchorX = max(pt.x, Metrics.headerWidth + Metrics.leadIn)
        zoom(by: max(0.2, 1 + event.magnification), at: anchorX)
    }

    // MARK: Keyboard Navigation & Shortcuts

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case 49: // Space
            model.togglePlay()
            return
        case 51, 117: // Delete / Forward Delete
            model.deleteSelection(ripple: flags.contains(.shift))
            return
        case 53: // Escape
            model.selectionRange = nil
            model.selectedClips.removeAll()
            model.selectedMarkerID = nil
            needsDisplay = true
            return
        case 36, 76: // Return / Enter
            model.seek(to: 0)
            return
        case 123: // Left arrow
            let step = flags.contains(.shift) ? 1.0 : TimelineGrid.step(secondsPerPoint: secondsPerPoint, minPoints: 14)
            model.seek(to: max(0, model.playhead - step))
            return
        case 124: // Right arrow
            let step = flags.contains(.shift) ? 1.0 : TimelineGrid.step(secondsPerPoint: secondsPerPoint, minPoints: 14)
            model.seek(to: min(contentDuration, model.playhead + step))
            return
        default:
            break
        }

        if flags.isEmpty || flags == .shift {
            switch chars {
            case "b", "s":
                model.splitAtPlayhead()
                return
            case "m":
                model.addMarkerAtPlayhead()
                return
            case "i":
                let t = model.playhead
                let end = max(t, model.selectionRange?.upperBound ?? contentDuration)
                model.selectionRange = t...end
                needsDisplay = true
                return
            case "o":
                let t = model.playhead
                let start = min(t, model.selectionRange?.lowerBound ?? 0)
                model.selectionRange = start...t
                needsDisplay = true
                return
            case "=", "+":
                zoom(by: 1.35, at: x(for: model.playhead))
                return
            case "-":
                zoom(by: 1.0 / 1.35, at: x(for: model.playhead))
                return
            case "0":
                fit()
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }
}
