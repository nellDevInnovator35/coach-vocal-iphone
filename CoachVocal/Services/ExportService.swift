import Foundation

// Portage de ProjectViewModel.exportProject() : construit un .zip du projet
// (résumé Markdown + audios + médias + pièces jointes) puis le renvoie pour
// partage via la share sheet iOS.
enum ExportService {

    static func exportProject(_ project: Project, repo: CoachRepository) throws -> URL {
        let fm = FileManager.default
        let subs = repo.subProjects(projectId: project.id)
        let recordings = repo.recordings(projectId: project.id)
        let attachments = repo.attachments(projectId: project.id)
        let messages = repo.messages(projectId: project.id)

        func subName(_ id: UUID?) -> String? { subs.first { $0.id == id }?.title }

        // Dossier source à zipper.
        let safeTitle = project.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined()
            .prefix(50)
        let root = fm.temporaryDirectory.appendingPathComponent("export_\(UUID().uuidString)/\(safeTitle.isEmpty ? "projet" : safeTitle)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        // resume.md
        var md = ""
        md += "# \(project.title)\n"
        md += "Créé le : \(frDateTime(project.createdAt))\n"
        md += "Modifié le : \(frDateTime(project.updatedAt))\n"
        let labels = repo.labels(projectId: project.id)
        if !labels.isEmpty { md += "Labels : \(labels.map { $0.name }.joined(separator: ", "))\n" }
        if !subs.isEmpty { md += "Sous-projets : \(subs.map { $0.title }.joined(separator: ", "))\n" }
        md += "\n## Enregistrements\n\n"
        for (i, rec) in recordings.enumerated() {
            let loc = subName(rec.subProjectId).map { " [\($0)]" } ?? " [racine]"
            md += "### Enregistrement \(i + 1)\(loc)\n"
            md += "Date : \(frDateTime(rec.createdAt))\n"
            md += (rec.transcription ?? "(pas de transcription)") + "\n\n"
        }
        if !attachments.isEmpty {
            md += "## Pièces jointes\n\n"
            for att in attachments {
                let loc = subName(att.subProjectId).map { " [\($0)]" } ?? ""
                md += "- \(att.fileName) (\(att.type))\(loc)\n"
            }
            md += "\n"
        }
        if !messages.isEmpty {
            md += "## Conversation avec Claude\n\n"
            for msg in messages {
                let role = msg.role == "user" ? "Moi" : "Claude"
                let loc = subName(msg.subProjectId).map { " [\($0)]" } ?? ""
                md += "**\(role)**\(loc) (\(frDateTime(msg.createdAt)))\n\(msg.content)\n\n"
            }
        }
        try md.write(to: root.appendingPathComponent("resume.md"), atomically: true, encoding: .utf8)

        // Fichiers
        try copyFiles(attachments.map { ($0.filePath, $0.fileName) }, into: root, sub: "attachments", fm: fm)
        try copyFiles(recordings.compactMap { rec in
            fm.fileExists(atPath: rec.audioPath) ? (rec.audioPath, URL(fileURLWithPath: rec.audioPath).lastPathComponent) : nil
        }, into: root, sub: "audio", fm: fm)
        var medias: [(String, String)] = []
        for rec in recordings {
            for m in repo.media(recordingId: rec.id) where fm.fileExists(atPath: m.filePath) {
                medias.append((m.filePath, URL(fileURLWithPath: m.filePath).lastPathComponent))
            }
        }
        try copyFiles(medias, into: root, sub: "media", fm: fm)

        // Zip via NSFileCoordinator (.forUploading produit une archive .zip).
        return try zipDirectory(root, name: "\(safeTitle.isEmpty ? "projet" : String(safeTitle)).zip")
    }

    private static func copyFiles(_ files: [(String, String)], into root: URL, sub: String, fm: FileManager) throws {
        guard !files.isEmpty else { return }
        let dir = root.appendingPathComponent(sub)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (path, name) in files {
            guard fm.fileExists(atPath: path) else { continue }
            try? fm.copyItem(at: URL(fileURLWithPath: path), to: dir.appendingPathComponent(name))
        }
    }

    private static func zipDirectory(_ directory: URL, name: String) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var resultURL: URL?
        var thrown: Error?

        coordinator.coordinate(readingItemAt: directory, options: [.forUploading], error: &coordError) { zippedURL in
            // zippedURL pointe vers une archive .zip temporaire fournie par le système.
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: zippedURL, to: dest)
                resultURL = dest
            } catch {
                thrown = error
            }
        }
        if let coordError { throw coordError }
        if let thrown { throw thrown }
        guard let resultURL else { throw NSError(domain: "Export", code: -1) }
        return resultURL
    }
}
