import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Portage de ProjectScreen.kt + ProjectViewModel.kt.
struct ProjectView: View {
    @Binding var path: [Route]
    let projectId: UUID

    @Environment(\.modelContext) private var context

    @Query private var allProjects: [Project]
    @Query private var allSubProjects: [SubProject]
    @Query private var allMessages: [Message]
    @Query private var allRecordings: [Recording]
    @Query private var allAttachments: [ProjectAttachment]

    @State private var selectedSubProjectId: UUID?
    @State private var inputText = ""
    @State private var isLoading = false

    // Dialogs / sheets
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDelete = false
    @State private var showClear = false
    @State private var showAttachments = false
    @State private var showNewSubProject = false
    @State private var newSubProjectText = ""
    @State private var renameSubTarget: SubProject?
    @State private var renameSubText = ""
    @State private var deleteSubTarget: SubProject?
    @State private var showFileImporter = false
    @State private var exportItem: ExportItem?

    private var repo: CoachRepository { CoachRepository(context) }
    private var project: Project? { allProjects.first { $0.id == projectId } }
    private var subProjects: [SubProject] {
        allSubProjects.filter { $0.projectId == projectId }.sorted { $0.createdAt > $1.createdAt }
    }
    private var selectedSubProject: SubProject? { subProjects.first { $0.id == selectedSubProjectId } }
    private var messages: [Message] {
        allMessages.filter { $0.projectId == projectId && $0.subProjectId == selectedSubProjectId }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var recordings: [Recording] {
        allRecordings.filter { $0.projectId == projectId && $0.subProjectId == selectedSubProjectId }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var attachments: [ProjectAttachment] {
        allAttachments.filter { $0.projectId == projectId && $0.subProjectId == selectedSubProjectId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private let importTypes: [UTType] = [.audio, .movie, .image, .pdf, .plainText, .item]

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            inputBar
        }
        .navigationTitle(project?.title ?? "Projet")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { for u in urls { addAttachment(u) } }
        }
        .sheet(isPresented: $showAttachments) {
            AttachmentsSheet(attachments: attachments,
                             onDelete: { repo.deleteProjectAttachment($0) },
                             onAdd: { showAttachments = false; showFileImporter = true })
        }
        .sheet(item: $exportItem) { ShareSheet(items: [$0.url]) }
        .alert("Renommer", isPresented: $showRename) {
            TextField("Nom", text: $renameText)
            Button("Annuler", role: .cancel) {}
            Button("Renommer") {
                let t = renameText.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                if let sp = selectedSubProject { repo.renameSubProject(sp, title: t) }
                else if let p = project { repo.updateProjectTitle(p, title: t) }
            }
        }
        .alert("Supprimer le projet ?", isPresented: $showDelete) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                if let p = project { repo.deleteProject(p); path.removeLast() }
            }
        } message: { Text("Ce projet et tout son contenu seront supprimés définitivement.") }
        .alert("Effacer la conversation ?", isPresented: $showClear) {
            Button("Annuler", role: .cancel) {}
            Button("Effacer", role: .destructive) {
                repo.clearMessages(projectId: projectId, subProjectId: selectedSubProjectId)
            }
        } message: { Text("Tous les messages seront supprimés. Les enregistrements sont conservés.") }
        .alert("Nouveau sous-projet", isPresented: $showNewSubProject) {
            TextField("Nom (vide = date du jour)", text: $newSubProjectText)
            Button("Annuler", role: .cancel) {}
            Button("Créer") {
                let t = newSubProjectText.trimmingCharacters(in: .whitespaces)
                let sp = repo.createSubProject(projectId: projectId, title: t.isEmpty ? nil : t)
                selectedSubProjectId = sp.id
                newSubProjectText = ""
            }
        }
        .alert("Renommer le sous-projet", isPresented: Binding(get: { renameSubTarget != nil }, set: { if !$0 { renameSubTarget = nil } })) {
            TextField("Nom", text: $renameSubText)
            Button("Annuler", role: .cancel) { renameSubTarget = nil }
            Button("Renommer") {
                if let sp = renameSubTarget {
                    let t = renameSubText.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { repo.renameSubProject(sp, title: t) }
                }
                renameSubTarget = nil
            }
        }
        .alert("Supprimer le sous-projet ?", isPresented: Binding(get: { deleteSubTarget != nil }, set: { if !$0 { deleteSubTarget = nil } })) {
            Button("Annuler", role: .cancel) { deleteSubTarget = nil }
            Button("Supprimer", role: .destructive) {
                if let sp = deleteSubTarget {
                    if selectedSubProjectId == sp.id { selectedSubProjectId = nil }
                    repo.deleteSubProject(sp)
                }
                deleteSubTarget = nil
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if selectedSubProjectId != nil { selectedSubProjectId = nil } else { path.removeLast() }
            } label: { Image(systemName: "chevron.backward") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { path.append(.recording) } label: { Image(systemName: "mic") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { exportProject() } label: { Image(systemName: "square.and.arrow.up") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { renameText = selectedSubProject?.title ?? project?.title ?? ""; showRename = true } label: {
                    SwiftUI.Label("Renommer", systemImage: "pencil")
                }
                Button { showAttachments = true } label: {
                    SwiftUI.Label("Pièces jointes (\(attachments.count))", systemImage: "folder")
                }
                Button { showClear = true } label: {
                    SwiftUI.Label("Effacer la conversation", systemImage: "trash.slash")
                }
                Divider()
                Button(role: .destructive) { showDelete = true } label: {
                    SwiftUI.Label("Supprimer le projet", systemImage: "trash")
                }
            } label: { Image(systemName: "ellipsis") }
        }
    }

    // MARK: - Liste des messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if selectedSubProjectId == nil {
                        SubProjectBar(subProjects: subProjects,
                                      onSelect: { selectedSubProjectId = $0.id },
                                      onCreateNew: { showNewSubProject = true },
                                      onRename: { renameSubTarget = $0; renameSubText = $0.title },
                                      onDelete: { deleteSubTarget = $0 })
                    }
                    if let sp = selectedSubProject {
                        Text(sp.title).font(.subheadline).foregroundStyle(AppColors.purple)
                    }
                    if !recordings.isEmpty {
                        recordingsSummary
                    }
                    if !attachments.isEmpty {
                        Button { showAttachments = true } label: {
                            HStack {
                                Image(systemName: "paperclip")
                                Text("\(attachments.count) fichier(s) joint(s)").font(.caption)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "#00ACC1").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(messages) { MessageBubble(message: $0).id($0.id) }
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var recordingsSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(recordings.count) enregistrement(s)").font(.caption).bold()
            ForEach(recordings) { rec in
                Text("- \(formatTime(rec.durationMs / 1000)) : \((rec.transcription ?? "pas de transcription").prefix(80))...")
                    .font(.caption2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.teal.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Barre de saisie

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button { showFileImporter = true } label: { Image(systemName: "paperclip") }
            TextField("Message...", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            Button(action: send) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
        }
        .padding(8)
        .background(.bar)
    }

    // MARK: - Actions

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isLoading else { return }
        inputText = ""
        isLoading = true
        let spid = selectedSubProjectId
        Task { @MainActor in
            repo.addMessage(projectId: projectId, role: "user", content: text, subProjectId: spid)
            do {
                let history = repo.messages(projectId: projectId)
                    .filter { $0.subProjectId == spid }
                    .map { ApiMessage(role: $0.role, content: $0.content) }
                let response = try await ClaudeApi().sendMessage(messages: history, systemPrompt: ClaudeApi.systemPrompt)
                repo.addMessage(projectId: projectId, role: "assistant", content: response, subProjectId: spid)
            } catch {
                repo.addMessage(projectId: projectId, role: "assistant",
                                content: "Erreur : \(error.localizedDescription)", subProjectId: spid)
            }
            isLoading = false
        }
    }

    private func addAttachment(_ url: URL) {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let destDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("attachments/\(projectId.uuidString)")
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))_\(url.lastPathComponent)")
        do { try fm.copyItem(at: url, to: dest) } catch { return }
        let size = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int).flatMap { $0 } ?? 0
        repo.addProjectAttachment(projectId: projectId, filePath: dest.path, fileName: url.lastPathComponent,
                                  type: fileCategory(for: url), mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
                                  fileSize: size, subProjectId: selectedSubProjectId)
    }

    private func exportProject() {
        guard let project else { return }
        if let url = try? ExportService.exportProject(project, repo: repo) {
            exportItem = ExportItem(url: url)
        }
    }
}

// MARK: - Composants

struct SubProjectBar: View {
    let subProjects: [SubProject]
    let onSelect: (SubProject) -> Void
    let onCreateNew: () -> Void
    let onRename: (SubProject) -> Void
    let onDelete: (SubProject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sous-projets").font(.subheadline.weight(.medium))
                Spacer()
                Button { onCreateNew() } label: { SwiftUI.Label("Nouveau", systemImage: "plus").font(.caption) }
            }
            if subProjects.isEmpty {
                Text("Aucun sous-projet. Les éléments sont à la racine.")
                    .font(.caption).foregroundStyle(.secondary.opacity(0.7))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(subProjects) { sp in
                            Menu {
                                Button { onSelect(sp) } label: { SwiftUI.Label("Ouvrir", systemImage: "arrow.right") }
                                Button { onRename(sp) } label: { SwiftUI.Label("Renommer", systemImage: "pencil") }
                                Button(role: .destructive) { onDelete(sp) } label: { SwiftUI.Label("Supprimer", systemImage: "trash") }
                            } label: {
                                Text(sp.title)
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                            .simultaneousGesture(TapGesture().onEnded { onSelect(sp) })
                        }
                    }
                }
            }
            Divider()
        }
    }
}

struct MessageBubble: View {
    let message: Message
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .padding(12)
                .background(isUser ? AppColors.purple.opacity(0.18) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

struct AttachmentsSheet: View {
    let attachments: [ProjectAttachment]
    let onDelete: (ProjectAttachment) -> Void
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if attachments.isEmpty {
                    Text("Aucune pièce jointe").foregroundStyle(.secondary)
                } else {
                    ForEach(attachments) { att in
                        HStack(spacing: 12) {
                            Image(systemName: icon(att.type)).foregroundStyle(AppColors.purple)
                            VStack(alignment: .leading) {
                                Text(att.fileName).lineLimit(1)
                                Text("\(att.type) • \(humanFileSize(att.fileSize))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .swipeActions {
                            Button(role: .destructive) { onDelete(att) } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Pièces jointes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { onAdd() } label: { Image(systemName: "plus") } }
                ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
            }
        }
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "audio": return "waveform"
        case "video": return "video"
        case "image": return "photo"
        default: return "doc"
        }
    }
}

// Wrapper UIActivityViewController pour la share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// Enveloppe identifiable pour présenter la share sheet via .sheet(item:).
struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}
