import SwiftUI

/// Landing view for entering a URL to read
struct HomeView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @FocusState private var isURLFieldFocused: Bool
    @State private var showClearConfirmation = false
    @State private var pendingDelete: RecentArticle?

    var body: some View {
        List {
            Section {
                // Compact header
                HStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read Article Aloud")
                            .font(.title3)
                            .fontWeight(.bold)
                    }

                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Section {
                // URL Input
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(.secondary)

                    TextField("Enter URL", text: $viewModel.urlInput)
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
                .contentShape(Rectangle())
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

            Section {
                // Fetch button
                Button(action: {
                    isURLFieldFocused = false
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
                .buttonStyle(.plain)
                .disabled(!viewModel.canFetch)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))

            Section(header: recentHeader) {
                if viewModel.recentArticles.isEmpty {
                    Text("Recent articles will appear here as you listen.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.recentArticles) { recent in
                        RecentArticleRow(
                            article: recent,
                            progress: viewModel.recentProgress(for: recent),
                            remainingText: viewModel.recentRemainingText(for: recent),
                            cachedLabel: viewModel.recentCachedAudioLabel(for: recent)
                        ) {
                            viewModel.loadRecentArticle(recent)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = recent
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.plain)
        .alert("Delete this recent article?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let recent = pendingDelete {
                    viewModel.removeRecentArticle(recent)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This also removes the cached article data.")
        }
        .alert("Clear all recent articles?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                viewModel.clearRecentArticles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes all cached article data.")
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.showError && !viewModel.showArticle },
            set: { if !$0 { viewModel.showError = false } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
    }

    private var recentHeader: some View {
        HStack {
            Text("Recent")
                .font(.headline)
            Spacer()
            if !viewModel.recentArticles.isEmpty {
                Button("Clear") {
                    showClearConfirmation = true
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
}

/// Row displaying a recent article
struct RecentArticleRow: View {
    let article: RecentArticle
    let progress: Double
    let remainingText: String
    let cachedLabel: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(article.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(article.host)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(article.timeAgo)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(remainingText)
                    Spacer()
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                if let cachedLabel {
                    Text(cachedLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView(viewModel: ReaderViewModel())
}
