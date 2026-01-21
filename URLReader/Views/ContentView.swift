import SwiftUI

/// Main content view of the app
struct ContentView: View {
    @EnvironmentObject var viewModel: ReaderViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                URLInputView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $viewModel.showArticle) {
                ArticleReaderView(viewModel: viewModel)
                    .navigationTitle(viewModel.article?.title ?? "")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack {
                                if let article = viewModel.article, !article.sections.isEmpty {
                                    Button(action: { viewModel.showTableOfContents = true }) {
                                        Image(systemName: "list.bullet")
                                    }
                                }

                                Button(action: { viewModel.showVoiceSettings = true }) {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                    }
            }
            .sheet(isPresented: $viewModel.showTableOfContents) {
                TableOfContentsView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showVoiceSettings) {
                VoiceSettingsView(viewModel: viewModel)
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .onChange(of: viewModel.showArticle) { isShowing in
                if !isShowing {
                    viewModel.clearContent()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ReaderViewModel())
}
