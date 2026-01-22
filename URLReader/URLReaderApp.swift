import SwiftUI

@main
struct URLReaderApp: App {
    @StateObject private var viewModel = ReaderViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onAppear {
                    checkForSharedURL()
                }
        }
    }

    /// Handles incoming URLs from deep links (urlreader://open?url=...)
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "urlreader",
              url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems,
              let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
              let decodedURL = urlParam.removingPercentEncoding else {
            return
        }

        Task { @MainActor in
            viewModel.loadURL(decodedURL)
        }
    }

    /// Checks for URLs shared via App Group from the Share Extension
    private func checkForSharedURL() {
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.kareemf.URLReader"),
              let sharedURLString = sharedDefaults.string(forKey: "SharedURL"),
              let timestamp = sharedDefaults.object(forKey: "SharedURLTimestamp") as? Date else {
            return
        }

        // Only process if the shared URL is recent (within last 60 seconds)
        let timeSinceShare = Date().timeIntervalSince(timestamp)
        guard timeSinceShare < 60 else {
            // Clear old shared URL
            sharedDefaults.removeObject(forKey: "SharedURL")
            sharedDefaults.removeObject(forKey: "SharedURLTimestamp")
            return
        }

        // Clear the shared URL so we don't process it again
        sharedDefaults.removeObject(forKey: "SharedURL")
        sharedDefaults.removeObject(forKey: "SharedURLTimestamp")
        sharedDefaults.synchronize()

        Task { @MainActor in
            viewModel.loadURL(sharedURLString)
        }
    }
}
