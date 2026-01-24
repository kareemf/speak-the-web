import SwiftUI

struct SherpaModelsView: View {
    @ObservedObject var store: SherpaOnnxModelStore

    var body: some View {
        List {
            if store.isLoading {
                Section {
                    ProgressView("Loading models…")
                }
            }

            ForEach(groupedModels.keys.sorted(), id: \.self) { language in
                Section(language) {
                    ForEach(groupedModels[language] ?? []) { model in
                        SherpaModelRow(model: model, store: store)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sherpa Models")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Refresh") {
                    Task {
                        await store.refreshModels()
                    }
                }
            }
        }
        .task {
            if store.models.isEmpty {
                await store.refreshModels()
            }
        }
        .alert("Error", isPresented: $store.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred")
        }
    }

    private var groupedModels: [String: [SherpaModel]] {
        Dictionary(grouping: store.models) { model in
            model.languageDisplayName
        }
        .mapValues { models in
            models.sorted { $0.compressedSizeBytes > $1.compressedSizeBytes }
        }
    }
}

private struct SherpaModelRow: View {
    let model: SherpaModel
    @ObservedObject var store: SherpaOnnxModelStore

    private var isSelected: Bool {
        store.selectedModelId == model.id
    }

    private var isDownloaded: Bool {
        store.isDownloaded(model)
    }

    private var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file

        if let uncompressedSize = store.uncompressedSizeBytes(for: model) {
            return "On disk: \(formatter.string(fromByteCount: Int64(uncompressedSize)))"
        }

        return "Download: \(formatter.string(fromByteCount: Int64(model.compressedSizeBytes)))"
    }

    private var isBusy: Bool {
        switch store.downloadState(for: model) {
        case .downloading, .processing:
            return true
        case .idle, .failed:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.displayName)
                    .font(.headline)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }

            Text(sizeText)
                .font(.caption)
                .foregroundColor(.secondary)

            switch store.downloadState(for: model) {
            case let .downloading(progress):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            case .processing:
                ProgressView("Processing…")
                    .font(.caption)
            case let .failed(message):
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.red)
            default:
                EmptyView()
            }

            HStack(spacing: 12) {
                if isDownloaded {
                    Button("Select") {
                        store.select(model: model)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSelected)

                    Button("Delete") {
                        store.delete(model: model)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button("Download") {
                        store.download(model: model)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    SherpaModelsView(store: SherpaOnnxModelStore())
}
