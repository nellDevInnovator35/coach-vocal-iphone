import Foundation

// Portage de WhisperApi.kt : transcription d'un fichier audio via l'API Whisper d'OpenAI.

struct WhisperApi {

    private let apiKey = Secrets.openAIApiKey
    private static let apiURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    enum WhisperError: LocalizedError {
        case missingKey
        case http(Int, String)
        case parsing(String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Clé API OpenAI manquante. Renseigne-la dans Secrets.swift."
            case .http(let code, let body): return "Whisper API erreur \(code): \(body)"
            case .parsing(let body): return "Erreur parsing réponse Whisper: \(body)"
            }
        }
    }

    /// Transcrit un fichier audio en texte.
    /// - Parameters:
    ///   - fileURL: fichier audio (mp3, m4a, wav, ogg, webm, …)
    ///   - language: code ISO-639-1 (ex: "fr")
    func transcribe(fileURL: URL, language: String = "fr") async throws -> String {
        guard !apiKey.isEmpty, apiKey != "sk-..." else { throw WhisperError.missingKey }

        let mimeType = Self.mimeType(for: fileURL.pathExtension.lowercased())
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n")

        for (name, value) in [("model", "whisper-1"), ("language", language), ("response_format", "json")] {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let bodyString = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(code) else { throw WhisperError.http(code, bodyString) }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["text"] as? String
        else { throw WhisperError.parsing(bodyString) }

        return text
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "mp3": return "audio/mpeg"
        case "mp4", "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "ogg", "opus", "oga": return "audio/ogg"
        case "webm": return "audio/webm"
        case "flac": return "audio/flac"
        case "aac": return "audio/aac"
        case "amr": return "audio/amr"
        case "3gp": return "audio/3gpp"
        default: return "audio/ogg"
        }
    }
}
