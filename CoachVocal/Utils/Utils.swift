import Foundation
import UniformTypeIdentifiers

// Helpers transverses.

/// Formate des secondes en "mm:ss" (formatTime de RecordingScreen.kt).
func formatTime(_ seconds: Int) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

/// Format de date FR utilisé un peu partout.
func frDateTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "dd/MM/yyyy HH:mm"
    f.locale = Locale(identifier: "fr_FR")
    return f.string(from: date)
}

/// Taille de fichier lisible.
func humanFileSize(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) o" }
    if bytes < 1024 * 1024 { return "\(bytes / 1024) Ko" }
    return "\(bytes / (1024 * 1024)) Mo"
}

/// Catégorise un type de fichier à partir de son UTType / extension.
func fileCategory(for url: URL) -> String {
    if let type = UTType(filenameExtension: url.pathExtension) {
        if type.conforms(to: .audio) { return "audio" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "video" }
        if type.conforms(to: .image) { return "image" }
    }
    return "document"
}
