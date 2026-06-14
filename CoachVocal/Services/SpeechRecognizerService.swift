import Foundation
import Observation
import Speech
import AVFoundation

// Portage de SpeechToTextService.kt + AudioRecorder.kt.
//
// Sur Android, SpeechRecognizer faisait la transcription temps réel et l'audio
// n'était pas réellement sauvegardé (fichier placeholder .txt).
// Ici on fait mieux : SFSpeechRecognizer transcrit en direct ET le même flux
// micro est écrit dans un vrai fichier .m4a via AVAudioFile.

@Observable
final class SpeechRecognizerService {

    enum Status: String {
        case idle = "Initialisation..."
        case ready = "Parlez..."
        case listening = "Écoute..."
        case processing = "Traitement..."
        case unavailable = "Reconnaissance vocale non disponible"
        case denied = "Permission micro/reconnaissance refusée"
    }

    // État observable par la vue.
    var fullTranscription = ""
    var partialText = ""
    var status: Status = .idle
    var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var audioFile: AVAudioFile?
    private(set) var audioFileURL: URL?
    private var startTime: Date?

    /// Texte affiché = transcription consolidée + segment partiel en cours.
    var displayText: String {
        var s = fullTranscription
        if !partialText.isEmpty {
            if !s.isEmpty { s += " " }
            s += partialText
        }
        return s
    }

    // MARK: - Autorisations

    static func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speechOK && micOK
    }

    // MARK: - Démarrage

    func start() {
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Fichier de sortie audio (vrai enregistrement, contrairement à Android).
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("recording_\(Int(Date().timeIntervalSince1970 * 1000)).m4a")
            audioFileURL = url

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            audioFile = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ])

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.request?.append(buffer)
                try? self.audioFile?.write(from: buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isRecording = true
            startTime = Date()
            startRecognition()
        } catch {
            status = .unavailable
        }
    }

    private func startRecognition() {
        guard isRecording, let recognizer else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        status = .ready

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // Les callbacks peuvent arriver hors du thread principal : on repasse
            // sur le main pour muter l'état observable et l'UI.
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        if !text.isEmpty {
                            self.fullTranscription = self.fullTranscription.isEmpty ? text : "\(self.fullTranscription) \(text)"
                        }
                        self.partialText = ""
                        // Relance la reconnaissance pour continuer la dictée longue.
                        if self.isRecording {
                            self.restartRecognition()
                        }
                    } else {
                        if !text.isEmpty { self.partialText = text }
                        self.status = .listening
                    }
                }
                if error != nil, self.isRecording {
                    self.restartRecognition()
                }
            }
        }
    }

    private func restartRecognition() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        // Petit délai pour laisser le moteur se réinitialiser.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isRecording else { return }
            self.startRecognition()
        }
    }

    // MARK: - Arrêt

    struct Result {
        let audioURL: URL?
        let durationMs: Int
        let transcription: String
    }

    @discardableResult
    func stop() -> Result {
        let duration = startTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        let finalText = displayText.isEmpty ? "Aucune transcription disponible" : displayText

        isRecording = false
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return Result(audioURL: audioFileURL, durationMs: duration, transcription: finalText)
    }

    func cancel() {
        isRecording = false
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioFile = nil
        if let url = audioFileURL { try? FileManager.default.removeItem(at: url) }
        audioFileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
