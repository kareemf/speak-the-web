import SwiftUI

/// Main content view of the app
struct ContentView: View {
    @EnvironmentObject var viewModel: ReaderViewModel

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if viewModel.hasContent {
                        // Article View
                        ArticleReaderView(viewModel: viewModel)
                    } else {
                        // URL Input View
                        URLInputView(viewModel: viewModel)
                    }
                }
            }
            .navigationTitle(viewModel.article?.title ?? "URL Reader")
            .navigationBarTitleDisplayMode(viewModel.hasContent ? .inline : .large)
            .toolbar {
                if viewModel.hasContent {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { viewModel.clearContent() }) {
                            Image(systemName: "xmark")
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            if !viewModel.article!.sections.isEmpty {
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
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ReaderViewModel())
}
