import SwiftUI

/// Main content view of the app
struct ContentView: View {
    @EnvironmentObject var viewModel: ReaderViewModel
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                URLInputView(viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showHelp = true }) {
                            Image(systemName: "questionmark.circle")
                        }
                        
                        Button(action: { viewModel.showVoiceSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpView()
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
                SettingsView(viewModel: viewModel, modelStore: viewModel.sherpaModelStore)
            }
            .onChange(of: viewModel.showArticle) { _, isShowing in
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
