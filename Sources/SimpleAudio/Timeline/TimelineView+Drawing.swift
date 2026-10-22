import Accelerate
import AppKit
import SimpleAudioCore
import SimpleAudioEngine

/// Pre-built text attributes and styles so `draw(_:)` allocates no attribute dictionaries per frame.
enum TimelineStyle {
    static let truncating: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    static let clipLabel: [NSAttributedString.Key: Any] = [
        .font: Theme.font(11, .semibold),
        .foregroundColor: Theme.text,
        .paragraphStyle: truncating,
    ]
    static let noteLabel: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(8.5, .bold),
        .foregroundColor: Theme.background,
        .paragraphStyle: truncating,
    ]
    static let noteLabelLight: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(8.5, .semibold),
        .foregroundColor: Theme.text,
        .paragraphStyle: truncating,
    ]
    static let badgeLabel: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(9.5, .medium),
        .foregroundColor: Theme.accent,
    ]
    static let timecode: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(9.5),
        .foregroundColor: Theme.text,
    ]
    static let ruler: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(9.5),
        .foregroundColor: Theme.textDim,
    ]
    static let rulerBar: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(9.0, .semibold),
        .foregroundColor: Theme.accent.withAlphaComponent(0.85),
    ]
    static let markerLabel: [NSAttributedString.Key: Any] = [
        .font: Theme.font(9.5, .semibold),
        .foregroundColor: Theme.background,
    ]
    static let trackTitle: [NSAttributedString.Key: Any] = [
        .font: Theme.font(11.5, .semibold),
        .foregroundColor: Theme.text,
        .paragraphStyle: truncating,
    ]
    static let trackSubtitle: [NSAttributedString.Key: Any] = [
        .font: Theme.font(9.5, .regular),
        .foregroundColor: Theme.textDim,
        .paragraphStyle: truncating,
    ]
    static let keyLabel: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(8.0, .semibold),
        .foregroundColor: Theme.textDim,
    ]
    static let headerButtonOff: [NSAttributedString.Key: Any] = [
        .font: Theme.font(9.5, .bold),
        .foregroundColor: Theme.textDim,
        .paragraphStyle: centered,
    ]
    static let headerButtonOn: [NSAttributedString.Key: Any] = [
        .font: Theme.font(9.5, .bold),
        .foregroundColor: Theme.background,
        .paragraphStyle: centered,
    ]
    static let headerValue: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(10, .medium),
        .foregroundColor: Theme.textDim,
        .paragraphStyle: centered,
    ]
    static let channelTag: [NSAttributedString.Key: Any] = [
        .font: Theme.mono(8.5, .semibold),
        .foregroundColor: Theme.textFaint,
    ]
    static let cornerDim: [NSAttributedString.Key: Any] = [
        .font: Theme.font(9, .semibold),
        .foregroundColor: Theme.textFaint,
    ]
    static let cornerOn: [NSAttributedString.Key: Any] = [
        .font: Theme.font(9, .semibold),
        .foregroundColor: Theme.snapGuide,
    ]
    static let pill = NSColor.black.withAlphaComponent(0.58)
    static let beyondEnd = NSColor.black.withAlphaComponent(0.35)
    static let hatchStep: CGFloat = 8
    static let hoverEdge = Theme.accent.withAlphaComponent(0.85)
    static let hoverEdgeWidth: CGFloat = 2
    static let timecodeWidth: CGFloat = ceil(("0:00.000" as NSString).size(withAttributes: timecode).width)
}

extension TimelineView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Theme.background.setFill()
        dirtyRect.intersection(bounds).fill()

        let p = project
        let rows = trackRows(for: p)

        // 1. Track lanes
        if dirtyRect.intersects(laneArea) {
            ctx.saveGState()
            ctx.clip(to: laneArea)
            for row in rows {
                let r = CGRect(x: Metrics.headerWidth, y: row.rect.minY, width: laneWidth, height: row.rect.height)
                guard r.intersects(dirtyRect) else { continue }
                let isSelectedTrack = model.selectedTrackID == row.track.id
                let bg = isSelectedTrack ? Theme.laneSelected : (row.index % 2 == 0 ? Theme.lane : Theme.laneAlt)
                bg.setFill()
                r.fill()
                ctx.saveGState()
                ctx.clip(to: r)
                if row.track.isMIDI {
                    drawPitchRows(in: r, row: row)
                    drawMusicalGrid(in: r, project: p)
                    drawTrackLaneNotes(ctx, project: p, row: row, laneRect: r)
                    if row.showPianoKeys {
                        drawPianoKeyboardStrip(ctx, row: row, laneRect: r)
                    }
                } else {
                    drawGrid(in: r)
                    drawTrackLane(ctx, project: p, row: row, laneRect: r)
                }
                ctx.restoreGState()
            }

            let bottom = rows.last?.rect.maxY ?? Metrics.topBarHeight
            let endX = x(for: p.totalDuration)
            if p.totalDuration > 0, endX < laneArea.maxX {
                TimelineStyle.beyondEnd.setFill()
                let startClamped = max(endX, laneArea.minX)
                CGRect(x: startClamped, y: laneArea.minY, width: laneArea.maxX - startClamped, height: max(0, bottom - laneArea.minY)).fill()
            }

            drawSelectionRangeInLanes(ctx, rows: rows)
            drawMarkersInLanes(ctx, project: p, bottom: bottom)
            drawGestureFeedback(ctx, project: p, rows: rows)
            if let line = hoverEdgeLine(project: p, rows: rows) {
                TimelineStyle.hoverEdge.setFill()
                line.fill()
            }
            ctx.restoreGState()
        }

        // 2. Track headers (left column)
        let headerCol = CGRect(x: 0, y: Metrics.topBarHeight, width: Metrics.headerWidth - 1, height: laneArea.height)
        if dirtyRect.intersects(headerCol) {
            ctx.saveGState()
            ctx.clip(to: headerCol)
            drawTrackHeaders(ctx, project: p, rows: rows)
            ctx.restoreGState()
        }

        // 3. Overview minimap & Ruler (top bar)
        if dirtyRect.intersects(overviewArea) {
            drawOverview(ctx, project: p)
        }
        if dirtyRect.intersects(rulerArea) {
            drawRuler(ctx, project: p)
        }
        let cornerRect = CGRect(x: 0, y: 0, width: Metrics.headerWidth, height: Metrics.topBarHeight)
        if dirtyRect.intersects(cornerRect) {
            drawCorner()
        }

        // 4. Hairline separators
        Theme.separator.setFill()
        CGRect(x: Metrics.headerWidth - 1, y: 0, width: 1, height: bounds.height).fill()
        CGRect(x: 0, y: Metrics.overviewHeight - 1, width: bounds.width, height: 1).fill()
        CGRect(x: 0, y: Metrics.topBarHeight - 1, width: bounds.width, height: 1).fill()
        for row in rows where row.rect.maxY >= Metrics.topBarHeight {
            CGRect(x: 0, y: row.rect.maxY, width: bounds.width, height: Metrics.laneGap).fill()
        }
    }

    // MARK: Grid & Center Lines

    private func drawGrid(in rect: CGRect) {
        let minor = TimelineGrid.step(secondsPerPoint: secondsPerPoint, minPoints: 14)
        let major = TimelineGrid.step(secondsPerPoint: secondsPerPoint, minPoints: 84)
        var t = max(0, (time(for: rect.minX) / minor).rounded(.down) * minor)
        let end = time(for: rect.maxX)
        while t <= end {
            let isMajor = abs(t / major - (t / major).rounded()) < 1e-6
            (isMajor ? Theme.gridMajor : Theme.gridMinor).setFill()
            CGRect(x: x(for: t).rounded(), y: rect.minY, width: 1, height: rect.height).fill()
            t += minor
        }
    }

    private func drawPitchRows(in rect: CGRect, row: TrackRow) {
        let pitchCount = max(1, row.maxPitch - row.minPitch + 1)
        let usableTop = row.rect.minY + Metrics.blockInset
        let usableHeight = max(12, row.rect.height - 2 * Metrics.blockInset)
        let rowH = usableHeight / CGFloat(pitchCount)

        for pitch in row.minPitch...row.maxPitch {
            let normFromTop = CGFloat(row.maxPitch - pitch) / CGFloat(max(1, pitchCount - 1))
            let y = usableTop + normFromTop * max(0, usableHeight - rowH)
            if row.showPianoKeys && GeneralMIDI.isBlackKey(pitch) && rowH >= 3.5 {
                Theme.laneBlackKey.withAlphaComponent(0.55).setFill()
                CGRect(x: rect.minX, y: y, width: rect.width, height: rowH).fill()
            }
            if pitch % 12 == 0 {
                Theme.gridOctave.setFill()
                CGRect(x: rect.minX, y: (y + rowH).rounded(), width: rect.width, height: 1).fill()
            }
        }
    }

    private func drawMusicalGrid(in rect: CGRect, project p: AudioProject) {
        let beatSec = p.secondsPerBeat
        let barSec = p.secondsPerBar
        let minor = max(beatSec, TimelineGrid.step(secondsPerPoint: secondsPerPoint, minPoints: 18))
        let major = max(barSec, TimelineGrid.step(secondsPerPoint: secondsPerPoint, minPoints: 72))

        var t = max(0, (time(for: rect.minX) / minor).rounded(.down) * minor)
        let end = time(for: rect.maxX)
        while t <= end {
            let isMajor = abs(t / major - (t / major).rounded()) < 1e-4
            (isMajor ? Theme.gridMajor : Theme.gridMinor).setFill()
            CGRect(x: x(for: t).rounded(), y: rect.minY, width: 1, height: rect.height).fill()
            t += minor
        }
    }

    private func drawPianoKeyboardStrip(_ ctx: CGContext, row: TrackRow, laneRect: CGRect) {
        let stripW: CGFloat = Metrics.pianoKeysWidth
        let stripRect = CGRect(x: laneRect.minX, y: row.rect.minY, width: stripW, height: row.rect.height)
        Theme.header.withAlphaComponent(0.92).setFill()
        stripRect.fill()

        let pitchCount = max(1, row.maxPitch - row.minPitch + 1)
        let usableTop = row.rect.minY + Metrics.blockInset
        let usableHeight = max(12, row.rect.height - 2 * Metrics.blockInset)
        let keyH = max(3.0, usableHeight / CGFloat(pitchCount))

        for pitch in row.minPitch...row.maxPitch {
            let normFromTop = CGFloat(row.maxPitch - pitch) / CGFloat(max(1, pitchCount - 1))
            let y = usableTop + normFromTop * max(0, usableHeight - keyH)
            let isBlack = GeneralMIDI.isBlackKey(pitch)
            if isBlack {
                NSColor(white: 0.08, alpha: 0.95).setFill()
                CGRect(x: stripRect.minX, y: y, width: stripW * 0.62, height: max(keyH - 0.5, 2)).fill()
            } else {
                NSColor(white: 1.0, alpha: 0.08).setFill()
                CGRect(x: stripRect.minX, y: y, width: stripW - 1, height: max(keyH - 0.5, 2)).fill()
            }
            if pitch % 12 == 0 && keyH >= 5.5 {
                let label = GeneralMIDI.noteName(pitch) as NSString
                label.draw(at: CGPoint(x: stripRect.minX + 4, y: y - 1), withAttributes: TimelineStyle.keyLabel)
            }
        }

        Theme.separator.setFill()
        CGRect(x: stripRect.maxX - 1, y: stripRect.minY, width: 1, height: stripRect.height).fill()
    }

    private func drawTrackLaneNotes(_ ctx: CGContext, project p: AudioProject, row: TrackRow, laneRect: CGRect) {
        let track = row.track
        let audible = p.isTrackAudible(track)
        let trackColor = Theme.trackColor(track.colorIndex)
        let visibleMinX = laneRect.minX
        let visibleMaxX = laneRect.maxX
        let visibleEndTime = time(for: visibleMaxX)

        for note in track.notes {
            if note.start > visibleEndTime { break }
            let rect = noteRect(note, in: row)
            guard rect.maxX >= visibleMinX, rect.minX <= visibleMaxX else { continue }
            let selected = model.selectedNotes.contains(note.id)
            let hovered = hoveredNote == note.id
            let noteAudible = audible && !note.mute

            let velFactor = CGFloat(0.45 + 0.55 * note.normalizedVelocity)
            let fillAlpha: CGFloat = noteAudible ? (selected ? 0.95 : 0.78 * velFactor) : 0.22
            let radius = min(2.5, rect.height * 0.35)
            let cgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

            ctx.addPath(cgPath)
            ctx.setFillColor(trackColor.withAlphaComponent(fillAlpha).cgColor)
            ctx.fillPath()

            if rect.height >= 6 && noteAudible {
                ctx.setFillColor(NSColor.white.withAlphaComponent(selected ? 0.45 : 0.22).cgColor)
                ctx.fill(CGRect(x: rect.minX + 1, y: rect.minY + 0.5, width: max(0, rect.width - 2), height: 1.2))
            }

            ctx.addPath(cgPath)
            if selected {
                ctx.setStrokeColor(Theme.selection.cgColor)
                ctx.setLineWidth(1.5)
            } else if hovered {
                ctx.setStrokeColor(TimelineStyle.hoverEdge.cgColor)
                ctx.setLineWidth(1.2)
            } else {
                ctx.setStrokeColor(trackColor.withAlphaComponent(noteAudible ? 0.95 : 0.35).cgColor)
                ctx.setLineWidth(0.75)
            }
            ctx.strokePath()

            if rect.width >= 24 && rect.height >= 9.5 {
                let name = ((track.isDrum || track.channel == 9) ? GeneralMIDI.drumName(note.pitch) : GeneralMIDI.noteName(note.pitch + track.transpose)) as NSString
                let attrs = selected ? TimelineStyle.noteLabel : TimelineStyle.noteLabelLight
                name.draw(
                    with: rect.insetBy(dx: 3, dy: 0),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: attrs
                )
            }
        }
    }

    // MARK: Track Lanes & Clips

    private func drawTrackLane(_ ctx: CGContext, project p: AudioProject, row: TrackRow, laneRect: CGRect) {
        let track = row.track
        let audible = p.isTrackAudible(track)
        let trackColor = Theme.trackColor(track.colorIndex)

        // Zero-crossing horizontal reference lines
        Theme.zeroLine.setFill()
        if track.stereoSplit {
            let topMid = (laneRect.minY + laneRect.height * 0.25).rounded()
            let botMid = (laneRect.minY + laneRect.height * 0.75).rounded()
            let sepY = (laneRect.midY).rounded()
            CGRect(x: laneRect.minX, y: topMid, width: laneRect.width, height: 1).fill()
            CGRect(x: laneRect.minX, y: botMid, width: laneRect.width, height: 1).fill()
            Theme.gridMajor.setFill()
            CGRect(x: laneRect.minX, y: sepY, width: laneRect.width, height: 1).fill()
            ("L" as NSString).draw(at: CGPoint(x: laneRect.minX + 4, y: laneRect.minY + 2), withAttributes: TimelineStyle.channelTag)
            ("R" as NSString).draw(at: CGPoint(x: laneRect.minX + 4, y: sepY + 2), withAttributes: TimelineStyle.channelTag)
        } else {
            CGRect(x: laneRect.minX, y: laneRect.midY.rounded(), width: laneRect.width, height: 1).fill()
        }

        let visibleMinX = laneRect.minX
        let visibleMaxX = laneRect.maxX

        for clip in track.clips {
            let rect = clipRect(clip, in: row.rect)
            guard rect.maxX >= visibleMinX, rect.minX <= visibleMaxX else { continue }
            let selected = model.selectedClips.contains(clip.id)
            drawClipBlock(
                ctx,
                clip: clip,
                track: track,
                rect: rect,
                color: trackColor,
                selected: selected,
                hovered: clip.id == hoveredClip,
                audible: audible && !clip.mute
            )
            drawFadeHandles(fadeHandleCenters(for: clip, in: row.rect), selected: selected)
        }
    }

    func drawClipBlock(
        _ ctx: CGContext,
        clip: AudioClip,
        track: AudioTrack,
        rect: CGRect,
        color: NSColor,
        selected: Bool,
        hovered: Bool,
        audible: Bool
    ) {
        let body = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        color.withAlphaComponent(selected ? 0.22 : (audible ? 0.12 : 0.05)).setFill()
        body.fill()

        ctx.saveGState()
        body.addClip()

        if !audible {
            drawMutedHatch(ctx, rect: rect, color: color)
        }

        let url = model.resolvedURL(for: clip.path)
        let waveAlpha: CGFloat = audible ? 0.88 : 0.32
        drawWaveform(
            ctx,
            url: url,
            clip: clip,
            stereoSplit: track.stereoSplit,
            rect: rect,
            color: color.withAlphaComponent(waveAlpha)
        )
        drawFadeWedges(ctx, rect: rect, clip: clip)
        ctx.restoreGState()

        // Label pill at top-left of clip (clamped to stay visible when scrolled)
        let left = max(rect.minX, laneArea.minX) + 5
        let room = rect.maxX - 5 - left
        if room >= 28 {
            var title = clip.name
            if clip.reversed { title += " ⇄" }
            if clip.mute { title += " (muet)" }
            let gainBadge = abs(clip.gainDB) >= 0.05 ? "  \(TimeFormat.decibels(clip.gainDB))" : ""
            let fullText = (title + gainBadge) as NSString
            let textWidth = ceil(fullText.size(withAttributes: TimelineStyle.clipLabel).width)
            let pillWidth = min(textWidth + 10, room)
            let pill = CGRect(x: left, y: rect.minY + 4, width: pillWidth, height: 16)
            TimelineStyle.pill.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 3, yRadius: 3).fill()
            fullText.draw(
                with: pill.insetBy(dx: 5, dy: 1.5),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: TimelineStyle.clipLabel
            )
        }

        if hovered, rect.width >= 2 * TimelineStyle.timecodeWidth + 24 {
            drawTimecodePill(TimeFormat.timecode(clip.offset), at: CGPoint(x: rect.minX + 4, y: rect.maxY - 17))
            drawTimecodePill(
                TimeFormat.timecode(clip.end),
                at: CGPoint(x: rect.maxX - 4 - TimelineStyle.timecodeWidth - 8, y: rect.maxY - 17)
            )
        }

        (selected ? Theme.selection : color.withAlphaComponent(audible ? 0.85 : 0.4)).setStroke()
        body.lineWidth = selected ? 1.5 : 1
        body.stroke()
    }

    private func drawMutedHatch(_ ctx: CGContext, rect: CGRect, color: NSColor) {
        let step = TimelineStyle.hatchStep
        let from = max(rect.minX, laneArea.minX) - rect.height
        let to = min(rect.maxX, laneArea.maxX)
        var hx = rect.minX + ((from - rect.minX) / step).rounded(.down) * step
        while hx <= to {
            ctx.move(to: CGPoint(x: hx, y: rect.maxY))
            ctx.addLine(to: CGPoint(x: hx + rect.height, y: rect.minY))
            hx += step
        }
        ctx.setStrokeColor(color.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    private func drawTimecodePill(_ text: String, at origin: CGPoint) {
        let pill = CGRect(x: origin.x, y: origin.y, width: TimelineStyle.timecodeWidth + 8, height: 13)
        TimelineStyle.pill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 3, yRadius: 3).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 4, y: pill.minY), withAttributes: TimelineStyle.timecode)
    }

    // MARK: High-Resolution Waveform Drawing (Peak + RMS + Live Gain & Fade Shaping + Stereo L/R)

    func drawWaveform(
        _ ctx: CGContext,
        url: URL,
        clip: AudioClip,
        stereoSplit: Bool,
        rect: CGRect,
        color: NSColor
    ) {
        guard let wave = model.waveforms.envelope(for: url), wave.binsPerSecond > 0, !wave.peaks.isEmpty else { return }
        let from = max(rect.minX, laneArea.minX).rounded(.down)
        let to = min(rect.maxX, laneArea.maxX).rounded(.up)
        guard to > from else { return }

        let spp = secondsPerPoint
        let bps = wave.binsPerSecond
        let linearGain = Float(clip.linearGain)
        let hasFade = clip.fadeIn > 1e-6 || clip.fadeOut > 1e-6

        // Sample-level polyline when zoomed in close (< 0.5 ms per pixel)
        if spp < 0.0005, let pcm = model.waveforms.pcm(for: url) {
            drawSampleLevelWaveform(ctx, pcm: pcm, clip: clip, stereoSplit: stereoSplit, rect: rect, from: from, to: to, color: color)
            return
        }

        if stereoSplit && wave.channelCount >= 2 {
            let topRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.5)
            let botRect = CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height * 0.5)
            drawChannelEnvelope(
                ctx,
                peaks: wave.leftPeaks,
                rms: wave.rms,
                bps: bps,
                clip: clip,
                linearGain: linearGain,
                hasFade: hasFade,
                clipRect: rect,
                channelRect: topRect,
                from: from,
                to: to,
                color: color
            )
            drawChannelEnvelope(
                ctx,
                peaks: wave.rightPeaks,
                rms: wave.rms,
                bps: bps,
                clip: clip,
                linearGain: linearGain,
                hasFade: hasFade,
                clipRect: rect,
                channelRect: botRect,
                from: from,
                to: to,
                color: color
            )
        } else {
            drawChannelEnvelope(
                ctx,
                peaks: wave.peaks,
                rms: wave.rms,
                bps: bps,
                clip: clip,
                linearGain: linearGain,
                hasFade: hasFade,
                clipRect: rect,
                channelRect: rect,
                from: from,
                to: to,
                color: color
            )
        }
    }

    private func drawChannelEnvelope(
        _ ctx: CGContext,
        peaks: [Float],
        rms: [Float],
        bps: Double,
        clip: AudioClip,
        linearGain: Float,
        hasFade: Bool,
        clipRect: CGRect,
        channelRect: CGRect,
        from: CGFloat,
        to: CGFloat,
        color: NSColor
    ) {
        let count = Int(to - from) + 1
        guard count > 0 else { return }
        let mid = channelRect.midY
        let half = max(channelRect.height / 2 - 2, 1)
        let spp = secondsPerPoint
        let peakCount = peaks.count
        let rmsCount = rms.count

        // Single-pass column calculation (avoids computing peak/rms twice per pixel column)
        var peakHeights = [CGFloat](repeating: 0.5, count: count)
        var rmsHeights = [CGFloat](repeating: 0.25, count: count)

        peaks.withUnsafeBufferPointer { peakBuf in
            rms.withUnsafeBufferPointer { rmsBuf in
                let pBase = peakBuf.baseAddress
                let rBase = rmsBuf.baseAddress
                for idx in 0..<count {
                    let px = from + CGFloat(idx)
                    let local = Double(px - clipRect.minX) * spp
                    let srcTime = clip.reversed ? (clip.sourceStart + clip.duration - local) : (clip.sourceStart + local)
                    let i0 = max(Int((srcTime * bps).rounded(.down)), 0)
                    let i1 = min(max(i0 + 1, Int(((srcTime + spp) * bps).rounded(.up))), peakCount)
                    guard i0 < i1 else { continue }

                    var pMax: Float = 0
                    var rMax: Float = 0
                    let span = i1 - i0
                    if span >= 16, let pBase {
                        vDSP_maxv(pBase + i0, 1, &pMax, vDSP_Length(span))
                        let rEnd = min(i1, rmsCount)
                        if i0 < rEnd, let rBase {
                            vDSP_maxv(rBase + i0, 1, &rMax, vDSP_Length(rEnd - i0))
                        }
                    } else if let pBase {
                        for i in i0..<i1 {
                            let pv = pBase[i]
                            if pv > pMax { pMax = pv }
                            if i < rmsCount, let rBase {
                                let rv = rBase[i]
                                if rv > rMax { rMax = rv }
                            }
                        }
                    }

                    var scale = linearGain
                    if hasFade {
                        scale *= Float(clip.fadeGain(atLocalTime: local))
                    }
                    let pH = max(CGFloat(min(pMax * scale, 1.0)) * half, 0.5)
                    let rH = max(CGFloat(min(rMax * scale, 1.0)) * half, 0.3)
                    peakHeights[idx] = pH
                    rmsHeights[idx] = min(rH, pH)
                }
            }
        }

        let peakPath = CGMutablePath()
        let rmsPath = CGMutablePath()
        peakPath.move(to: CGPoint(x: from, y: mid))
        rmsPath.move(to: CGPoint(x: from, y: mid))

        for idx in 0..<count {
            let px = from + CGFloat(idx)
            peakPath.addLine(to: CGPoint(x: px, y: mid - peakHeights[idx]))
            rmsPath.addLine(to: CGPoint(x: px, y: mid - rmsHeights[idx]))
        }
        for idx in stride(from: count - 1, through: 0, by: -1) {
            let px = from + CGFloat(idx)
            peakPath.addLine(to: CGPoint(x: px, y: mid + peakHeights[idx]))
            rmsPath.addLine(to: CGPoint(x: px, y: mid + rmsHeights[idx]))
        }
        peakPath.closeSubpath()
        rmsPath.closeSubpath()

        ctx.addPath(peakPath)
        ctx.setFillColor(color.withAlphaComponent(color.alphaComponent * 0.62).cgColor)
        ctx.fillPath()

        ctx.addPath(rmsPath)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    private func drawSampleLevelWaveform(
        _ ctx: CGContext,
        pcm: AudioPCMData,
        clip: AudioClip,
        stereoSplit: Bool,
        rect: CGRect,
        from: CGFloat,
        to: CGFloat,
        color: NSColor
    ) {
        let spp = secondsPerPoint
        let linearGain = Float(clip.linearGain)
        let channelsToDraw = (stereoSplit && pcm.channelCount >= 2) ? 2 : 1

        for ch in 0..<channelsToDraw {
            let channelRect: CGRect
            if channelsToDraw == 2 {
                channelRect = CGRect(
                    x: rect.minX,
                    y: ch == 0 ? rect.minY : rect.midY,
                    width: rect.width,
                    height: rect.height * 0.5
                )
            } else {
                channelRect = rect
            }
            let mid = channelRect.midY
            let half = max(channelRect.height / 2 - 2, 1)
            let path = CGMutablePath()
            var started = false
            var px = from
            while px <= to {
                let local = Double(px - rect.minX) * spp
                let srcTime = clip.reversed ? (clip.sourceStart + clip.duration - local) : (clip.sourceStart + local)
                let (sL, sR) = pcm.sample(at: srcTime)
                let s = (ch == 0 ? sL : sR) * linearGain * Float(clip.fadeGain(atLocalTime: local))
                let y = mid - CGFloat(min(max(s, -1), 1)) * half
                if !started {
                    path.move(to: CGPoint(x: px, y: y))
                    started = true
                } else {
                    path.addLine(to: CGPoint(x: px, y: y))
                }
                px += 1
            }
            ctx.addPath(path)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1.25)
            ctx.strokePath()
        }
    }

    // MARK: Fade Wedges, Mathematical Curve & Handles

    func drawFadeWedges(_ ctx: CGContext, rect: CGRect, clip: AudioClip) {
        let steps = 20
        for (isIn, length) in [(true, clip.fadeIn), (false, clip.fadeOut)] where length > 1e-4 {
            let w = min(CGFloat(length / secondsPerPoint), rect.width)
            guard w >= 1.5 else { continue }
            let startX = isIn ? rect.minX : (rect.maxX - w)

            // Build the fade curve from x = startX (frac = 0) to x = startX + w (frac = 1)
            let wedge = CGMutablePath()
            let curve = CGMutablePath()
            wedge.move(to: CGPoint(x: isIn ? startX : startX + w, y: rect.minY))

            for k in 0...steps {
                let frac = Double(k) / Double(steps)
                let g = clip.fadeShape.gain(at: frac, isIn: isIn)
                let ptX = startX + CGFloat(frac) * w
                let ptY = rect.maxY - CGFloat(g) * rect.height
                wedge.addLine(to: CGPoint(x: ptX, y: ptY))
                if k == 0 {
                    curve.move(to: CGPoint(x: ptX, y: ptY))
                } else {
                    curve.addLine(to: CGPoint(x: ptX, y: ptY))
                }
            }
            wedge.closeSubpath()

            ctx.addPath(wedge)
            ctx.setFillColor(Theme.fade.cgColor)
            ctx.fillPath()

            ctx.addPath(curve)
            ctx.setStrokeColor(Theme.text.withAlphaComponent(0.65).cgColor)
            ctx.setLineWidth(1.2)
            ctx.strokePath()
        }
    }

    private func drawFadeHandles(_ h: (fadeIn: CGPoint, fadeOut: CGPoint), selected: Bool) {
        for c in [h.fadeIn, h.fadeOut] {
            let square = CGRect(
                x: c.x - Metrics.fadeHandle / 2,
                y: c.y - Metrics.fadeHandle / 2,
                width: Metrics.fadeHandle,
                height: Metrics.fadeHandle
            )
            (selected ? Theme.selection : Theme.accent.withAlphaComponent(0.9)).setFill()
            square.fill()
            Theme.background.setStroke()
            NSBezierPath(rect: square.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    // MARK: Time Range Selection & Markers in Lanes

    private func drawSelectionRangeInLanes(_ ctx: CGContext, rows: [TrackRow]) {
        guard let range = model.selectionRange, range.upperBound > range.lowerBound + 1e-5 else { return }
        let x0 = x(for: range.lowerBound).rounded()
        let x1 = x(for: range.upperBound).rounded()
        guard x1 >= laneArea.minX, x0 <= laneArea.maxX else { return }

        let targetRows: [TrackRow]
        if let selTrack = model.selectedTrackID, let only = rows.first(where: { $0.track.id == selTrack }), rows.count > 1 {
            targetRows = [only]
        } else {
            targetRows = rows
        }
        guard let first = targetRows.first, let last = targetRows.last else { return }
        let topY = first.rect.minY
        let botY = last.rect.maxY
        let spanRect = CGRect(x: x0, y: topY, width: max(x1 - x0, 1), height: max(0, botY - topY))

        Theme.rangeSelection.withAlphaComponent(0.13).setFill()
        spanRect.fill()

        Theme.rangeSelection.withAlphaComponent(0.88).setFill()
        CGRect(x: x0, y: topY, width: 1.5, height: spanRect.height).fill()
        CGRect(x: x1 - 1.5, y: topY, width: 1.5, height: spanRect.height).fill()
        // Top & bottom bracket caps
        let capW: CGFloat = min(6, max(2, spanRect.width / 3))
        CGRect(x: x0, y: topY, width: capW, height: 2).fill()
        CGRect(x: x0, y: botY - 2, width: capW, height: 2).fill()
        CGRect(x: x1 - capW, y: topY, width: capW, height: 2).fill()
        CGRect(x: x1 - capW, y: botY - 2, width: capW, height: 2).fill()
    }

    private func drawMarkersInLanes(_ ctx: CGContext, project p: AudioProject, bottom: CGFloat) {
        guard bottom > laneArea.minY else { return }
        let sorted = p.markers.sorted { $0.time < $1.time }
        for (idx, marker) in sorted.enumerated() {
            let mx = x(for: marker.time).rounded()
            let color = Theme.trackColor(marker.colorIndex)
            let isSelected = model.selectedMarkerID == marker.id
            if isSelected {
                let nextTime = idx + 1 < sorted.count ? sorted[idx + 1].time : contentDuration
                let xEnd = x(for: nextTime).rounded()
                let spanX0 = max(laneArea.minX, mx)
                let spanX1 = min(laneArea.maxX, xEnd)
                if spanX1 > spanX0 {
                    color.withAlphaComponent(0.06).setFill()
                    CGRect(x: spanX0, y: laneArea.minY, width: spanX1 - spanX0, height: bottom - laneArea.minY).fill()
                }
            }
            guard mx >= laneArea.minX, mx <= laneArea.maxX else { continue }
            (isSelected ? Theme.selection.withAlphaComponent(0.85) : color.withAlphaComponent(0.45)).setFill()
            CGRect(x: mx, y: laneArea.minY, width: isSelected ? 1.5 : 1, height: bottom - laneArea.minY).fill()
        }
    }

    // MARK: Track Headers

    private func drawTrackHeaders(_ ctx: CGContext, project p: AudioProject, rows: [TrackRow]) {
        Theme.header.setFill()
        CGRect(x: 0, y: Metrics.topBarHeight, width: Metrics.headerWidth - 1, height: laneArea.height).fill()

        for row in rows {
            let r = CGRect(x: 0, y: row.rect.minY, width: Metrics.headerWidth - 1, height: row.rect.height)
            let isSelected = model.selectedTrackID == row.track.id
            let isDraggingThisTrack: Bool
            if case .moveTrack(let draggedID, _) = drag {
                isDraggingThisTrack = draggedID == row.track.id
            } else {
                isDraggingThisTrack = false
            }
            if isDraggingThisTrack {
                Theme.selection.withAlphaComponent(0.18).setFill()
                r.fill()
            } else if isSelected {
                Theme.laneSelected.withAlphaComponent(0.75).setFill()
                r.fill()
            }
            let color = Theme.trackColor(row.track.colorIndex)
            color.setFill()
            CGRect(x: 0, y: r.minY, width: 3.5, height: r.height).fill()

            // Subtle 6-dot drag grip when multiple tracks can be reordered
            if p.tracks.count > 1 {
                let gripColor = isDraggingThisTrack ? Theme.selection : Theme.textFaint.withAlphaComponent(0.55)
                gripColor.setFill()
                let gx: CGFloat = 6.5
                let gy = r.minY + 10
                for dy in stride(from: CGFloat(0), through: 6, by: 3) {
                    CGRect(x: gx, y: gy + dy, width: 1.5, height: 1.5).fill()
                    CGRect(x: gx + 2.5, y: gy + dy, width: 1.5, height: 1.5).fill()
                }
            }

            let titleX: CGFloat = p.tracks.count > 1 ? 13.5 : 11
            let isMIDI = row.track.isMIDI
            let controls = headerControlRects(in: row.rect, isMIDI: isMIDI)
            let titleWidth = max(20, controls.mute.minX - titleX - 4)
            (row.track.name as NSString).draw(
                with: CGRect(x: titleX, y: r.minY + 7, width: titleWidth, height: 16),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: TimelineStyle.trackTitle
            )

            if isMIDI {
                let subText = "\(row.track.instrumentLabel) · Ch \(row.track.channel + 1)" as NSString
                subText.draw(
                    with: CGRect(x: 11, y: r.minY + 24, width: Metrics.headerWidth - 18, height: 14),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: TimelineStyle.trackSubtitle
                )
            }

            // Mute button (M)
            drawHeaderButton(rect: controls.mute, label: "M", active: row.track.mute, tint: Theme.muteColor)
            // Solo button (S)
            drawHeaderButton(rect: controls.solo, label: "S", active: row.track.solo, tint: Theme.soloColor)
            // Stereo L/R split button or Piano-Roll button
            if isMIDI {
                drawHeaderButton(rect: controls.third, label: "🎹", active: row.track.pianoRollExpanded, tint: Theme.snapGuide)
            } else {
                drawHeaderButton(rect: controls.third, label: "⊶", active: row.track.stereoSplit, tint: Theme.snapGuide)
            }

            // Gain & Pan pills
            let minHForPills: CGFloat = isMIDI ? 66 : 54
            if r.height >= minHForPills {
                drawValuePill(rect: controls.gain, text: TimeFormat.decibels(row.track.gainDB))
                drawValuePill(rect: controls.pan, text: TimeFormat.pan(row.track.pan))
            }

            if isDraggingThisTrack {
                Theme.selection.withAlphaComponent(0.85).setStroke()
                let border = NSBezierPath(rect: r.insetBy(dx: 0.75, dy: 0.75))
                border.lineWidth = 1.5
                border.stroke()
            }
        }
    }

    private func drawHeaderButton(rect: CGRect, label: String, active: Bool, tint: NSColor) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
        (active ? tint : NSColor(white: 1, alpha: 0.06)).setFill()
        path.fill()
        let attrs = active ? TimelineStyle.headerButtonOn : TimelineStyle.headerButtonOff
        let size = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.midY - size.height / 2, width: rect.width, height: size.height),
            withAttributes: attrs
        )
    }

    private func drawValuePill(rect: CGRect, text: String) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
        NSColor(white: 1, alpha: 0.05).setFill()
        path.fill()
        let size = (text as NSString).size(withAttributes: TimelineStyle.headerValue)
        (text as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.midY - size.height / 2, width: rect.width, height: size.height),
            withAttributes: TimelineStyle.headerValue
        )
    }

    // MARK: Overview Minimap, Ruler & Corner

    private func drawOverview(_ ctx: CGContext, project p: AudioProject) {
        let area = overviewArea
        Theme.overview.setFill()
        area.fill()
        guard area.width > 20, p.totalDuration > 0 else { return }

        ctx.saveGState()
        ctx.clip(to: area)

        let dur = contentDuration
        let allClips = p.allClips
        let waveReadyCount = allClips.reduce(0) { acc, item in
            let hasWave = model.waveforms.envelope(for: model.resolvedURL(for: item.clip.path))?.peaks.isEmpty == false
            return acc + (hasWave ? 1 : 0)
        }
        let cacheKey = OverviewCacheKey(
            changeCount: model.store.changeCount,
            width: Int(area.width.rounded()),
            height: Int(area.height.rounded()),
            clipCount: allClips.count,
            noteCount: p.noteCount,
            waveReadyCount: waveReadyCount
        )

        if preview != nil || cachedOverviewKey != cacheKey {
            let fromX = area.minX + Metrics.leadIn
            let toX = area.maxX - Metrics.leadIn
            let spanW = max(toX - fromX, 1)
            let midY = area.midY
            let halfH = area.height / 2 - 3

            // 1. Build combined miniature waveform path in a single pass
            var builtWavePath: CGPath?
            if waveReadyCount > 0 {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: fromX, y: midY))
                var coords: [(x: CGFloat, h: CGFloat)] = []
                coords.reserveCapacity(Int(spanW / 2) + 2)
                var px = fromX
                while px <= toX {
                    let t0 = Double((px - fromX) / spanW) * dur
                    let t1 = Double((px + 1 - fromX) / spanW) * dur
                    var peak: Float = 0
                    for (_, _, c) in allClips where !c.mute && c.end >= t0 && c.offset <= t1 {
                        if let w = model.waveforms.envelope(for: model.resolvedURL(for: c.path)) {
                            let v = w.values(at: c.sourceStart + max(0, t0 - c.offset), window: max(0.01, t1 - t0))
                            let scaled = v.peak * Float(c.amplitude(atTimelineTime: max(c.offset, min(t0, c.end))))
                            if scaled > peak { peak = scaled }
                        }
                    }
                    let h = max(CGFloat(min(peak, 1)) * halfH, 0.5)
                    coords.append((px, h))
                    path.addLine(to: CGPoint(x: px, y: midY - h))
                    px += 2
                }
                for item in coords.reversed() {
                    path.addLine(to: CGPoint(x: item.x, y: midY + item.h))
                }
                path.closeSubpath()
                builtWavePath = path
            }

            // 2. Build batched MIDI note rects by track color
            var builtBatches: [(colorIndex: Int, rects: [CGRect])] = []
            let allNotes = p.allNotes
            if !allNotes.isEmpty {
                var minP = 127
                var maxP = 0
                for (_, _, n) in allNotes {
                    if n.pitch < minP { minP = n.pitch }
                    if n.pitch > maxP { maxP = n.pitch }
                }
                maxP = max(minP + 12, maxP)
                let pSpan = CGFloat(max(1, maxP - minP))
                let topPad: CGFloat = 4
                let usableH = max(4, area.height - 2 * topPad)

                var byColor: [Int: [CGRect]] = [:]
                for (ti, _, n) in allNotes where !n.mute {
                    let cIdx = p.tracks[ti].colorIndex
                    let x0 = overviewX(for: n.start)
                    let x1 = max(x0 + 1.5, overviewX(for: n.end))
                    let norm = CGFloat(maxP - n.pitch) / pSpan
                    let ny = area.minY + topPad + norm * (usableH - 2)
                    byColor[cIdx, default: []].append(CGRect(x: x0, y: ny, width: x1 - x0, height: 2.0))
                }
                builtBatches = byColor.keys.sorted().map { ($0, byColor[$0]!) }
            }

            if preview == nil {
                cachedOverviewKey = cacheKey
                cachedOverviewWavePath = builtWavePath
                cachedOverviewNoteBatches = builtBatches
            }

            if let wavePath = builtWavePath {
                ctx.addPath(wavePath)
                ctx.setFillColor(Theme.accent.withAlphaComponent(0.45).cgColor)
                ctx.fillPath()
            }
            for batch in builtBatches {
                ctx.setFillColor(Theme.trackColor(batch.colorIndex).withAlphaComponent(0.78).cgColor)
                ctx.fill(batch.rects)
            }
        } else {
            if let wavePath = cachedOverviewWavePath {
                ctx.addPath(wavePath)
                ctx.setFillColor(Theme.accent.withAlphaComponent(0.45).cgColor)
                ctx.fillPath()
            }
            for batch in cachedOverviewNoteBatches {
                ctx.setFillColor(Theme.trackColor(batch.colorIndex).withAlphaComponent(0.78).cgColor)
                ctx.fill(batch.rects)
            }
        }

        // Selection range on overview
        if let range = model.selectionRange {
            let rx0 = overviewX(for: range.lowerBound)
            let rx1 = overviewX(for: range.upperBound)
            Theme.rangeSelection.withAlphaComponent(0.22).setFill()
            CGRect(x: rx0, y: area.minY + 1, width: max(rx1 - rx0, 1), height: area.height - 2).fill()
        }

        // Visible viewport box
        let visibleStart = scrollOffset
        let visibleEnd = min(dur, scrollOffset + Double(laneWidth - Metrics.leadIn - Metrics.endMargin) * secondsPerPoint)
        let vx0 = max(area.minX + 2, overviewX(for: visibleStart))
        let vx1 = min(area.maxX - 2, max(vx0 + 8, overviewX(for: visibleEnd)))
        let viewRect = CGRect(x: vx0, y: area.minY + 2, width: vx1 - vx0, height: area.height - 4)
        NSColor(white: 1, alpha: 0.06).setFill()
        viewRect.fill()
        Theme.text.withAlphaComponent(0.45).setStroke()
        let vpPath = NSBezierPath(roundedRect: viewRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        vpPath.lineWidth = 1
        vpPath.stroke()

        ctx.restoreGState()
    }

    private func drawRuler(_ ctx: CGContext, project p: AudioProject) {
        let ruler = rulerArea
        Theme.ruler.setFill()
        ruler.fill()
        ctx.saveGState()
        ctx.clip(to: ruler)

        let minor = TimelineGrid.step(secondsPerPoint: secondsPerPoint, minPoints: 14)
        let major = TimelineGrid.step(secondsPerPoint: secondsPerPoint, minPoints: 84)
        var t = max(0, (time(for: ruler.minX) / minor).rounded(.down) * minor)
        let end = time(for: ruler.maxX)
        while t <= end {
            let px = x(for: t).rounded()
            let isMajor = abs(t / major - (t / major).rounded()) < 1e-6
            (isMajor ? Theme.textFaint : Theme.gridMajor).setFill()
            CGRect(x: px, y: ruler.maxY - (isMajor ? 8 : 4), width: 1, height: isMajor ? 8 : 4).fill()
            if isMajor {
                let baseLabel = TimeFormat.rulerLabel(t, step: major)
                let fullLabel: NSString
                if p.hasMIDITracks {
                    let barNum = Int((t / max(0.1, p.secondsPerBar)).rounded()) + 1
                    fullLabel = "\(baseLabel) · M\(barNum)" as NSString
                } else {
                    fullLabel = baseLabel as NSString
                }
                fullLabel.draw(
                    at: CGPoint(x: px + 4, y: ruler.minY + 3),
                    withAttributes: TimelineStyle.ruler
                )
            }
            t += minor
        }

        // Loop range bar on ruler bottom
        if let loop = p.loopRange {
            let a = x(for: loop.lowerBound)
            let b = x(for: loop.upperBound)
            Theme.accent.withAlphaComponent(0.45).setFill()
            CGRect(x: a, y: ruler.maxY - 4, width: max(b - a, 1), height: 4).fill()
        }

        // Selection range bar on ruler bottom
        if let range = model.selectionRange {
            let a = x(for: range.lowerBound)
            let b = x(for: range.upperBound)
            Theme.rangeSelection.withAlphaComponent(0.65).setFill()
            CGRect(x: a, y: ruler.maxY - 3, width: max(b - a, 1), height: 3).fill()
        }

        // Markers in ruler
        let sortedMarkers = p.markers.sorted { $0.time < $1.time }
        for (idx, marker) in sortedMarkers.enumerated() {
            let mx = x(for: marker.time).rounded()
            let color = Theme.trackColor(marker.colorIndex)
            let selected = model.selectedMarkerID == marker.id
            if selected {
                let nextTime = idx + 1 < sortedMarkers.count ? sortedMarkers[idx + 1].time : contentDuration
                let nx = x(for: nextTime).rounded()
                let zx0 = max(ruler.minX, mx)
                let zx1 = min(ruler.maxX, nx)
                if zx1 > zx0 {
                    color.withAlphaComponent(0.18).setFill()
                    CGRect(x: zx0, y: ruler.minY, width: zx1 - zx0, height: ruler.height).fill()
                }
            }
            guard mx >= ruler.minX - 60, mx <= ruler.maxX + 40 else { continue }
            let label = marker.name as NSString
            let labelW = min(ceil(label.size(withAttributes: TimelineStyle.markerLabel).width) + 8, 90)
            let pill = CGRect(x: mx, y: ruler.minY + 3, width: labelW, height: 13)
            (selected ? Theme.selection : color).setFill()
            let pillPath = NSBezierPath(roundedRect: pill, xRadius: 2.5, yRadius: 2.5)
            pillPath.fill()
            if selected {
                NSColor.white.withAlphaComponent(0.9).setStroke()
                pillPath.lineWidth = 1.0
                pillPath.stroke()
            }
            label.draw(
                with: pill.insetBy(dx: 4, dy: 0.5),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: TimelineStyle.markerLabel
            )
        }

        ctx.restoreGState()
    }

    private func drawCorner() {
        let p = project
        Theme.overview.setFill()
        CGRect(x: 0, y: 0, width: Metrics.headerWidth - 1, height: Metrics.overviewHeight - 1).fill()
        if p.hasMIDITracks {
            let info = "\(Int(p.bpm.rounded())) BPM · \(p.timeSignatureNumerator)/\(p.timeSignatureDenominator)" as NSString
            info.draw(at: CGPoint(x: 12, y: 7), withAttributes: TimelineStyle.rulerBar)
        } else {
            ("APERÇU GLOBAL" as NSString).draw(at: CGPoint(x: 12, y: 7), withAttributes: TimelineStyle.cornerDim)
        }

        Theme.ruler.setFill()
        CGRect(x: 0, y: Metrics.overviewHeight, width: Metrics.headerWidth - 1, height: Metrics.rulerHeight - 1).fill()
        ("MAG" as NSString).draw(
            at: CGPoint(x: 12, y: Metrics.overviewHeight + 6),
            withAttributes: model.snapping ? TimelineStyle.cornerOn : TimelineStyle.cornerDim
        )
        let trackCountText = "\(p.tracks.count) PISTE\(p.tracks.count > 1 ? "S" : "")" as NSString
        trackCountText.draw(at: CGPoint(x: 48, y: Metrics.overviewHeight + 6), withAttributes: TimelineStyle.cornerDim)
    }

    // MARK: Hover Edge & Snap Guide

    func hoverEdgeLine(project p: AudioProject, rows: [TrackRow]) -> CGRect? {
        guard let hit = hoverHit else { return nil }
        switch hit {
        case .clipEdge(let clipID, let edge):
            guard let (ti, ci) = p.clipLocation(of: clipID),
                  let row = rows.first(where: { $0.index == ti }) else { return nil }
            let block = clipRect(p.tracks[ti].clips[ci], in: row.rect)
            let ex = (edge == .start ? block.minX : block.maxX).rounded()
            let w = TimelineStyle.hoverEdgeWidth
            return CGRect(x: edge == .start ? ex : ex - w, y: block.minY, width: w, height: block.height)
        case .noteEdge(let noteID, let edge):
            guard let (ti, ni) = p.noteLocation(of: noteID),
                  let row = rows.first(where: { $0.index == ti }) else { return nil }
            let block = noteRect(p.tracks[ti].notes[ni], in: row)
            let ex = (edge == .start ? block.minX : block.maxX).rounded()
            let w = TimelineStyle.hoverEdgeWidth
            return CGRect(x: edge == .start ? ex : ex - w, y: block.minY, width: w, height: block.height)
        default:
            return nil
        }
    }

    private func drawGestureFeedback(_ ctx: CGContext, project p: AudioProject, rows: [TrackRow]) {
        if let guide = snapGuide {
            let gx = x(for: guide).rounded()
            Theme.snapGuide.setFill()
            let bottom = rows.last?.rect.maxY ?? laneArea.maxY
            CGRect(x: gx, y: laneArea.minY, width: 1, height: max(0, bottom - laneArea.minY)).fill()
        }
    }
}
