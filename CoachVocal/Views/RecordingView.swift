import SwiftUI

// Portage de RecordingScreen.kt — enregistrement + transcription temps réel.
struct RecordingView: View {
    @Binding var path: [Route]

    @State private var speech = SpeechRecognizerService()
    @State private var elapsed = 0
    @State private var pulse = false
    @State private var authorized = true

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(formatTime(elapsed))
                .font(.system(size: 56, weight: .light, design: .rounded))
                .foregroundStyle(speech.isRecording ? AppColors.recordingRed : .primary)

            Text(speech.status.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.top, 4)

            Spacer().frame(height: 20)

            if !speech.displayText.isEmpty {
                ScrollView {
                    Text(speech.displayText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(maxHeight: 200)
                .background(Color(.secondarySystemBackground).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
            } else if speech.isRecording {
                Text("La transcription apparaîtra ici...")
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 48)

            if speech.isRecording {
                Button(action: stopAndContinue) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(AppColors.recordingRed)
                        .clipShape(Circle())
                        .scaleEffect(pulse ? 1.15 : 1.0)
                }
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            }

            Spacer().frame(height: 32)

            Button("Annuler") {
                speech.cancel()
                path.removeLast()
            }

            Spacer()
        }
        .padding(24)
        .navigationBarBackButtonHidden(true)
        .task {
            authorized = await SpeechRecognizerService.requestAuthorization()
            if authorized {
                speech.start()
                pulse = true
            } else {
                speech.status = .denied
            }
        }
        .onReceive(timer) { _ in
            if speech.isRecording { elapsed += 1 }
        }
        .onDisappear {
            if speech.isRecording { speech.cancel() }
        }
    }

    private func stopAndContinue() {
        let result = speech.stop()
        // popUpTo(RECORDING, inclusive) puis navigate(postRecording).
        path.removeLast()
        path.append(.postRecording(
            audioPath: result.audioURL?.path ?? "",
            durationMs: result.durationMs,
            transcription: result.transcription
        ))
    }
}
