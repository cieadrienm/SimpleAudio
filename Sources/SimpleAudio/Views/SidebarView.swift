import SwiftUI
import SimpleAudioCore

struct SidebarView: View {
    @Bindable var model: AppModel

    private var project: AudioProject { model.store.project }

    private struct SourceFileEntry: Identifiable {
        var id: String { path }
        let path: String
        let name: String
        let duration: Double
        let clipID: UUID
        let trackID: UUID
    }

    private var sourceFiles: [SourceFileEntry] {
        var seen = Set<String>()
        var result: [SourceFileEntry] = []
        for (_, trackID, clip) in project.allClips {
            if seen.insert(clip.path).inserted {
                let fileName = URL(fileURLWithPath: clip.path).lastPathComponent
                result.append(
                    SourceFileEntry(
                        path: clip.path,
                        name: fileName.isEmpty ? clip.name : fileName,
                        duration: clip.sourceDuration,
                        clipID: clip.id,
                        trackID: trackID
                    )
                )
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Tracks Section
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader("Pistes") {
                            HStack(spacing: 6) {
                                Button {
                                    model.addMIDITrack()
                                } label: {
                                    Image(systemName: "pianokeys")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(nsColor: Theme.textDim))
                                }
                                .buttonStyle(.plain)
                                .help("Ajouter une piste MIDI")

                                Button {
                                    model.addTrack()
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(nsColor: Theme.textDim))
                                }
                                .buttonStyle(.plain)
                                .help("Ajouter une piste audio (⌥⌘N)")
                            }
                        }

                        ForEach(project.tracks) { track in
                            trackRow(track)
                        }
                    }

                    Divider().overlay(Color(nsColor: Theme.separator))

                    // 2. Audio Files Section
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader("Fichiers audio") {
                            Button {
                                model.importAudioPanel()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(nsColor: Theme.textDim))
                            }
                            .buttonStyle(.plain)
                            .help("Importer des fichiers audio (⌘I)")
                        }

                        if sourceFiles.isEmpty {
                            Text("Aucun fichier importé")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: Theme.textFaint))
                                .padding(.vertical, 4)
                        } else {
                            ForEach(sourceFiles) { entry in
                                fileRow(entry)
                            }
                        }
                    }

                    Divider().overlay(Color(nsColor: Theme.separator))

                    // 3. Markers Section
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader("Marqueurs") {
                            Button {
                                model.addMarkerAtPlayhead()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(nsColor: Theme.textDim))
                            }
                            .buttonStyle(.plain)
                            .help("Ajouter un marqueur à la tête de lecture (M)")
                        }

                        if project.markers.isEmpty {
                            Text("Aucun marqueur")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: Theme.textFaint))
                                .padding(.vertical, 4)
                        } else {
                            ForEach(project.markers) { marker in
                                markerRow(marker)
                            }
                        }
                    }
                }
                .padding(12)
            }

            Spacer(minLength: 0)

            // Bottom quick action bar
            HStack(spacing: 5) {
                TextButton(title: "Importer…", symbol: "waveform.badge.plus", compact: true) {
                    model.importAudioPanel()
                }
                Spacer(minLength: 2)
                TextButton(title: "+ Audio", compact: true) {
                    model.addTrack()
                }
                TextButton(title: "+ MIDI", compact: true) {
                    model.addMIDITrack()
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.18))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(nsColor: Theme.separator))
                    .frame(height: 1)
            }
        }
        .frame(width: 216)
        .background(Color(nsColor: Theme.panel))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: Theme.separator))
                .frame(width: 1)
        }
    }

    private func trackRow(_ track: AudioTrack) -> some View {
        let selected = model.selectedTrackID == track.id
        let trackIdx = project.trackIndex(of: track.id) ?? 0
        let totalTracks = project.tracks.count
        return HStack(spacing: 6) {
            Circle()
                .fill(Color(nsColor: Theme.trackColor(track.colorIndex)))
                .frame(width: 8, height: 8)
            if track.isMIDI {
                Image(systemName: "pianokeys")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(nsColor: Theme.accent))
            }
            Text(track.name)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(Color(nsColor: Theme.text))
                .lineLimit(1)
            Spacer(minLength: 2)
            if track.mute {
                Text("M")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(nsColor: Theme.background))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(nsColor: Theme.muteColor)))
            }
            if track.solo {
                Text("S")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(nsColor: Theme.background))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2.5).fill(Color(nsColor: Theme.soloColor)))
            }
            Text(track.isMIDI ? "\(track.notes.count)♩" : "\(track.clips.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.textFaint))
            if totalTracks > 1 {
                HStack(spacing: 1) {
                    Button {
                        model.moveTrack(track.id, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color(nsColor: trackIdx > 0 ? Theme.textDim : Theme.textFaint.withAlphaComponent(0.3)))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(trackIdx == 0)
                    .help("Monter la piste (⌥↑)")

                    Button {
                        model.moveTrack(track.id, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Color(nsColor: trackIdx < totalTracks - 1 ? Theme.textDim : Theme.textFaint.withAlphaComponent(0.3)))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .disabled(trackIdx >= totalTracks - 1)
                    .help("Descendre la piste (⌥↓)")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.white.opacity(0.09) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedTrackID = track.id
        }
        .contextMenu {
            if totalTracks > 1 {
                Button("Monter la piste (⌥↑)") {
                    model.moveTrack(track.id, by: -1)
                }
                .disabled(trackIdx == 0)

                Button("Descendre la piste (⌥↓)") {
                    model.moveTrack(track.id, by: 1)
                }
                .disabled(trackIdx >= totalTracks - 1)

                Divider()
            }
            Button("Dupliquer la piste") {
                model.selectedTrackID = track.id
                model.duplicateSelectedTrack()
            }
            if totalTracks > 1 {
                Button("Supprimer la piste", role: .destructive) {
                    model.selectedTrackID = track.id
                    model.removeSelectedTrack()
                }
            }
        }
    }

    private func fileRow(_ entry: SidebarView.SourceFileEntry) -> some View {
        let selected = model.selectedClips.contains(entry.clipID)
        return HStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(nsColor: Theme.accent))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(nsColor: Theme.text))
                    .lineLimit(1)
                Text(TimeFormat.shortDuration(entry.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(nsColor: Theme.textFaint))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedClips = [entry.clipID]
            model.selectedTrackID = entry.trackID
        }
    }

    private func markerRow(_ marker: AudioMarker) -> some View {
        let selected = model.selectedMarkerID == marker.id
        return HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: Theme.trackColor(marker.colorIndex)))
                .frame(width: 4, height: 12)
            Text(marker.name)
                .font(.system(size: 11.5))
                .foregroundStyle(Color(nsColor: Theme.text))
                .lineLimit(1)
            Spacer()
            Text(TimeFormat.timecode(marker.time))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(nsColor: Theme.textDim))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedMarkerID = marker.id
            model.seek(to: marker.time)
        }
    }
}
