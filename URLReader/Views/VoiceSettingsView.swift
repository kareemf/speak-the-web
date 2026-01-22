import SwiftUI
import AVFoundation

/// View for selecting voice and adjusting speech settings
struct AVSpeechSettingsView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @State private var previewSynthesizer = AVSpeechSynthesizer()

    var body: some View {
        List {
            // Voice Section
            Section("Voice") {
                ForEach(groupedVoices.keys.sorted(), id: \.self) { language in
                    DisclosureGroup(languageDisplayName(for: language)) {
                        ForEach(groupedVoices[language] ?? [], id: \.identifier) { voice in
                            VoiceRow(
                                voice: voice,
                                isSelected: viewModel.speechService.selectedVoice?.identifier == voice.identifier,
                                onSelect: {
                                    viewModel.speechService.setVoice(voice)
                                }
                            )
                        }
                    }
                }
            }

            // Preview Section
            Section("Preview") {
                Button(action: previewVoice) {
                    Label("Preview Current Voice", systemImage: "play.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("AVSpeech")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groupedVoices: [String: [AVSpeechSynthesisVoice]] {
        Dictionary(grouping: viewModel.speechService.availableVoices) { voice in
            String(voice.language.prefix(2))
        }
    }

    private func languageDisplayName(for code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private func previewVoice() {
        viewModel.activateVoicePreviewSession()
        let previewText = "Hello! This is a preview of the selected voice at the current speed."
        let utterance = AVSpeechUtterance(string: previewText)
        utterance.voice = viewModel.speechService.selectedVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * viewModel.currentRateMultiplier

        previewSynthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.speak(utterance)
    }
}

/// Row displaying a voice option
struct VoiceRow: View {
    let voice: AVSpeechSynthesisVoice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(voice.name)
                            .foregroundColor(.primary)

                        if voice.quality == .enhanced {
                            Text("Enhanced")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor)
                                .cornerRadius(4)
                        }
                    }

                    Text(voice.language)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
    }
}

#Preview {
    AVSpeechSettingsView(viewModel: ReaderViewModel())
}
