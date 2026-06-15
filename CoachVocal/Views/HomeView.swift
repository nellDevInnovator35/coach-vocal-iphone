import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Portage de HomeScreen.kt.
struct HomeView: View {
    @Binding var path: [Route]
    @Environment(\.modelContext) private var context

    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @Query private var allLabels: [Label]
    @Query private var allLinks: [ProjectLabel]

    @State private var renameTarget: Project?
    @State private var renameText = ""
    @State private var deleteTarget: Project?
    @State private var showAudioImporter = false

    private var repo: CoachRepository { CoachRepository(context) }

    private func labels(for project: Project) -> [Label] {
        let ids = Set(allLinks.filter { $0.projectId == project.id }.map { $0.labelId })
        return allLabels.filter { ids.contains($0.id) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(projects) { project in
                            ProjectCard(project: project, labels: labels(for: project))
                                .contentShape(Rectangle())
                                .onTapGesture { path.append(.project(project.id)) }
                                .contextMenu {
                                    Button {
                                        renameText = project.title
                                        renameTarget = project
                                    } label: { SwiftUI.Label("Renommer", systemImage: "pencil") }
                                    Button(role: .destructive) {
                                        deleteTarget = project
                                    } label: { SwiftUI.Label("Supprimer", systemImage: "trash") }
                                }
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                }
            }

            // FAB micro (LargeFloatingActionButton).
            Button {
                path.append(.recording)
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(AppColors.recordingRed)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding(24)
        }
        .navigationTitle("Coach Vocal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAudioImporter = true } label: {
                    Image(systemName: "waveform")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { path.append(.labels) } label: {
                    Image(systemName: "tag")
                }
            }
        }
        // Importer un audio (équivalent OpenDocument audio/*).
        .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                if let local = copyToTemp(url) {
                    path.append(.importAudio(url: local))
                }
            }
        }
        // Renommer.
        .alert("Renommer le projet", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Nom du projet", text: $renameText)
            Button("Annuler", role: .cancel) { renameTarget = nil }
            Button("Renommer") {
                if let p = renameTarget, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    repo.updateProjectTitle(p, title: renameText.trimmingCharacters(in: .whitespaces))
                }
                renameTarget = nil
            }
        }
        // Supprimer.
        .alert("Supprimer le projet ?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Annuler", role: .cancel) { deleteTarget = nil }
            Button("Supprimer", role: .destructive) {
                if let p = deleteTarget { repo.deleteProject(p) }
                deleteTarget = nil
            }
        } message: {
            Text("Ce projet sera supprimé avec tous ses enregistrements et conversations. Action irréversible.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.secondary.opacity(0.5))
            Text("Appuie sur le micro pour commencer")
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Copie un fichier importé (URL sécurisée) vers un emplacement temporaire stable.
    private func copyToTemp(_ url: URL) -> URL? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("import_\(Int(Date().timeIntervalSince1970 * 1000))_\(url.lastPathComponent)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}

struct ProjectCard: View {
    let project: Project
    let labels: [Label]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title)
                .font(.headline)
                .lineLimit(1)
            Text(frDateTime(project.updatedAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(labels) { label in
                            Text(label.name)
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: label.colorHex).opacity(0.15))
                                .foregroundStyle(Color(hex: label.colorHex))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
