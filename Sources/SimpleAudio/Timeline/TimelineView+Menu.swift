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
            addItem(menu, "Copier la plage (\(TimeFormat.shortDuration(range.upperBound - range.lowerBound)))", action: #selector(ctxCopy))
            addItem(menu, "Couper la plage", action: #selector(ctxCut))
            addItem(menu, "Rogner sur la plage (Crop)", action: #selector(ctxCropRange))
            addItem(menu, "Silencer la plage", action: #selector(ctxSilenceRange))
            menu.addItem(.separator())
            addItem(menu, "Fondu d'entrée sur la plage", action: #selector(ctxFadeInRange))
            addItem(menu, "Fondu de sortie sur la plage", action: #selector(ctxFadeOutRange))
            menu.addItem(.separator())
            addItem(menu, "Supprimer la plage", action: #selector(ctxDelete))
            addItem(menu, "Supprimer et raccorder la plage", action: #selector(ctxRippleDelete))
            addItem(menu, "Boucler sur la plage", action: #selector(ctxLoopRange))
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

            addItem(menu, "Scinder ici", action: #selector(ctxSplitAtClick(_:)), represented: clickTime)
            addItem(menu, "Sélectionner la plage du clip", action: #selector(ctxSelectClipRange(_:)), represented: clipID)
            menu.addItem(.separator())
            addItem(menu, "Copier", action: #selector(ctxCopy))
            addItem(menu, "Couper", action: #selector(ctxCut))
            addItem(menu, "Dupliquer le clip", action: #selector(ctxDuplicate))
            menu.addItem(.separator())
            addItem(menu, "Normaliser à -0.1 dBFS", action: #selector(ctxNormalize))
            addItem(menu, "Supprimer les silences aux extrémités", action: #selector(ctxStripSilence))
            addItem(menu, "Inverser le sens (Reverse)", action: #selector(ctxReverse))
            addItem(menu, "Activer/Couper le son du clip", action: #selector(ctxToggleClipMute))

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
            let shapeParent = NSMenuItem(title: "Courbe de fondu", action: nil, keyEquivalent: "")
            shapeParent.submenu = shapeMenu
            menu.addItem(shapeParent)

            menu.addItem(.separator())
            addItem(menu, "Supprimer", action: #selector(ctxDelete))
            addItem(menu, "Supprimer et raccorder", action: #selector(ctxRippleDelete))

        case .noteBody(let noteID, _), .noteEdge(let noteID, _):
            if !model.selectedNotes.contains(noteID) {
                model.selectedNotes = [noteID]
                model.selectedClips.removeAll()
            }
            if let (ti, _) = project.noteLocation(of: noteID) {
                model.selectedTrackID = project.tracks[ti].id
            }
            needsDisplay = true

            addItem(menu, "Scinder la note ici", action: #selector(ctxSplitAtClick(_:)), represented: clickTime)
            addItem(menu, "Quantifier à la double-croche (1/16)", action: #selector(ctxQuantize))
            menu.addItem(.separator())
            addItem(menu, "Transposer +1 demi-ton", action: #selector(ctxTransposeUp1))
            addItem(menu, "Transposer −1 demi-ton", action: #selector(ctxTransposeDown1))
            addItem(menu, "Transposer +1 octave (+12)", action: #selector(ctxTransposeUp12))
            addItem(menu, "Transposer −1 octave (−12)", action: #selector(ctxTransposeDown12))
            menu.addItem(.separator())
            addItem(menu, "Copier", action: #selector(ctxCopy))
            addItem(menu, "Couper", action: #selector(ctxCut))
            addItem(menu, "Dupliquer la note", action: #selector(ctxDuplicate))
            addItem(menu, "Activer/Couper le son de la note", action: #selector(ctxToggleClipMute))
            menu.addItem(.separator())
            addItem(menu, "Supprimer", action: #selector(ctxDelete))
            addItem(menu, "Supprimer et raccorder", action: #selector(ctxRippleDelete))

        case .header(let ctrl):
            let trackID: UUID
            switch ctrl {
            case .mute(let id), .solo(let id), .stereoSplit(let id), .pianoRoll(let id), .gain(let id), .pan(let id), .title(let id):
                trackID = id
            }
            model.selectedTrackID = trackID
            let isMIDI = project.trackIndex(of: trackID).map { project.tracks[$0].isMIDI } ?? false
            if isMIDI {
                addItem(menu, "Ouvrir/Réduire le Piano-Roll (P)", action: #selector(ctxTogglePianoRoll(_:)), represented: trackID)
                addItem(menu, "Rendre la piste MIDI en piste Audio (WAV)", action: #selector(ctxBounceMIDIToAudio(_:)), represented: trackID)
                addItem(menu, "Convertir la piste MIDI en Audio sur place", action: #selector(ctxReplaceMIDIWithAudio(_:)), represented: trackID)
                menu.addItem(.separator())
            } else {
                addItem(menu, "Afficher/Masquer les canaux L/R", action: #selector(ctxToggleStereo(_:)), represented: trackID)
            }
            addItem(menu, "Dupliquer la piste", action: #selector(ctxDuplicateTrack))
            if project.tracks.count > 1, let ti = project.trackIndex(of: trackID) {
                if ti > 0 {
                    addItem(menu, "Monter la piste (⌥↑)", action: #selector(ctxMoveTrackUp(_:)), represented: trackID)
                }
                if ti < project.tracks.count - 1 {
                    addItem(menu, "Descendre la piste (⌥↓)", action: #selector(ctxMoveTrackDown(_:)), represented: trackID)
                }
            }
            addItem(menu, "Ajouter une piste audio", action: #selector(ctxAddTrack))
            addItem(menu, "Ajouter une piste MIDI", action: #selector(ctxAddMIDITrack))
            if project.tracks.count > 1 {
                menu.addItem(.separator())
                addItem(menu, "Supprimer la piste", action: #selector(ctxRemoveTrack))
            }

        case .marker(let id):
            model.selectedMarkerID = id
            addItem(menu, "Aller au marqueur", action: #selector(ctxGoToMarker(_:)), represented: id)
            addItem(menu, "Supprimer le marqueur", action: #selector(ctxRemoveMarker(_:)), represented: id)

        default:
            if !model.clipboard.isEmpty || !model.noteClipboard.isEmpty {
                addItem(menu, "Coller ici", action: #selector(ctxPasteAtClick(_:)), represented: clickTime)
                menu.addItem(.separator())
            }
            addItem(menu, "Importer des fichiers audio ou MIDI…", action: #selector(ctxImportAudio))
            addItem(menu, "Ajouter un marqueur ici", action: #selector(ctxAddMarkerAtClick(_:)), represented: clickTime)
            addItem(menu, "Ajouter une piste audio", action: #selector(ctxAddTrack))
            addItem(menu, "Ajouter une piste MIDI", action: #selector(ctxAddMIDITrack))
            menu.addItem(.separator())
            addItem(menu, "Ajuster le zoom à la fenêtre", action: #selector(ctxZoomFit))
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
        model.store.perform("Définir la boucle") { proj in
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
        model.store.perform("Courbe de fondu") { proj in
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
