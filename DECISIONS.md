# Décisions d'Architecture — SimpleAudio

## 1. Zéro dépendance externe & Légèreté maximale (~3 Mo)
- **Contexte** : Les éditeurs audio courants (ocenaudio ~250 Mo, Audacity ~100 Mo) embarquent des frameworks multiplateformes lourds (Qt, wxWidgets, bibliothèques C++ dupliquées).
- **Décision** : Utiliser exclusivement les frameworks système macOS (`AppKit`, `SwiftUI`, `AVFoundation`, `AudioToolbox`, `Accelerate/vDSP`, sockets BSD `Darwin`). Le binaire compilé en mode `release` pèse ~2 à 3 Mo et démarre instantanément.

## 2. Modèle d'édition hybride : Clips multipistes + Plage temporelle (`selectionRange`)
- **Contexte** : L'utilisateur souhaite à la fois la simplicité d'un éditeur d'onde rapide (fondus, copier-coller, rogner, silencer une portion d'audio) et la souplesse d'un multipiste non-destructif comme `Montage`.
- **Décision** : `AudioProject` repose sur des `AudioTrack` contenant des `AudioClip` non-destructifs, complétés par `selectionRange: ClosedRange<Double>?`. Toutes les commandes d'édition (`⌘C`, `⌘X`, `⌘V`, `⌫`, `⇧⌫`, `⌘T`, fondus, silence) opèrent de façon transparente soit sur la plage temporelle active (en découpant automatiquement les clips aux bornes), soit sur les clips sélectionnés.

## 3. Moteur de lecture temps réel `AVAudioSourceNode` sans latence de seek
- **Contexte** : Reconstruire un graphe `AVAudioPlayerNode` à chaque coupe ou déplacement de poignée de fondu provoque des coupures audibles.
- **Décision** : `PlaybackEngine` construit un `RenderPlan` immuable à chaque modification du `DocumentStore` et le transmet au thread temps réel de `AVAudioSourceNode`, qui mixe directement les échantillons `Float32` depuis `PCMStore` avec application exacte des courbes de fondu (`cosine`, `linear`, `exponential`, `logarithmic`), du gain et du panoramique.

## 4. Ports réseau dédiés (HTTP `:17910`, OSC `:9110`)
- **Contexte** : Éviter toute collision avec `Montage` (`:17900`) et `OSCScore` (`:17890`, `:9100`) lorsque les trois applications tournent simultanément.
- **Décision** : L'API HTTP `/v1` écoute par défaut sur `127.0.0.1:17910` (`SIMPLEAUDIO_API_PORT`) et le serveur OSC UDP sur `:9110` (`SIMPLEAUDIO_OSC_IN_PORT`).
