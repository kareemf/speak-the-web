import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject var modelStore: SherpaOnnxModelStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Speech Engine") {
                    ForEach(SpeechEngineType.allCases) { engine in
                        Button {
                            viewModel.selectedSpeechEngine = engine
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(engine.displayName)
                                        .font(.headline)
                                    Text(engineDescription(for: engine))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if viewModel.selectedSpeechEngine == engine {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Playback Speed") {
                    Picker("Speed", selection: $viewModel.selectedRateIndex) {
                        ForEach(0..<SpeechService.ratePresets.count, id: \.self) { index in
                            Text(SpeechService.ratePresets[index].name)
                                .tag(index)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Current Speed")
                        Spacer()
                        Text(viewModel.currentRateName)
                            .foregroundColor(.secondary)
                    }
                }

                Section("AVSpeechSynthesizer") {
                    NavigationLink("Change Voice") {
                        AVSpeechSettingsView(viewModel: viewModel)
                    }

                    HStack {
                        Text("Current Voice")
                        Spacer()
                        Text(viewModel.speechService.selectedVoice?.name ?? "Default")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Sherpa-onnx") {
                    NavigationLink("Manage Models") {
                        SherpaModelsView(store: modelStore)
                    }

                    HStack {
                        Text("Selected Model")
                        Spacer()
                        Text(modelStore.selectedRecord?.displayName ?? "None")
                            .foregroundColor(.secondary)
                    }

                    if !SherpaOnnxRuntime.isAvailable {
                        Text("Sherpa-onnx runtime is not linked in this build.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func engineDescription(for engine: SpeechEngineType) -> String {
        switch engine {
        case .avSpeech:
            return "Instant generation, less natural sounding voices."
        case .sherpaOnnx:
            return "Slow generation, more natural sounding voices. Additional storage needed per voice."
        }
    }
}

#Preview {
    SettingsView(viewModel: ReaderViewModel(), modelStore: SherpaOnnxModelStore())
}
