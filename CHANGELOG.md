Changelog
=========

The version is `VERSION` in `Scripts/bundle.sh`; each release is tagged `vX.Y.Z` in git.

0.9.0 — 2026-10-20
------------------

Première version numérotée.

- Éditeur audio multipiste natif macOS ultra-léger (~3,4 Mo), dans la lignée visuelle de Montage et OSCScore.
- Formes d’onde Peak + RMS multi-résolution accélérées par vDSP, affichage stéréo L/R séparé et minimap globale interactive.
- Montage non destructif : découpe (B / S), sélection de plage temporelle (I / O ou ⇧-glisser), copier-coller, rognage, glissement source (⌥-glisser) et 4 courbes de fondu (Cosinus, Linéaire, Exponentiel, Logarithmique).
- Touche `Z` pour basculer entre la vue d’ensemble du projet entier et un zoom centré sur la tête de lecture (ou la plage sélectionnée).
- Moteur de lecture temps réel `AVAudioEngine` sans allocation sur le thread audio, normalisation Peak (-0.1 dBFS) et EBU R128 (-14 LUFS), élagage des silences et inversion du sens de lecture.
- Export multi-format (WAV 16/24/32-bit float, AIFF, CAF, M4A AAC, ALAC, FLAC, MP3) et export par pistes séparées (stems).
- Contrôle temps réel par OSC (UDP `:9110`), API HTTP locale (`127.0.0.1:17910/v1`) et serveur MCP intégré (`simpleaudio-mcp`).
- Fenêtres natives À propos, Aide (⌘?) et Raccourcis clavier (⌘/).
