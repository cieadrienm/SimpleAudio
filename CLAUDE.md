# Instructions Agent — SimpleAudio

## Identité & Crédits
- Compagnie : **cie Adrien M** (ou **Compagnie Adrien M**).
- Identifiant de bundle : `net.cieadrienm.simpleaudio`.

## Architecture
- `Sources/SimpleAudioCore` : Modèle pur (`AudioProject`, `AudioTrack`, `AudioClip`, `FadeShape`, `AudioMarker`, `ClipboardSlice`), opérations d'édition (`Operations`), magasin de document à chemin d'écriture unique (`DocumentStore.perform`), et encodeur/décodeur OSC 1.0/1.1 (`OSCCodec`). Aucune dépendance UI.
- `Sources/SimpleAudioEngine` : Décodage et cache d'enveloppes 400 Hz Crête + RMS + L/R (`WaveformCache`, `PCMStore`), analyse audio (`AudioAnalysis` : détection de silences, passage par zéro, mesure LUFS ITU-R BS.1770-4 via `vDSP_biquad`), moteur de lecture temps réel (`PlaybackEngine` via `AVAudioEngine` + `AVAudioSourceNode`), export multiformat (`AudioExporter`), et générateur de fixtures synthétiques (`SyntheticAudio`).
- `Sources/SimpleAudio` : Interface macOS native (SwiftUI + `TimelineView` AppKit haute performance sans allocations par trame dans `draw(_:)`), serveur HTTP `/v1` (`:17910`), et serveur OSC UDP (`:9110`).
- `Sources/SimpleAudioMCPCore` & `Sources/simpleaudio-mcp` : Serveur MCP JSON-RPC 2.0 sur stdio, relié à l'API HTTP `/v1`.

## Vérification
- Toujours valider par `swift test`, `.build/debug/SimpleAudio --self-test` et `.build/debug/SimpleAudio --snapshot /tmp/simpleaudio.png`.
- Pour mettre à jour `/Applications/SimpleAudio.app`, exécuter `Scripts/bundle.sh release`.
