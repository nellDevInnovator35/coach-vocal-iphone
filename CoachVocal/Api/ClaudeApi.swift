import Foundation

// Portage de ClaudeApi.kt : appels à l'API Messages d'Anthropic via URLSession.

struct ClaudeApi {

    static let systemPrompt = """
    Tu es un assistant personnel intégré dans une application de coaching vocal.
    L'utilisateur t'envoie des transcriptions de ses enregistrements vocaux.
    Aide-le à organiser ses idées, résumer ses notes, proposer des actions concrètes.
    Sois concis et utile. Réponds en français.
    """

    private let apiKey = Secrets.claudeApiKey
    private let model = "claude-sonnet-4-20250514"

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    enum ClaudeError: LocalizedError {
        case missingKey
        case http(Int, String)
        case empty
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Clé API Claude manquante. Renseigne-la dans Secrets.swift."
            case .http(let code, let body): return "Erreur API Claude \(code): \(body)"
            case .empty: return "Réponse vide"
            }
        }
    }

    /// Envoie l'historique de conversation à Claude et renvoie le texte de réponse.
    func sendMessage(messages: [ApiMessage], systemPrompt: String? = nil) async throws -> String {
        guard !apiKey.isEmpty, apiKey != "sk-ant-..." else { throw ClaudeError.missingKey }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": messages.map { $0.jsonValue }
        ]
        if let systemPrompt { body["system"] = systemPrompt }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ClaudeError.http(code, String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(ApiResponse.self, from: data)
        return decoded.content.first(where: { $0.type == "text" })?.text ?? "Pas de réponse"
    }

    /// Envoie un message avec une image (vision). L'image est ajoutée au dernier message user.
    func sendMessageWithImage(messages: [ApiMessage], imageURL: URL, systemPrompt: String? = nil) async throws -> String {
        let imageData = try Data(contentsOf: imageURL)
        let base64 = imageData.base64EncodedString()
        let mediaType: String
        switch imageURL.pathExtension.lowercased() {
        case "png": mediaType = "image/png"
        case "gif": mediaType = "image/gif"
        case "webp": mediaType = "image/webp"
        default: mediaType = "image/jpeg"
        }

        var msgs = messages
        if let last = msgs.last, last.role == "user" {
            msgs[msgs.count - 1] = ApiMessage(
                role: "user",
                blocks: [
                    .image(mediaType: mediaType, base64: base64),
                    .text(last.textContent)
                ]
            )
        }
        return try await sendMessage(messages: msgs, systemPrompt: systemPrompt)
    }
}

// MARK: - Modèles de requête

/// Un message peut contenir soit du texte simple, soit des blocs (texte + image).
struct ApiMessage {
    let role: String
    private let text: String?
    private let blocks: [ContentBlock]?

    init(role: String, content: String) {
        self.role = role
        self.text = content
        self.blocks = nil
    }

    init(role: String, blocks: [ContentBlock]) {
        self.role = role
        self.text = nil
        self.blocks = blocks
    }

    var textContent: String {
        if let text { return text }
        if let blocks {
            for case let .text(t) in blocks { return t }
        }
        return ""
    }

    /// Représentation JSON attendue par l'API.
    var jsonValue: [String: Any] {
        if let text {
            return ["role": role, "content": text]
        }
        return ["role": role, "content": (blocks ?? []).map { $0.jsonValue }]
    }
}

enum ContentBlock {
    case text(String)
    case image(mediaType: String, base64: String)

    var jsonValue: [String: Any] {
        switch self {
        case .text(let t):
            return ["type": "text", "text": t]
        case .image(let mediaType, let base64):
            return [
                "type": "image",
                "source": ["type": "base64", "media_type": mediaType, "data": base64]
            ]
        }
    }
}

// MARK: - Modèles de réponse

private struct ApiResponse: Decodable {
    let content: [ResponseContent]
}

private struct ResponseContent: Decodable {
    let type: String
    let text: String?
}
