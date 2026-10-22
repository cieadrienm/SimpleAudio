# SimpleAudio

Éditeur audio et MIDI multipiste natif, ultra-léger (~4,8 Mo contre 250 Mo pour ocenaudio et 100 Mo pour Audacity) et fluide à **60 Hz / 120 Hz ProMotion** pour macOS, conçu dans le même esprit que **Montage** et **OSCScore** (**cie Adrien M**).

## Fonctionnalités

- **Formes d'ondes haute précision & fluidité 120 Hz ProMotion** :
  - Enveloppe Crête + RMS calculée à 400 Hz par seconde avec `Accelerate` (`vDSP`), affichage stéréo séparé L/R (`⊶`), mini-carte d'aperçu global mise en cache vectorielle, mise à l'échelle dynamique selon le gain et la courbe de fondu, et tracé au niveau de l'échantillon à fort niveau de zoom.
  - Tête de lecture 100 % GPU interpolée à 120 Hz entre les buffers audio et animations élastiques de zoom/scroll pilotées par `CADisplayLink`.
- **Éditeur MIDI & Piano-Roll intégré (SimpleMIDIPlayer)** :
  - Import et export natifs de fichiers MIDI Standard (`.mid` / `.midi` / `.smf` Format 0 & 1).
  - Piano-Roll multipiste avec clavier latéral interactif, création/déplacement/rognage de notes, quantification (`Q`), transposition (`↑`/`↓`, `⇧↑`/`⇧↓`), sélection de 128 instruments General MIDI + kits de batterie GM (canal 10).
  - Synthèse temps réel via `AVAudioUnitMIDIInstrument` (`kAudioUnitSubType_MIDISynth`) avec support des banques SoundFont `.sf2` / `.dls` et synthétiseur analytique FM/additif de secours.
  - Conversion / bounce direct d'une piste MIDI en piste Audio WAV 24 bits sur la timeline.
- **Fondus & Courbes mathématiques** : poignées de fondu d'entrée et de sortie en haut de chaque clip, fondu rapide sur plage sélectionnée (`⌃I` / `⌃O`), fondu enchaîné (`X`), et 4 courbes au choix (*Courbe en S / cosinus*, *Linéaire*, *Exponentielle*, *Logarithmique*).
- **Édition sur plage temporelle, par clips ou par notes** :
  - Sélection de plage temporelle (`⇧+Glisser`, glisser dans une piste vide, double-clic sur un clip/note, ou touches `I` / `O`).
  - Copier (`⌘C`), Couper (`⌘X`), Coller (`⌘V`), Dupliquer (`⌘D`), Scinder (`B` / `S` / `⌘K`), Rogner sur la plage (`⌘T`), Silencer la plage (`⇧⌘M`), Supprimer (`⌫`), Supprimer et raccorder / Ripple Delete (`⇧⌫`).
- **Multipiste, Réorganisation & Lecture temps réel** :
  - Réorganisation des pistes par glisser-déposer vertical de l'en-tête de piste, boutons `↑`/`↓` dans la barre latérale et l'inspecteur, ou raccourcis `⌥↑` / `⌥↓`.
  - Mixeur temps réel `AVAudioEngine` + `AVAudioSourceNode` à latence nulle, Gain dB, Panoramique stéréo, Muet (`M`), Solo (`S`), vumètre crête stéréo L/R, boucle (`L` / `⌘L`) et marqueurs (`K`) avec zoom intelligent à 3 niveaux (`Z`).
- **Export multiformat & Normalisation** :
  - Formats : **WAV** (16 / 24 / 32 bits float), **AIFF**, **CAF**, **M4A (AAC)**, **ALAC (Apple Lossless)**, **FLAC**, **MP3** et **MIDI (`.mid`)**.
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
