import SafariServices
import SwiftUI

struct SafariReaderView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {
        // SFSafariViewController does not support updating the URL after creation.
    }
}
