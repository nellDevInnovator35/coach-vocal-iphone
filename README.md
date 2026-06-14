# Coach Vocal — version iOS

Portage iOS (Swift + SwiftUI + SwiftData) de l'app Android `appli-coach-mobile`.
Mêmes fonctions : enregistrement vocal avec transcription en direct, import audio
transcrit par Whisper, conversation avec Claude, projets / sous-projets / labels,
pièces jointes et export `.zip`.

## Correspondance Android → iOS

| Android (Kotlin)            | iOS (Swift)                                   |
|-----------------------------|-----------------------------------------------|
| Jetpack Compose             | SwiftUI                                        |
| Room                        | SwiftData (`@Model`, `@Query`)                |
| ViewModel + StateFlow       | `@Observable` + `@State` / vues + repository  |
| SpeechRecognizer            | `SFSpeechRecognizer` + `AVAudioEngine`        |
| AudioRecord (WAV)           | `AVAudioEngine` → fichier `.m4a` réel         |
| OkHttp (Claude / Whisper)   | `URLSession` async/await                       |
| FileProvider + Intent SEND  | `UIActivityViewController` (share sheet)       |
| Export ZIP (ZipOutputStream)| `NSFileCoordinator(.forUploading)`            |

Amélioration au passage : sur Android l'écran d'enregistrement ne sauvegardait
pas le vrai audio (fichier `.txt` placeholder). Ici le micro est transcrit **et**
écrit dans un vrai `.m4a` en parallèle.

## Prérequis

- Un **Mac** avec **Xcode 15.3+** (gratuit sur le Mac App Store).
- **XcodeGen** pour générer le projet : `brew install xcodegen`
  (si tu n'as pas Homebrew : https://brew.sh).
- Une **clé API Anthropic** et une **clé API OpenAI**.

## Mise en route

```bash
cd coach-mobilr-ios

# 1. Renseigne tes clés API (fichier ignoré par git)
#    Secrets.swift existe déjà avec des placeholders — édite-le,
#    ou repars du modèle :
cp CoachVocal/Secrets.example.swift CoachVocal/Secrets.swift
#    puis ouvre CoachVocal/Secrets.swift et colle tes deux clés.

# 2. Génère le projet Xcode
xcodegen generate

# 3. Ouvre-le
open CoachVocal.xcodeproj
```

## Installer sur ton iPhone (sans App Store)

1. Dans Xcode, sélectionne le target **CoachVocal** → onglet **Signing & Capabilities**.
   Coche *Automatically manage signing* et choisis ton **Apple ID** comme *Team*
   (Xcode → Settings → Accounts pour l'ajouter si besoin — un Apple ID gratuit suffit).
2. Si Xcode signale un conflit de bundle id, change `PRODUCT_BUNDLE_IDENTIFIER`
   dans `project.yml` (ex. `com.tonnom.coachvocal`) puis relance `xcodegen generate`.
3. Branche l'iPhone en USB. Sur le téléphone : **Réglages → Confidentialité et
   sécurité → Mode développeur** → activer, puis redémarrer.
4. En haut de Xcode, choisis ton iPhone comme destination et clique **Run** (▶).
5. Au 1er lancement, iOS bloque l'app : **Réglages → Général → VPN et gestion de
   l'appareil** → approuve ton profil de développeur. Relance l'app.

Limites de la signature gratuite : l'app **expire au bout de 7 jours**
(re-lance depuis Xcode pour réactiver), max 3 apps installées de cette façon.
Avec un compte Apple Developer payant (99 $/an), la validité passe à 1 an.

## Architecture du code

```
CoachVocal/
  CoachVocalApp.swift      # @main, ModelContainer SwiftData, navigation (NavigationStack)
  Secrets.swift            # clés API (gitignoré)
  Models/Models.swift      # entités SwiftData (Project, SubProject, Label, Recording, …)
  Data/CoachRepository.swift   # CRUD + helpers (ex-CoachRepository.kt)
  Api/ClaudeApi.swift      # API Messages Anthropic (+ vision)
  Api/WhisperApi.swift     # transcription Whisper (OpenAI)
  Services/
    SpeechRecognizerService.swift  # transcription temps réel + capture audio
    ExportService.swift            # génération du .zip d'export
  Theme/Theme.swift        # couleurs, Color(hex:)
  Utils/Utils.swift        # formatTime, dates, tailles de fichiers
  Views/
    HomeView.swift         # liste des projets + FAB micro + import
    RecordingView.swift    # enregistrement / transcription live
    PostRecordingView.swift# choix projet/sous-projet/labels + envoi à Claude
    ProjectView.swift      # chat Claude, sous-projets, pièces jointes, export
    LabelsView.swift       # CRUD labels
    ImportAudioView.swift  # import + transcription Whisper + envoi Claude
```

## Différences / pistes d'amélioration

- **Réception d'un audio partagé** (WhatsApp → « Partager vers Coach Vocal ») :
  sur Android c'était un `intent-filter ACTION_SEND`. Sur iOS cela demande une
  **Share Extension** (cible séparée), non incluse dans cette v1. En attendant,
  l'import se fait depuis l'app via le bouton d'import (Fichiers / iCloud).
- **Bouton volume pour lancer l'enregistrement** : non reproductible simplement
  sur iOS (pas d'API publique équivalente). Remplacé par le bouton micro.
- Le **dark mode** et les couleurs dynamiques sont gérés nativement par iOS.
```
