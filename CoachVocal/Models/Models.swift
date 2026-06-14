import Foundation
import SwiftData

// Portage des entités Room (Project.kt) en modèles SwiftData.
// Les IDs auto-incrémentés Room (Long) deviennent des UUID.
// Les références (projectId, subProjectId…) sont des UUID stockés, plutôt
// que des relations SwiftData, pour rester proche du schéma d'origine et
// garder un filtrage simple et prévisible.

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class SubProject {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), projectId: UUID, title: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Label {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String = "#6200EE") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

// Association projet ⇄ label (table de jonction project_labels).
@Model
final class ProjectLabel {
    var projectId: UUID
    var labelId: UUID

    init(projectId: UUID, labelId: UUID) {
        self.projectId = projectId
        self.labelId = labelId
    }
}

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var subProjectId: UUID?
    var audioPath: String
    var transcription: String?
    var durationMs: Int
    var createdAt: Date

    init(id: UUID = UUID(), projectId: UUID, subProjectId: UUID? = nil,
         audioPath: String, transcription: String? = nil, durationMs: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.projectId = projectId
        self.subProjectId = subProjectId
        self.audioPath = audioPath
        self.transcription = transcription
        self.durationMs = durationMs
        self.createdAt = createdAt
    }
}

@Model
final class MediaAttachment {
    @Attribute(.unique) var id: UUID
    var recordingId: UUID
    var filePath: String
    var type: String   // "image" | "video"
    var createdAt: Date

    init(id: UUID = UUID(), recordingId: UUID, filePath: String, type: String, createdAt: Date = .now) {
        self.id = id
        self.recordingId = recordingId
        self.filePath = filePath
        self.type = type
        self.createdAt = createdAt
    }
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var subProjectId: UUID?
    var role: String   // "user" | "assistant"
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), projectId: UUID, subProjectId: UUID? = nil,
         role: String, content: String, createdAt: Date = .now) {
        self.id = id
        self.projectId = projectId
        self.subProjectId = subProjectId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

@Model
final class ProjectAttachment {
    @Attribute(.unique) var id: UUID
    var projectId: UUID
    var subProjectId: UUID?
    var filePath: String
    var fileName: String
    var type: String   // "audio" | "video" | "image" | "document"
    var mimeType: String?
    var fileSize: Int
    var createdAt: Date

    init(id: UUID = UUID(), projectId: UUID, subProjectId: UUID? = nil,
         filePath: String, fileName: String, type: String,
         mimeType: String? = nil, fileSize: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.projectId = projectId
        self.subProjectId = subProjectId
        self.filePath = filePath
        self.fileName = fileName
        self.type = type
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.createdAt = createdAt
    }
}

// Schéma complet, utilisé par le ModelContainer.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Project.self, SubProject.self, Label.self, ProjectLabel.self,
        Recording.self, MediaAttachment.self, Message.self, ProjectAttachment.self
    ]
}
