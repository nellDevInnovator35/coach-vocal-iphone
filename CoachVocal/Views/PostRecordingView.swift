import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// Portage de PostRecordingScreen.kt + PostRecordingViewModel.kt.
struct PostRecordingView: View {
    @Binding var path: [Route]
    let audioPath: String
    let durationMs: Int
    let transcription: String

    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Label.name) private var labels: [Label]
    @Query private var allSubProjects: [SubProject]

    @State private var isNewProject = true
    @State private var projectTitle = ""
    @State private var selectedProjectId: UUID?
    @State private var selectedLabels: Set<UUID> = []

    @State private var subProjectChoice = "root"   // "root" | "existing" | "new"
    @State private var selectedSubProjectId: UUID?
    @State private var newSubProjectTitle = ""

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isSaving = false

    private var repo: CoachRepository { CoachRepository(context) }
    private var subProjects: [SubProject] {
        guard let pid = selectedProjectId else { return [] }
        return allSubProjects.filter { $0.projectId == pid }.sorted { $0.createdAt > $1.createdAt }
    }
    private var canSave: Bool { !isSaving && (isNewProject || selectedProjectId != nil) }

    var body: some View {
        Form {
            Section("Transcription") {
                Text(transcription).foregroundStyle(.secondary)
                Text("Durée : \(formatTime(durationMs / 1000))").font(.caption)
            }

            Section("Projet") {
                Picker("Destination", selection: $isNewProject) {
                    Text("Nouveau projet").tag(true)
                    Text("Projet existant").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(projects.isEmpty && !isNewProject)

                if isNewProject {
                    TextField("Nom du projet", text: $projectTitle)
                } else {
                    ForEach(projects) { p in
                        HStack {
                            Image(systemName: selectedProjectId == p.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(AppColors.purple)
                            Text(p.title)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedProjectId = p.id
                            subProjectChoice = "root"
                            selectedSubProjectId = nil
                        }
                    }
                }
            }

            if !isNewProject, selectedProjectId != nil {
                Section("Emplacement dans le projet") {
                    Picker("Emplacement", selection: $subProjectChoice) {
                        Text("Racine").tag("root")
                        Text("Sous-projet").tag("existing")
                        Text("Nouveau SP").tag("new")
                    }
                    .pickerStyle(.segmented)

                    if subProjectChoice == "existing" {
                        ForEach(subProjects) { sp in
                            HStack {
                                Image(systemName: selectedSubProjectId == sp.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(AppColors.purple)
                                Text(sp.title)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { selectedSubProjectId = sp.id }
                        }
                    } else if subProjectChoice == "new" {
                        TextField("Nom (vide = date du jour)", text: $newSubProjectTitle)
                    }
                }
            }

            if !labels.isEmpty {
                Section("Labels") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(labels) { label in
                                let on = selectedLabels.contains(label.id)
                                Text(label.name)
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(on ? Color(hex: label.colorHex).opacity(0.25) : Color(.tertiarySystemBackground))
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        if on { selectedLabels.remove(label.id) } else { selectedLabels.insert(label.id) }
                                    }
                            }
                        }
                    }
                }
            }

            Section {
                PhotosPicker(selection: $photoItems, matching: .any(of: [.images, .videos])) {
                    SwiftUI.Label("Ajouter photo/vidéo", systemImage: "photo")
                }
                if !photoItems.isEmpty {
                    Text("\(photoItems.count) fichier(s) attaché(s)").font(.caption)
                }
            }

            Section {
                Button(action: save) {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else { Text("Enregistrer").bold() }
                        Spacer()
                    }
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle("Nouvel enregistrement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { path.removeLast() } label: { Image(systemName: "xmark") }
            }
        }
    }

    private func save() {
        isSaving = true
        let validTranscription = transcription == "Aucune transcription disponible" ? nil : transcription

        Task { @MainActor in
            // Projet
            let projectId: UUID
            if isNewProject {
                projectId = repo.createProject(title: projectTitle.isEmpty ? "Sans titre" : projectTitle).id
            } else {
                projectId = selectedProjectId!
            }

            // Sous-projet
            var finalSubProjectId: UUID? = nil
            if !isNewProject {
                if subProjectChoice == "new" {
                    let title = newSubProjectTitle.isEmpty ? nil : newSubProjectTitle
                    finalSubProjectId = repo.createSubProject(projectId: projectId, title: title).id
                } else if subProjectChoice == "existing" {
                    finalSubProjectId = selectedSubProjectId
                }
            }

            // Labels
            for labelId in selectedLabels {
                repo.addLabelToProject(projectId: projectId, labelId: labelId)
            }

            // Enregistrement
            let recording = repo.createRecording(
                projectId: projectId, audioPath: audioPath,
                transcription: validTranscription, durationMs: durationMs,
                subProjectId: finalSubProjectId
            )

            // Médias attachés
            for item in photoItems {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let isVideo = (item.supportedContentTypes.first?.conforms(to: .movie)) ?? false
                    let ext = isVideo ? "mp4" : "jpg"
                    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("media_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)")
                    try? data.write(to: url)
                    repo.addMedia(recordingId: recording.id, filePath: url.path, type: isVideo ? "video" : "image")
                }
            }

            // Envoi à Claude
            if let t = validTranscription, !t.isEmpty {
                let userMsg = "Voici la transcription de mon enregistrement :\n\n\(t)"
                repo.addMessage(projectId: projectId, role: "user", content: userMsg, subProjectId: finalSubProjectId)
                do {
                    let response = try await ClaudeApi().sendMessage(
                        messages: [ApiMessage(role: "user", content: userMsg)],
                        systemPrompt: ClaudeApi.systemPrompt
                    )
                    repo.addMessage(projectId: projectId, role: "assistant", content: response, subProjectId: finalSubProjectId)
                } catch {
                    repo.addMessage(projectId: projectId, role: "assistant",
                                    content: "Erreur de connexion à Claude : \(error.localizedDescription)",
                                    subProjectId: finalSubProjectId)
                }
            }

            // Navigation vers le projet (popUpTo HOME).
            path = [.project(projectId)]
        }
    }
}
