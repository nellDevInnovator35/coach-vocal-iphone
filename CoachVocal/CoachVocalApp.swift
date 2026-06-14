import SwiftUI
import SwiftData

@main
struct CoachVocalApp: App {
    // Conteneur SwiftData (équivalent de AppDatabase.getInstance).
    let container: ModelContainer

    init() {
        do {
            let schema = Schema(AppSchema.models)
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Impossible d'initialiser SwiftData: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

// Destinations de navigation (équivalent des Routes Compose).
enum Route: Hashable {
    case recording
    case postRecording(audioPath: String, durationMs: Int, transcription: String)
    case project(UUID)
    case labels
    case importAudio(url: URL)
}

struct RootView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .recording:
                        RecordingView(path: $path)
                    case let .postRecording(audioPath, durationMs, transcription):
                        PostRecordingView(path: $path, audioPath: audioPath,
                                          durationMs: durationMs, transcription: transcription)
                    case let .project(id):
                        ProjectView(path: $path, projectId: id)
                    case .labels:
                        LabelsView()
                    case let .importAudio(url):
                        ImportAudioView(path: $path, audioURL: url)
                    }
                }
        }
        .tint(AppColors.purple)
    }
}
