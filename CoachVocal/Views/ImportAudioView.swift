import SwiftUI
import SwiftData

enum ImportState {
    case idle, copying, transcribing, sendingToClaude, done, error
}

// Portage de ImportAudioScreen.kt + ImportAudioViewModel.kt.
struct ImportAudioView: View {
    @Binding var path: [Route]
    let audioURL: URL

    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @Query private var allSubProjects: [SubProject]

    @State private var importStarted = false
    @State private var state: ImportState = .idle
    @State private var statusText = ""
    @State private var transcription = ""
    @State private var errorMessage = ""
    @State private var resultProjectId: UUID?

    @State private var newProjectTitle = ""
    @State private var selectedProjectId: UUID?
    @State private var subProjectChoice = "root"
    @State private var selectedSubProjectId: UUID?
    @State private var newSubProjectTitle = ""

    private var repo: CoachRepository { CoachRepository(context) }
    private var subProjects: [SubProject] {
        guard let pid = selectedProjectId else { return [] }
        return allSubProjects.filter { $0.projectId == pid }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if !importStarted { setupPhase } else { progressPhase }
        }
        .navigationTitle("Importer un audio")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Phase 1 : choix du projet

    private var setupPhase: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "waveform").font(.title)
                    VStack(alignment: .leading) {
                        Text("Fichier audio reçu").bold()
                        Text(audioURL.lastPathComponent).font(.caption).lineLimit(1)
                    }
                }
            }

            Section("Projet") {
                TextField("Nouveau projet", text: $newProjectTitle)
                    .onChange(of: newProjectTitle) { _, _ in selectedProjectId = nil }
            }

            if !projects.isEmpty {
                Section("Ou ajouter à un projet existant") {
                    ForEach(projects) { p in
                        HStack {
                            Image(systemName: selectedProjectId == p.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(AppColors.purple)
                            Text(p.title).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedProjectId = p.id
                            newProjectTitle = ""
                            subProjectChoice = "root"
                            selectedSubProjectId = nil
                        }
                    }
                }

                if selectedProjectId != nil {
                    Section("Emplacement") {
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
            }

            Section {
                Button {
                    importStarted = true
                    Task { await runImport() }
                } label: {
                    HStack {
                        Spacer()
                        SwiftUI.Label("Transcrire et analyser", systemImage: "text.bubble")
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Phase 2 : progression

    private var progressPhase: some View {
        VStack(spacing: 16) {
            Spacer()
            switch state {
            case .error:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 64)).foregroundStyle(.red)
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(AppColors.purple)
            default:
                ProgressView().scaleEffect(2).frame(height: 64)
            }

            Text(statusText).font(.headline)

            ProgressView(value: Double(step) / 4.0).padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 8) {
                StepRow(label: "Copie du fichier", active: step >= 1, completed: step > 1)
                StepRow(label: "Transcription Whisper", active: step >= 2, completed: step > 2)
                StepRow(label: "Envoi à Claude", active: step >= 3, completed: step > 3)
                StepRow(label: "Terminé", active: step >= 4, completed: step >= 4)
            }
            .padding(.horizontal, 32)

            if !transcription.isEmpty {
                ScrollView {
                    VStack(alignment: .leading) {
                        Text("Transcription").font(.caption).foregroundStyle(.secondary)
                        Text(transcription).font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .frame(maxHeight: 160)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }

            if state == .error {
                Button("Réessayer") {
                    importStarted = false
                    state = .idle
                    transcription = ""
                }
                .padding(.top)
            }
            Spacer()
        }
        .padding()
    }

    private var step: Int {
        switch state {
        case .copying: return 1
        case .transcribing: return 2
        case .sendingToClaude: return 3
        case .done: return 4
        default: return 0
        }
    }

    // MARK: - Logique d'import

    @MainActor
    private func runImport() async {
        do {
            state = .copying
            statusText = "Préparation du fichier audio..."
            let fileSizeMb = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int)
                .flatMap { $0 }.map { Double($0) / (1024 * 1024) } ?? 0
            statusText = String(format: "Fichier prêt (%.1f Mo)", fileSizeMb)

            // Transcription Whisper
            state = .transcribing
            statusText = "Transcription en cours via Whisper..."
            let text = try await WhisperApi().transcribe(fileURL: audioURL)
            transcription = text
            statusText = "Transcription terminée (\(text.count) caractères)"

            // Projet
            let projId: UUID
            if let selected = selectedProjectId {
                projId = selected
            } else {
                let title = newProjectTitle.isEmpty
                    ? "Import audio - \(audioURL.deletingPathExtension().lastPathComponent)"
                    : newProjectTitle
                projId = repo.createProject(title: title).id
            }
            resultProjectId = projId

            // Sous-projet
            var finalSubProjectId: UUID? = nil
            if selectedProjectId != nil {
                if subProjectChoice == "new" {
                    finalSubProjectId = repo.createSubProject(projectId: projId,
                        title: newSubProjectTitle.isEmpty ? nil : newSubProjectTitle).id
                } else if subProjectChoice == "existing" {
                    finalSubProjectId = selectedSubProjectId
                }
            }

            // Enregistrement
            repo.createRecording(projectId: projId, audioPath: audioURL.path,
                                 transcription: text, durationMs: 0, subProjectId: finalSubProjectId)

            // Envoi à Claude
            state = .sendingToClaude
            statusText = "Envoi à Claude..."
            let userMsg = "Voici la transcription d'un message vocal :\n\n\(text)"
            repo.addMessage(projectId: projId, role: "user", content: userMsg, subProjectId: finalSubProjectId)
            do {
                let response = try await ClaudeApi().sendMessage(
                    messages: [ApiMessage(role: "user", content: userMsg)],
                    systemPrompt: ClaudeApi.systemPrompt
                )
                repo.addMessage(projectId: projId, role: "assistant", content: response, subProjectId: finalSubProjectId)
            } catch {
                repo.addMessage(projectId: projId, role: "assistant",
                                content: "Erreur Claude : \(error.localizedDescription)", subProjectId: finalSubProjectId)
            }

            state = .done
            statusText = "Import terminé !"
            try? await Task.sleep(nanoseconds: 600_000_000)
            path = [.project(projId)]
        } catch {
            state = .error
            errorMessage = error.localizedDescription
            statusText = "Erreur : \(error.localizedDescription)"
        }
    }
}

struct StepRow: View {
    let label: String
    let active: Bool
    let completed: Bool

    var body: some View {
        HStack {
            Image(systemName: completed ? "checkmark.circle.fill" : (active ? "smallcircle.filled.circle" : "circle"))
                .foregroundStyle(completed ? AppColors.purple : (active ? AppColors.teal : Color.secondary.opacity(0.4)))
            Text(label)
                .foregroundStyle(active || completed ? Color.primary : Color.secondary.opacity(0.5))
        }
    }
}
