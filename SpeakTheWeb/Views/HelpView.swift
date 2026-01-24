import SwiftUI
import WebKit

/// In-app help view that displays bundled HTML content
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HelpWebView()
                .navigationTitle("Help")
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

/// WKWebView wrapper for displaying bundled HTML
struct HelpWebView: UIViewRepresentable {
    func makeUIView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.applicationNameForUserAgent = "SpeakTheWeb"

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground

        // Disable bouncing for native feel
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false

        // Allow back/forward navigation within help
        webView.allowsBackForwardNavigationGestures = true

        loadHelpContent(in: webView)

        return webView
    }

    func updateUIView(_: WKWebView, context _: Context) {
        // No updates needed
    }

    private func loadHelpContent(in webView: WKWebView) {
        guard let helpURL = resolveHelpURL() else {
            loadErrorPage(in: webView)
            return
        }

        let readAccessURL = helpURL.deletingLastPathComponent()
        webView.loadFileURL(helpURL, allowingReadAccessTo: readAccessURL)
    }

    private func resolveHelpURL() -> URL? {
        if let docsURL = Bundle.main.url(forResource: "docs", withExtension: nil) {
            let helpURL = docsURL.appendingPathComponent("help.html")
            if FileManager.default.fileExists(atPath: helpURL.path) {
                return helpURL
            }
        }

        if let helpURL = Bundle.main.url(forResource: "help", withExtension: "html", subdirectory: "docs") {
            return helpURL
        }

        return Bundle.main.url(forResource: "help", withExtension: "html")
    }

    private func loadErrorPage(in webView: WKWebView) {
        let errorHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, sans-serif;
                    padding: 40px 20px;
                    text-align: center;
                    color: #8e8e93;
                }
            </style>
        </head>
        <body>
            <p>Help content could not be loaded.</p>
            <p>Please visit our website for help.</p>
        </body>
        </html>
        """
        webView.loadHTMLString(errorHTML, baseURL: nil)
    }
}

#Preview {
    HelpView()
}
