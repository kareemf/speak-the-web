import SwiftUI

/// View displaying the article content with playback controls
struct ArticleReaderView: View {
    @ObservedObject var viewModel: ReaderViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Article content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Article metadata
                    if let article = viewModel.article {
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
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                        // Current word highlight
                        if viewModel.speechService.isPlaying {
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundColor(.accentColor)
                                Text("Speaking: ")
                                    .foregroundColor(.secondary)
                                Text(viewModel.speechService.currentWord)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .font(.caption)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                        }

                        // Article content
                        Text(article.content)
                            .font(.body)
                            .lineSpacing(6)
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                }
                .padding()
            }

            // Playback controls
            PlaybackControlsView(viewModel: viewModel)
        }
    }
}

#Preview {
    let viewModel = ReaderViewModel()
    return ArticleReaderView(viewModel: viewModel)
}
