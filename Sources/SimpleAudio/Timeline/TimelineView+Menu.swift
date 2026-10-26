import AppKit
import SimpleAudioCore

extension TimelineView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let pt = convert(event.locationInWindow, from: nil)
        let h = hit(at: pt)
        let clickTime = max(0, time(for: pt.x))
        let menu = NSMenu()

        // If right-clicking inside an active selection range, offer range actions first
        if let range = model.selectionRange,
           range.upperBound > range.lowerBound + 1e-4,
           clickTime >= range.lowerBound && clickTime <= range.upperBound {
            addItem(menu, L("Copier la plage (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))", "Copy Range (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))"), action: #selector(ctxCopy))
            addItem(menu, L("Couper la plage", "Cut Range"), action: #selector(ctxCut))
            addItem(menu, L("Rogner sur la plage (Crop)", "Crop to Range"), action: #selector(ctxCropRange))
            addItem(menu, L("Silencer la plage", "Silence Range"), action: #selector(ctxSilenceRange))
            menu.addItem(.separator())
            addItem(menu, L("Fondu d'entrée sur la plage", "Fade In on Range"), action: #selector(ctxFadeInRange))
            addItem(menu, L("Fondu de sortie sur la plage", "Fade Out on Range"), action: #selector(ctxFadeOutRange))
            menu.addItem(.separator())
            addItem(menu, L("Supprimer la plage", "Delete Range"), action: #selector(ctxDelete))
            addItem(menu, L("Supprimer et raccorder la plage", "Ripple Delete Range"), action: #selector(ctxRippleDelete))
            addItem(menu, L("Boucler sur la plage", "Loop Range"), action: #selector(ctxLoopRange))
            menu.addItem(.separator())
        }

        switch h {
        case .clipBody(let clipID, _), .clipEdge(let clipID, _), .fadeHandle(let clipID, _):
            if !model.selectedClips.contains(clipID) {
                model.selectedClips = [clipID]
            }
            if let (ti, _) = project.clipLocation(of: clipID) {
                model.selectedTrackID = project.tracks[ti].id
            }
            needsDisplay = true

            addItem(menu, L("Scinder ici", "Split Here"), action: #selector(ctxSplitAtClick(_:)), represented: clickTime)
            addItem(menu, L("Sélectionner la plage du clip", "Select Clip Range"), action: #selector(ctxSelectClipRange(_:)), represented: clipID)
            menu.addItem(.separator())
            addItem(menu, L("Copier", "Copy"), action: #selector(ctxCopy))
            addItem(menu, L("Couper", "Cut"), action: #selector(ctxCut))
            addItem(menu, L("Dupliquer le clip", "Duplicate Clip"), action: #selector(ctxDuplicate))
            menu.addItem(.separator())
            addItem(menu, L("Normaliser à -0.1 dBFS", "Normalize to -0.1 dBFS"), action: #selector(ctxNormalize))
            addItem(menu, L("Supprimer les silences aux extrémités", "Strip Silence at Edges"), action: #selector(ctxStripSilence))
            addItem(menu, L("Inverser le sens (Reverse)", "Reverse Clip"), action: #selector(ctxReverse))
            addItem(menu, L("Activer/Couper le son du clip", "Mute/Unmute Clip"), action: #selector(ctxToggleClipMute))

            // Fade shape submenu
            let shapeMenu = NSMenu()
            for shape in FadeShape.allCases {
                let item = NSMenuItem(title: shape.label, action: #selector(ctxSetFadeShape(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = shape.rawValue
                if let (_, _, c) = project.allClips.first(where: { $0.clip.id == clipID }), c.fadeShape == shape {
                    item.state = .on
                }
                shapeMenu.addItem(item)
            }
            let shapeParent = NSMenuItem(title: L("Courbe de fondu", "Fade Curve"), action: nil, keyEquivalent: "")
            shapeParent.submenu = shapeMenu
            menu.addItem(shapeParent)

            menu.addItem(.separator())
            addItem(menu, L("Supprimer", "Delete"), action: #selector(ctxDelete))
            addItem(menu, L("Supprimer et raccorder", "Ripple Delete"), action: #selector(ctxRippleDelete))

        case .noteBody(let noteID, _), .noteEdge(let noteID, _):
            if !model.selectedNotes.contains(noteID) {
                model.selectedNotes = [noteID]
                model.selectedClips.removeAll()
            }
            if let (ti, _) = project.noteLocation(of: noteID) {
                model.selectedTrackID = project.tracks[ti].id
            }
            needsDisplay = true

            addItem(menu, L("Scinder la note ici", "Split Note Here"), action: #selector(ctxSplitAtClick(_:)), represented: clickTime)
            addItem(menu, L("Quantifier à la double-croche (1/16)", "Quantize to 1/16th Note"), action: #selector(ctxQuantize))
            menu.addItem(.separator())
            addItem(menu, L("Transposer +1 demi-ton", "Transpose +1 Semitone"), action: #selector(ctxTransposeUp1))
            addItem(menu, L("Transposer −1 demi-ton", "Transpose −1 Semitone"), action: #selector(ctxTransposeDown1))
            addItem(menu, L("Transposer +1 octave (+12)", "Transpose +1 Octave (+12)"), action: #selector(ctxTransposeUp12))
            addItem(menu, L("Transposer −1 octave (−12)", "Transpose −1 Octave (−12)"), action: #selector(ctxTransposeDown12))
            menu.addItem(.separator())
            addItem(menu, L("Copier", "Copy"), action: #selector(ctxCopy))
            addItem(menu, L("Couper", "Cut"), action: #selector(ctxCut))
            addItem(menu, L("Dupliquer la note", "Duplicate Note"), action: #selector(ctxDuplicate))
            addItem(menu, L("Activer/Couper le son de la note", "Mute/Unmute Note"), action: #selector(ctxToggleClipMute))
            menu.addItem(.separator())
            addItem(menu, L("Supprimer", "Delete"), action: #selector(ctxDelete))
            addItem(menu, L("Supprimer et raccorder", "Ripple Delete"), action: #selector(ctxRippleDelete))

        case .header(let ctrl):
            let trackID: UUID
            switch ctrl {
            case .mute(let id), .solo(let id), .stereoSplit(let id), .pianoRoll(let id), .gain(let id), .pan(let id), .title(let id):
                trackID = id
            }
            model.selectedTrackID = trackID
            let isMIDI = project.trackIndex(of: trackID).map { project.tracks[$0].isMIDI } ?? false
            if isMIDI {
                addItem(menu, L("Ouvrir/Réduire le Piano-Roll (P)", "Expand/Collapse Piano Roll (P)"), action: #selector(ctxTogglePianoRoll(_:)), represented: trackID)
                addItem(menu, L("Rendre la piste MIDI en piste Audio (WAV)", "Bounce MIDI Track to Audio Track (WAV)"), action: #selector(ctxBounceMIDIToAudio(_:)), represented: trackID)
                addItem(menu, L("Convertir la piste MIDI en Audio sur place", "Convert MIDI Track to Audio In Place"), action: #selector(ctxReplaceMIDIWithAudio(_:)), represented: trackID)
                menu.addItem(.separator())
            } else {
                addItem(menu, L("Afficher/Masquer les canaux L/R", "Show/Hide L/R Channels"), action: #selector(ctxToggleStereo(_:)), represented: trackID)
            }
            addItem(menu, L("Dupliquer la piste", "Duplicate Track"), action: #selector(ctxDuplicateTrack))
            if project.tracks.count > 1, let ti = project.trackIndex(of: trackID) {
                if ti > 0 {
                    addItem(menu, L("Monter la piste (⌥↑)", "Move Track Up (⌥↑)"), action: #selector(ctxMoveTrackUp(_:)), represented: trackID)
                }
                if ti < project.tracks.count - 1 {
                    addItem(menu, L("Descendre la piste (⌥↓)", "Move Track Down (⌥↓)"), action: #selector(ctxMoveTrackDown(_:)), represented: trackID)
                }
            }
            addItem(menu, L("Ajouter une piste audio", "Add Audio Track"), action: #selector(ctxAddTrack))
            addItem(menu, L("Ajouter une piste MIDI", "Add MIDI Track"), action: #selector(ctxAddMIDITrack))
            if project.tracks.count > 1 {
                menu.addItem(.separator())
                addItem(menu, L("Supprimer la piste", "Delete Track"), action: #selector(ctxRemoveTrack))
            }

        case .marker(let id):
            model.selectedMarkerID = id
            addItem(menu, L("Aller au marqueur", "Go to Marker"), action: #selector(ctxGoToMarker(_:)), represented: id)
            addItem(menu, L("Supprimer le marqueur", "Delete Marker"), action: #selector(ctxRemoveMarker(_:)), represented: id)

        default:
            if !model.clipboard.isEmpty || !model.noteClipboard.isEmpty {
                addItem(menu, L("Coller ici", "Paste Here"), action: #selector(ctxPasteAtClick(_:)), represented: clickTime)
                menu.addItem(.separator())
            }
            addItem(menu, L("Importer des fichiers audio ou MIDI…", "Import Audio or MIDI Files…"), action: #selector(ctxImportAudio))
            addItem(menu, L("Ajouter un marqueur ici", "Add Marker Here"), action: #selector(ctxAddMarkerAtClick(_:)), represented: clickTime)
            addItem(menu, L("Ajouter une piste audio", "Add Audio Track"), action: #selector(ctxAddTrack))
            addItem(menu, L("Ajouter une piste MIDI", "Add MIDI Track"), action: #selector(ctxAddMIDITrack))
            menu.addItem(.separator())
            addItem(menu, L("Ajuster le zoom à la fenêtre", "Zoom to Fit Window"), action: #selector(ctxZoomFit))
        }

        return menu
    }

    private func addItem(_ menu: NSMenu, _ title: String, action: Selector, represented: Any? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = represented
        menu.addItem(item)
    }

    @objc private func ctxCopy() { model.copySelection() }
    @objc private func ctxCut() { model.cutSelection() }
    @objc private func ctxDuplicate() { model.duplicateSelectedClips() }
    @objc private func ctxCropRange() { model.cropToSelection() }
    @objc private func ctxSilenceRange() { model.silenceSelection() }
    @objc private func ctxFadeInRange() { model.applyFadeIn(duration: 0.5) }
    @objc private func ctxFadeOutRange() { model.applyFadeOut(duration: 0.5) }
    @objc private func ctxDelete() { model.deleteSelection(ripple: false) }
    @objc private func ctxRippleDelete() { model.deleteSelection(ripple: true) }
    @objc private func ctxNormalize() { model.normalizeSelectedClips(targetDB: -0.1) }
    @objc private func ctxStripSilence() { model.stripSilenceOnSelected() }
    @objc private func ctxReverse() { model.reverseSelectedClips() }
    @objc private func ctxToggleClipMute() { model.toggleMuteSelectedClips() }
    @objc private func ctxAddTrack() { model.addTrack() }
    @objc private func ctxAddMIDITrack() { _ = model.addMIDITrack() }
    @objc private func ctxDuplicateTrack() { model.duplicateSelectedTrack() }
    @objc private func ctxRemoveTrack() { model.removeSelectedTrack() }

    @objc private func ctxMoveTrackUp(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.moveTrack(id, by: -1)
    }

    @objc private func ctxMoveTrackDown(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.moveTrack(id, by: 1)
    }
    @objc private func ctxImportAudio() { model.importAudioPanel() }
    @objc private func ctxZoomFit() { fit() }
    @objc private func ctxQuantize() { model.quantizeSelection() }
    @objc private func ctxTransposeUp1() { model.transposeSelection(semitones: 1) }
    @objc private func ctxTransposeDown1() { model.transposeSelection(semitones: -1) }
    @objc private func ctxTransposeUp12() { model.transposeSelection(semitones: 12) }
    @objc private func ctxTransposeDown12() { model.transposeSelection(semitones: -12) }

    @objc private func ctxTogglePianoRoll(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.toggleTrackPianoRoll(id)
    }

    @objc private func ctxBounceMIDIToAudio(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        _ = model.bounceMIDITrackToAudio(id, replaceMIDITrack: false)
    }

    @objc private func ctxReplaceMIDIWithAudio(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        _ = model.bounceMIDITrackToAudio(id, replaceMIDITrack: true)
    }

    @objc private func ctxLoopRange() {
        guard let range = model.selectionRange else { return }
        model.store.perform(L("Définir la boucle", "Set Loop")) { proj in
            proj.loopRange = range
        }
    }

    @objc private func ctxSplitAtClick(_ sender: NSMenuItem) {
        guard let t = sender.representedObject as? Double else { return }
        model.seek(to: t)
        model.splitAtPlayhead()
    }

    @objc private func ctxSelectClipRange(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let (ti, ci) = project.clipLocation(of: id) else { return }
        let clip = project.tracks[ti].clips[ci]
        model.selectionRange = clip.offset...clip.end
        needsDisplay = true
    }

    @objc private func ctxSetFadeShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let shape = FadeShape(rawValue: raw) else { return }
        let ids = model.selectedClips
        model.store.perform(L("Courbe de fondu", "Fade Curve")) { proj in
            for id in ids {
                try? Operations.setFade(&proj, id: id, shape: shape)
            }
        }
    }

    @objc private func ctxToggleStereo(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.toggleTrackStereoSplit(id)
    }

    @objc private func ctxGoToMarker(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let marker = project.markers.first(where: { $0.id == id }) else { return }
        model.seek(to: marker.time)
    }

    @objc private func ctxRemoveMarker(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.removeMarker(id)
    }

    @objc private func ctxPasteAtClick(_ sender: NSMenuItem) {
        guard let t = sender.representedObject as? Double else { return }
        model.seek(to: t)
        model.pasteAtPlayhead()
    }

    @objc private func ctxAddMarkerAtClick(_ sender: NSMenuItem) {
        guard let t = sender.representedObject as? Double else { return }
        model.seek(to: t)
        model.addMarkerAtPlayhead()
    }
}
