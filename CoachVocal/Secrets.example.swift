import Foundation

// MODÈLE — copie ce fichier en `Secrets.swift` et renseigne tes clés.
//   cp CoachVocal/Secrets.example.swift CoachVocal/Secrets.swift
// Secrets.swift est ignoré par git (voir .gitignore).
//
// Équivalent iOS du local.properties Android (CLAUDE_API_KEY / OPENAI_API_KEY).

enum Secrets {
    /// Clé API Anthropic (https://console.anthropic.com)
    static let claudeApiKey = "sk-ant-..."

    /// Clé API OpenAI pour Whisper (https://platform.openai.com)
    static let openAIApiKey = "sk-..."
}
