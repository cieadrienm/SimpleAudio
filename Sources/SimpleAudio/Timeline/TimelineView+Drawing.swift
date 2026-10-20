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
    static let markerLabel: [NSAttributedString.Key: Any] = [
        .font: Theme.font(9.5, .semibold),
        .foregroundColor: Theme.background,
    ]
    static let trackTitle: [NSAttributedString.Key: Any] = [
        .font: Theme.font(11.5, .semibold),
        .foregroundColor: Theme.text,
        .paragraphStyle: truncating,
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
        bounds.fill()

        let p = project
        let rows = trackRows(for: p)

        // 1. Track lanes
        ctx.saveGState()
        ctx.clip(to: laneArea)
        for row in rows {
            let r = CGRect(x: Metrics.headerWidth, y: row.rect.minY, width: laneWidth, height: row.rect.height)
            guard r.intersects(dirtyRect) else { continue }
            let isSelectedTrack = model.selectedTrackID == row.track.id
            let bg = isSelectedTrack ? Theme.laneSelected : (row.index % 2 == 0 ? Theme.lane : Theme.laneAlt)
            bg.setFill()
            r.fill()
            drawGrid(in: r)
            ctx.saveGState()
            ctx.clip(to: r)
            drawTrackLane(ctx, project: p, row: row, laneRect: r)
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

        // 2. Track headers (left column)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: Metrics.topBarHeight, width: Metrics.headerWidth - 1, height: laneArea.height))
        drawTrackHeaders(ctx, project: p, rows: rows)
        ctx.restoreGState()

        // 3. Overview minimap & Ruler (top bar)
        drawOverview(ctx, project: p)
        drawRuler(ctx, project: p)
        drawCorner()

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
        let mid = channelRect.midY
        let half = max(channelRect.height / 2 - 2, 1)
        let spp = secondsPerPoint
        let peakPath = CGMutablePath()
        let rmsPath = CGMutablePath()

        func columnMetrics(_ px: CGFloat) -> (peakH: CGFloat, rmsH: CGFloat) {
            let local = Double(px - clipRect.minX) * spp
            let srcTime = clip.reversed ? (clip.sourceStart + clip.duration - local) : (clip.sourceStart + local)
            let i0 = max(Int((srcTime * bps).rounded(.down)), 0)
            let i1 = min(max(i0 + 1, Int(((srcTime + spp) * bps).rounded(.up))), peaks.count)
            guard i0 < i1 else { return (0.5, 0.25) }
            var pMax: Float = 0
            var rMax: Float = 0
            for i in i0..<i1 {
                if peaks[i] > pMax { pMax = peaks[i] }
                if i < rms.count, rms[i] > rMax { rMax = rms[i] }
            }
            var scale = linearGain
            if hasFade {
                scale *= Float(clip.fadeGain(atLocalTime: local))
            }
            let pH = max(CGFloat(min(pMax * scale, 1.0)) * half, 0.5)
            let rH = max(CGFloat(min(rMax * scale, 1.0)) * half, 0.3)
            return (pH, min(rH, pH))
        }

        peakPath.move(to: CGPoint(x: from, y: mid))
        rmsPath.move(to: CGPoint(x: from, y: mid))

        var px = from
        while px <= to {
            let m = columnMetrics(px)
            peakPath.addLine(to: CGPoint(x: px, y: mid - m.peakH))
            rmsPath.addLine(to: CGPoint(x: px, y: mid - m.rmsH))
            px += 1
        }
        px -= 1
        while px >= from {
            let m = columnMetrics(px)
            peakPath.addLine(to: CGPoint(x: px, y: mid + m.peakH))
            rmsPath.addLine(to: CGPoint(x: px, y: mid + m.rmsH))
            px -= 1
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
        for marker in p.markers {
            let mx = x(for: marker.time).rounded()
            guard mx >= laneArea.minX, mx <= laneArea.maxX else { continue }
            let color = Theme.trackColor(marker.colorIndex)
            color.withAlphaComponent(0.45).setFill()
            CGRect(x: mx, y: laneArea.minY, width: 1, height: bottom - laneArea.minY).fill()
        }
    }

    // MARK: Track Headers

    private func drawTrackHeaders(_ ctx: CGContext, project p: AudioProject, rows: [TrackRow]) {
        Theme.header.setFill()
        CGRect(x: 0, y: Metrics.topBarHeight, width: Metrics.headerWidth - 1, height: laneArea.height).fill()

        for row in rows {
            let r = CGRect(x: 0, y: row.rect.minY, width: Metrics.headerWidth - 1, height: row.rect.height)
            let isSelected = model.selectedTrackID == row.track.id
            if isSelected {
                Theme.laneSelected.withAlphaComponent(0.75).setFill()
                r.fill()
            }
            let color = Theme.trackColor(row.track.colorIndex)
            color.setFill()
            CGRect(x: 0, y: r.minY, width: 3.5, height: r.height).fill()

            let controls = headerControlRects(in: row.rect)
            let titleWidth = max(20, controls.mute.minX - 16)
            (row.track.name as NSString).draw(
                with: CGRect(x: 11, y: r.minY + 8, width: titleWidth, height: 16),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: TimelineStyle.trackTitle
            )

            // Mute button (M)
            drawHeaderButton(rect: controls.mute, label: "M", active: row.track.mute, tint: Theme.muteColor)
            // Solo button (S)
            drawHeaderButton(rect: controls.solo, label: "S", active: row.track.solo, tint: Theme.soloColor)
            // Stereo L/R split button
            drawHeaderButton(rect: controls.stereo, label: "⊶", active: row.track.stereoSplit, tint: Theme.snapGuide)

            // Gain & Pan pills
            if r.height >= 54 {
                drawValuePill(rect: controls.gain, text: TimeFormat.decibels(row.track.gainDB))
                drawValuePill(rect: controls.pan, text: TimeFormat.pan(row.track.pan))
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

        // Draw combined miniature waveform across the whole project duration
        let fromX = area.minX + Metrics.leadIn
        let toX = area.maxX - Metrics.leadIn
        let spanW = max(toX - fromX, 1)
        let midY = area.midY
        let halfH = area.height / 2 - 3
        let dur = contentDuration

        if let firstClip = p.allClips.first?.clip,
           let wave = model.waveforms.envelope(for: model.resolvedURL(for: firstClip.path)),
           !wave.peaks.isEmpty {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: fromX, y: midY))
            var px = fromX
            while px <= toX {
                let t0 = Double((px - fromX) / spanW) * dur
                let t1 = Double((px + 1 - fromX) / spanW) * dur
                var peak: Float = 0
                for (_, _, c) in p.allClips where !c.mute && c.end >= t0 && c.offset <= t1 {
                    if let w = model.waveforms.envelope(for: model.resolvedURL(for: c.path)) {
                        let v = w.values(at: c.sourceStart + max(0, t0 - c.offset), window: max(0.01, t1 - t0))
                        let scaled = v.peak * Float(c.amplitude(atTimelineTime: max(c.offset, min(t0, c.end))))
                        if scaled > peak { peak = scaled }
                    }
                }
                let h = max(CGFloat(min(peak, 1)) * halfH, 0.5)
                path.addLine(to: CGPoint(x: px, y: midY - h))
                px += 2
            }
            px -= 2
            while px >= fromX {
                let t0 = Double((px - fromX) / spanW) * dur
                let t1 = Double((px + 1 - fromX) / spanW) * dur
                var peak: Float = 0
                for (_, _, c) in p.allClips where !c.mute && c.end >= t0 && c.offset <= t1 {
                    if let w = model.waveforms.envelope(for: model.resolvedURL(for: c.path)) {
                        let v = w.values(at: c.sourceStart + max(0, t0 - c.offset), window: max(0.01, t1 - t0))
                        let scaled = v.peak * Float(c.amplitude(atTimelineTime: max(c.offset, min(t0, c.end))))
                        if scaled > peak { peak = scaled }
                    }
                }
                let h = max(CGFloat(min(peak, 1)) * halfH, 0.5)
                path.addLine(to: CGPoint(x: px, y: midY + h))
                px -= 2
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(Theme.accent.withAlphaComponent(0.45).cgColor)
            ctx.fillPath()
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

        // Playhead line in overview
        let playX = overviewX(for: model.playhead).rounded()
        Theme.playhead.setFill()
        CGRect(x: playX, y: area.minY, width: 1.5, height: area.height).fill()

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
                (TimeFormat.rulerLabel(t, step: major) as NSString).draw(
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
        for marker in p.markers {
            let mx = x(for: marker.time).rounded()
            guard mx >= ruler.minX - 40, mx <= ruler.maxX + 40 else { continue }
            let color = Theme.trackColor(marker.colorIndex)
            let selected = model.selectedMarkerID == marker.id
            let label = marker.name as NSString
            let labelW = min(ceil(label.size(withAttributes: TimelineStyle.markerLabel).width) + 8, 90)
            let pill = CGRect(x: mx, y: ruler.minY + 3, width: labelW, height: 13)
            (selected ? Theme.selection : color).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 2.5, yRadius: 2.5).fill()
            label.draw(
                with: pill.insetBy(dx: 4, dy: 0.5),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: TimelineStyle.markerLabel
            )
        }

        ctx.restoreGState()
    }

    private func drawCorner() {
        Theme.overview.setFill()
        CGRect(x: 0, y: 0, width: Metrics.headerWidth - 1, height: Metrics.overviewHeight - 1).fill()
        ("APERÇU GLOBAL" as NSString).draw(at: CGPoint(x: 12, y: 7), withAttributes: TimelineStyle.cornerDim)

        Theme.ruler.setFill()
        CGRect(x: 0, y: Metrics.overviewHeight, width: Metrics.headerWidth - 1, height: Metrics.rulerHeight - 1).fill()
        ("MAG" as NSString).draw(
            at: CGPoint(x: 12, y: Metrics.overviewHeight + 6),
            withAttributes: model.snapping ? TimelineStyle.cornerOn : TimelineStyle.cornerDim
        )
        let trackCountText = "\(project.tracks.count) PISTE\(project.tracks.count > 1 ? "S" : "")" as NSString
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
