import SwiftUI

/// View for entering a URL to read
struct URLInputView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Icon
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                // Title and description
                VStack(spacing: 12) {
                    Text("Read Any Article")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Enter a URL and listen to the content using text-to-speech")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // URL Input
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)

                        TextField("Enter URL (e.g., example.com/article)", text: $viewModel.urlInput)
                            .textFieldStyle(.plain)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isURLFieldFocused)
                            .submitLabel(.go)
                            .onSubmit {
                                Task {
                                    await viewModel.fetchContent()
                                }
                            }

                        if !viewModel.urlInput.isEmpty {
                            Button(action: { viewModel.urlInput = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)

                    // Fetch button
                    Button(action: {
                        Task {
                            await viewModel.fetchContent()
                        }
                    }) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "arrow.down.doc")
                            }
                            Text(viewModel.isLoading ? "Loading..." : "Fetch Article")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.canFetch ? Color.accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!viewModel.canFetch)
                }
                .padding(.horizontal)

                // Sample URL button
                Button(action: { viewModel.loadSampleURL() }) {
                    Label("Try a sample article", systemImage: "lightbulb")
                        .font(.footnote)
                }
                .foregroundColor(.secondary)

                Spacer(minLength: 40)

                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    Text("Features")
                        .font(.headline)
                        .padding(.horizontal)

                    FeatureRow(icon: "play.circle", title: "Playback Controls", description: "Play, pause, skip forward and backward")
                    FeatureRow(icon: "speedometer", title: "Adjustable Speed", description: "Listen at 0.5x to 2x speed")
                    FeatureRow(icon: "list.bullet.indent", title: "Table of Contents", description: "Jump to different sections")
                    FeatureRow(icon: "person.wave.2", title: "Voice Selection", description: "Choose from available voices")
                }
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)

                Spacer(minLength: 20)
            }
        }
        .onAppear {
            isURLFieldFocused = true
        }
    }
}

/// A row displaying a feature
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    URLInputView(viewModel: ReaderViewModel())
}
