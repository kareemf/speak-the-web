import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject var modelStore: SherpaOnnxModelStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Speech Engine") {
                    Picker("Engine", selection: $viewModel.selectedSpeechEngine) {
                        ForEach(SpeechEngineType.allCases) { engine in
                            Text(engine.displayName)
                                .tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("AVSpeechSynthesizer") {
                    NavigationLink("Voice & Speed") {
                        AVSpeechSettingsView(viewModel: viewModel)
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
}

#Preview {
    SettingsView(viewModel: ReaderViewModel(), modelStore: SherpaOnnxModelStore())
}
