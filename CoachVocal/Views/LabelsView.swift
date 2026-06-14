import SwiftUI
import SwiftData

// Portage de LabelsScreen.kt.
struct LabelsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Label.name) private var labels: [Label]

    @State private var showDialog = false
    @State private var editing: Label?
    @State private var name = ""
    @State private var color = presetLabelColors.first!

    private var repo: CoachRepository { CoachRepository(context) }

    var body: some View {
        List {
            ForEach(labels) { label in
                HStack(spacing: 12) {
                    Circle().fill(Color(hex: label.colorHex)).frame(width: 24, height: 24)
                    Text(label.name)
                    Spacer()
                    Button { startEdit(label) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) { repo.deleteLabel(label) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle("Labels")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { startCreate() } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showDialog) {
            LabelDialog(name: $name, color: $color, isEditing: editing != nil) {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                if let editing {
                    repo.updateLabel(editing, name: trimmed, colorHex: color)
                } else {
                    repo.createLabel(name: trimmed, colorHex: color)
                }
                showDialog = false
            }
            .presentationDetents([.medium])
        }
    }

    private func startCreate() {
        editing = nil
        name = ""
        color = presetLabelColors.first!
        showDialog = true
    }

    private func startEdit(_ label: Label) {
        editing = label
        name = label.name
        color = label.colorHex
        showDialog = true
    }
}

struct LabelDialog: View {
    @Binding var name: String
    @Binding var color: String
    let isEditing: Bool
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name)
                Section("Couleur") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(presetLabelColors, id: \.self) { hex in
                            ZStack {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: color == hex ? 32 : 24, height: color == hex ? 32 : 24)
                                if color == hex {
                                    Image(systemName: "checkmark").font(.caption).foregroundStyle(.white)
                                }
                            }
                            .frame(height: 36)
                            .onTapGesture { color = hex }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Modifier le label" : "Nouveau label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: onSave)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
