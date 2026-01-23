import SwiftUI

/// View displaying the article content with playback controls
struct ArticleReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @State private var textViewHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if let article = viewModel.article {
                Picker("Reader Mode", selection: $viewModel.readerMode) {
                    ForEach(ReaderMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if viewModel.readerMode == .text {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Article metadata
                            VStack(alignment: .leading, spacing: 8) {
                                Text(article.title)
                                    .font(.title2)
                                    .fontWeight(.bold)

                                HStack {
                                    Label("\(article.wordCount) words", systemImage: "doc.text")
                                    Text("•")
                                    Label("\(article.estimatedReadingTime) min read", systemImage: "clock")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)

                                if let host = article.url.host {
                                    Link(destination: article.url) {
                                        Label(host, systemImage: "link")
                                            .font(.caption)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)

                            // Current word highlight
                            if viewModel.shouldShowCurrentWord {
                                HStack {
                                    Image(systemName: "waveform")
                                        .foregroundColor(.accentColor)
                                    Text("Speaking: ")
                                        .foregroundColor(.secondary)
                                    Text(viewModel.playbackCurrentWord)
                                        .fontWeight(.medium)
                                    Spacer()
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(8)
                            }

                            // Article content
                            GeometryReader { geometry in
                                SelectableTextView(
                                    text: article.content,
                                    width: geometry.size.width,
                                    height: $textViewHeight,
                                    font: UIFont.preferredFont(forTextStyle: .body),
                                    textColor: UIColor.label,
                                    lineSpacing: 6,
                                    onStartReadingFromSelection: { position in
                                        viewModel.startReading(from: position)
                                    }
                                )
                            }
                            .frame(height: textViewHeight)
                            .padding(12)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 0)
                        .padding(.bottom, 16)
                    }
                    .textSelection(.enabled)
                } else if viewModel.readerMode == .safari {
                    SafariReaderView(url: article.url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // Playback controls
            PlaybackControlsView(viewModel: viewModel)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.showError && viewModel.showArticle },
            set: { if !$0 { viewModel.showError = false } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
    }
}

#Preview {
    let viewModel = ReaderViewModel()
    return ArticleReaderView(viewModel: viewModel)
}
