import Foundation
import SwiftData

// Portage de CoachRepository.kt : centralise les accès aux données.
// Opère sur un ModelContext (toujours utilisé depuis l'UI / le main actor).
struct CoachRepository {
    let context: ModelContext

    init(_ context: ModelContext) {
        self.context = context
    }

    private func save() {
        try? context.save()
    }

    // MARK: - Helpers de fetch

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Projects

    func allProjects() -> [Project] {
        fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    func project(id: UUID) -> Project? {
        fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })).first
    }

    @discardableResult
    func createProject(title: String) -> Project {
        let p = Project(title: title)
        context.insert(p)
        save()
        return p
    }

    func updateProjectTitle(_ project: Project, title: String) {
        project.title = title
        project.updatedAt = .now
        save()
    }

    func deleteProject(_ project: Project) {
        // Suppression en cascade manuelle (pas de ForeignKey CASCADE en SwiftData ici).
        let pid = project.id
        for sp in subProjects(projectId: pid) { context.delete(sp) }
        for r in recordings(projectId: pid) {
            for m in media(recordingId: r.id) { context.delete(m) }
            context.delete(r)
        }
        for msg in fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.projectId == pid })) { context.delete(msg) }
        for att in fetch(FetchDescriptor<ProjectAttachment>(predicate: #Predicate { $0.projectId == pid })) { context.delete(att) }
        for pl in fetch(FetchDescriptor<ProjectLabel>(predicate: #Predicate { $0.projectId == pid })) { context.delete(pl) }
        context.delete(project)
        save()
    }

    func touchProject(_ projectId: UUID) {
        project(id: projectId)?.updatedAt = .now
        save()
    }

    // MARK: - Sub-projects

    func subProjects(projectId: UUID) -> [SubProject] {
        fetch(FetchDescriptor<SubProject>(
            predicate: #Predicate { $0.projectId == projectId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    func subProject(id: UUID) -> SubProject? {
        fetch(FetchDescriptor<SubProject>(predicate: #Predicate { $0.id == id })).first
    }

    @discardableResult
    func createSubProject(projectId: UUID, title: String? = nil) -> SubProject {
        let sp = SubProject(projectId: projectId, title: title ?? Self.todayTitle())
        context.insert(sp)
        touchProject(projectId)
        save()
        return sp
    }

    func renameSubProject(_ sp: SubProject, title: String) {
        sp.title = title
        sp.updatedAt = .now
        save()
    }

    func deleteSubProject(_ sp: SubProject) {
        let spid: UUID? = sp.id
        // Détache les éléments rattachés (équivalent SET_NULL).
        for r in fetch(FetchDescriptor<Recording>(predicate: #Predicate { $0.subProjectId == spid })) { r.subProjectId = nil }
        for m in fetch(FetchDescriptor<Message>(predicate: #Predicate { $0.subProjectId == spid })) { context.delete(m) }
        for a in fetch(FetchDescriptor<ProjectAttachment>(predicate: #Predicate { $0.subProjectId == spid })) { a.subProjectId = nil }
        let pid = sp.projectId
        context.delete(sp)
        touchProject(pid)
        save()
    }

    func touchSubProject(_ id: UUID) {
        subProject(id: id)?.updatedAt = .now
        save()
    }

    // MARK: - Labels

    func allLabels() -> [Label] {
        fetch(FetchDescriptor<Label>(sortBy: [SortDescriptor(\.name)]))
    }

    func labels(projectId: UUID) -> [Label] {
        let links = fetch(FetchDescriptor<ProjectLabel>(predicate: #Predicate { $0.projectId == projectId }))
        let ids = Set(links.map { $0.labelId })
        return allLabels().filter { ids.contains($0.id) }
    }

    @discardableResult
    func createLabel(name: String, colorHex: String = "#6200EE") -> Label {
        let l = Label(name: name, colorHex: colorHex)
        context.insert(l)
        save()
        return l
    }

    func updateLabel(_ label: Label, name: String, colorHex: String) {
        label.name = name
        label.colorHex = colorHex
        save()
    }

    func deleteLabel(_ label: Label) {
        let lid = label.id
        for pl in fetch(FetchDescriptor<ProjectLabel>(predicate: #Predicate { $0.labelId == lid })) { context.delete(pl) }
        context.delete(label)
        save()
    }

    func addLabelToProject(projectId: UUID, labelId: UUID) {
        let exists = fetch(FetchDescriptor<ProjectLabel>(
            predicate: #Predicate { $0.projectId == projectId && $0.labelId == labelId }
        )).isEmpty == false
        if !exists {
            context.insert(ProjectLabel(projectId: projectId, labelId: labelId))
            save()
        }
    }

    func removeLabelFromProject(projectId: UUID, labelId: UUID) {
        for pl in fetch(FetchDescriptor<ProjectLabel>(
            predicate: #Predicate { $0.projectId == projectId && $0.labelId == labelId }
        )) { context.delete(pl) }
        save()
    }

    // MARK: - Recordings

    func recordings(projectId: UUID) -> [Recording] {
        fetch(FetchDescriptor<Recording>(
            predicate: #Predicate { $0.projectId == projectId },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    @discardableResult
    func createRecording(projectId: UUID, audioPath: String, transcription: String?,
                         durationMs: Int, subProjectId: UUID? = nil) -> Recording {
        let r = Recording(projectId: projectId, subProjectId: subProjectId,
                          audioPath: audioPath, transcription: transcription, durationMs: durationMs)
        context.insert(r)
        touchProject(projectId)
        if let spid = subProjectId { touchSubProject(spid) }
        save()
        return r
    }

    func deleteRecording(_ recording: Recording) {
        context.delete(recording)
        save()
    }

    // MARK: - Media

    func media(recordingId: UUID) -> [MediaAttachment] {
        fetch(FetchDescriptor<MediaAttachment>(predicate: #Predicate { $0.recordingId == recordingId }))
    }

    @discardableResult
    func addMedia(recordingId: UUID, filePath: String, type: String) -> MediaAttachment {
        let m = MediaAttachment(recordingId: recordingId, filePath: filePath, type: type)
        context.insert(m)
        save()
        return m
    }

    // MARK: - Project attachments

    func attachments(projectId: UUID) -> [ProjectAttachment] {
        fetch(FetchDescriptor<ProjectAttachment>(
            predicate: #Predicate { $0.projectId == projectId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    @discardableResult
    func addProjectAttachment(projectId: UUID, filePath: String, fileName: String, type: String,
                              mimeType: String?, fileSize: Int, subProjectId: UUID? = nil) -> ProjectAttachment {
        let a = ProjectAttachment(projectId: projectId, subProjectId: subProjectId,
                                  filePath: filePath, fileName: fileName, type: type,
                                  mimeType: mimeType, fileSize: fileSize)
        context.insert(a)
        touchProject(projectId)
        if let spid = subProjectId { touchSubProject(spid) }
        save()
        return a
    }

    func deleteProjectAttachment(_ attachment: ProjectAttachment) {
        try? FileManager.default.removeItem(atPath: attachment.filePath)
        context.delete(attachment)
        save()
    }

    // MARK: - Messages

    func messages(projectId: UUID) -> [Message] {
        fetch(FetchDescriptor<Message>(
            predicate: #Predicate { $0.projectId == projectId },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    @discardableResult
    func addMessage(projectId: UUID, role: String, content: String, subProjectId: UUID? = nil) -> Message {
        let m = Message(projectId: projectId, subProjectId: subProjectId, role: role, content: content)
        context.insert(m)
        touchProject(projectId)
        if let spid = subProjectId { touchSubProject(spid) }
        save()
        return m
    }

    func clearMessages(projectId: UUID, subProjectId: UUID?) {
        let all = messages(projectId: projectId)
        for m in all where m.subProjectId == subProjectId {
            context.delete(m)
        }
        save()
    }

    // MARK: - Helpers

    static func todayTitle() -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: Date())
    }
}
