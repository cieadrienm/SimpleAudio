# SimpleAudio

Éditeur audio multipiste natif, ultra-léger (~3 Mo contre 250 Mo pour ocenaudio et 100 Mo pour Audacity) et rapide pour macOS, conçu dans le même esprit que **Montage** et **OSCScore** (**cie Adrien M**).

## Fonctionnalités

- **Formes d'ondes haute précision** : enveloppe Crête + RMS calculée à 400 Hz par seconde avec `Accelerate` (`vDSP`), affichage stéréo séparé L/R (`⊶`), aperçu global (minimap) en haut de la timeline, mise à l'échelle dynamique selon le gain et la courbe de fondu, et tracé au niveau de l'échantillon à fort niveau de zoom.
- **Fondus & Courbes mathématiques** : poignées de fondu d'entrée et de sortie en haut de chaque clip, fondu rapide sur plage sélectionnée, et 4 courbes au choix (*Courbe en S / cosinus*, *Linéaire*, *Exponentielle*, *Logarithmique*).
- **Édition sur plage temporelle ou par clips** :
  - Sélection de plage temporelle (`⇧+Glisser` sur un clip, glisser dans une piste vide, double-clic sur un clip, ou touches `I` / `O`).
  - Copier (`⌘C`), Couper (`⌘X`), Coller (`⌘V`), Dupliquer (`⌘D`), Scinder (`B` / `S` / `⌘K`), Rogner sur la plage (`⌘T`), Silencer la plage (`⇧⌘M`), Supprimer (`⌫`), Supprimer et raccorder / Ripple Delete (`⇧⌫`).
- **Multipiste & Lecture temps réel** :
  - Mixeur temps réel `AVAudioEngine` + `AVAudioSourceNode` à latence nulle (seek 0 ms), Gain dB, Panoramique stéréo, Muet (`M`), Solo (`S`), vumètre crête stéréo L/R à 60 Hz, boucle (`⌘L`) et marqueurs (`M`).
- **Export multiformat & Normalisation** :
  - Formats : **WAV** (16 / 24 / 32 bits float), **AIFF**, **CAF**, **M4A (AAC)**, **ALAC (Apple Lossless)**, **FLAC**, et **MP3** (via `ffmpeg` si présent).
  - Fréquences : 44,1 kHz, 48 kHz, 96 kHz — Stéréo ou Mono — Export du mixage Master ou de pistes séparées (*Stems*).
  - Normalisation crête (`-0.1 dBFS`) ou Loudness intégré ITU-R BS.1770-4 (`-14 LUFS`).
- **Automatisation MCP + HTTP (`/v1`) + OSC (UDP)** :
  - API HTTP locale sur `127.0.0.1:17910` (`SIMPLEAUDIO_API_PORT`) avec flux SSE `/v1/events`.
  - Serveur MCP stdio `simpleaudio-mcp` intégré dans le bundle `.app` et configuré via `.mcp.json`.
  - Entrée OSC UDP sur `:9110` (`SIMPLEAUDIO_OSC_IN_PORT`) et retour OSC optionnel vers `:9111`.

## Compilation & Installation

```bash
# Générer l'icône et assembler /Applications/SimpleAudio.app
chmod +x Scripts/bundle.sh
Scripts/bundle.sh release

# Lancer la suite de tests unitaires et d'intégration
swift test

# Auto-test de bout en bout et capture PNG sans interaction manuelle
.build/debug/SimpleAudio --self-test
.build/debug/SimpleAudio --snapshot /tmp/simpleaudio.png
```

## Crédits

**cie Adrien M** (Compagnie Adrien M) — Bundle ID : `net.cieadrienm.simpleaudio`.
