import Social
import UIKit
import UniformTypeIdentifiers

/// Share Extension view controller for receiving URLs from Safari
class ShareViewController: UIViewController {
    // MARK: - UI Elements

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.2
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Speak the Web"
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let urlLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        label.textAlignment = .center
        label.text = "Ready to read aloud"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var openButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Open in Speak the Web"
        config.image = UIImage(systemName: "play.circle.fill")
        config.imagePadding = 8
        config.cornerStyle = .large

        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(openInApp), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var cancelButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Cancel"

        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Properties

    private var sharedURL: URL?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractURL()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        view.addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(urlLabel)
        containerView.addSubview(statusLabel)
        containerView.addSubview(activityIndicator)
        containerView.addSubview(openButton)
        containerView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            urlLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            urlLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            activityIndicator.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),

            openButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            openButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            openButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            openButton.heightAnchor.constraint(equalToConstant: 50),

            cancelButton.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 8),
            cancelButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
        ])
    }

    // MARK: - URL Extraction

    private func extractURL() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments
        else {
            showError("No content to share")
            return
        }

        activityIndicator.startAnimating()
        statusLabel.text = "Loading..."

        // Try to find a URL in the attachments
        for attachment in attachments {
            // Check for URL type
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
                    DispatchQueue.main.async {
                        self?.activityIndicator.stopAnimating()

                        if let error {
                            self?.showError("Failed to load URL: \(error.localizedDescription)")
                            return
                        }

                        if let url = item as? URL {
                            self?.handleURL(url)
                        } else if let urlString = item as? String, let url = URL(string: urlString) {
                            self?.handleURL(url)
                        } else {
                            self?.showError("Invalid URL format")
                        }
                    }
                }
                return
            }

            // Check for plain text that might be a URL
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, error in
                    DispatchQueue.main.async {
                        self?.activityIndicator.stopAnimating()

                        if let error {
                            self?.showError("Failed to load content: \(error.localizedDescription)")
                            return
                        }

                        if let text = item as? String, let url = URL(string: text), url.scheme != nil {
                            self?.handleURL(url)
                        } else {
                            self?.showError("No valid URL found")
                        }
                    }
                }
                return
            }
        }

        activityIndicator.stopAnimating()
        showError("No URL found in shared content")
    }

    private func handleURL(_ url: URL) {
        sharedURL = url
        urlLabel.text = url.host ?? url.absoluteString
        statusLabel.text = "Ready to read aloud"
        openButton.isEnabled = true
    }

    private func showError(_ message: String) {
        statusLabel.text = message
        statusLabel.textColor = .systemRed
        openButton.isEnabled = false
    }

    // MARK: - Actions

    @objc private func openInApp() {
        guard let url = sharedURL else { return }

        // Save URL to shared UserDefaults (App Group)
        let sharedDefaults = UserDefaults(suiteName: "group.com.kareemf.SpeakTheWeb")
        sharedDefaults?.set(url.absoluteString, forKey: "SharedURL")
        sharedDefaults?.set(Date(), forKey: "SharedURLTimestamp")
        sharedDefaults?.synchronize()

        // Create the deep link URL
        let deepLinkURLString = "speaktheweb://open?url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"

        if let deepLinkURL = URL(string: deepLinkURLString) {
            // Open the main app via URL scheme
            var responder: UIResponder? = self
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(deepLinkURL, options: [:], completionHandler: nil)
                    break
                }
                responder = responder?.next
            }

            // Try alternative method for iOS 17+
            openURL(deepLinkURL)
        }

        // Complete the extension
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    @objc private func cancelShare() {
        extensionContext?.cancelRequest(withError: NSError(domain: "SpeakTheWebShare", code: 0, userInfo: nil))
    }

    /// Helper to open URL from extension
    @objc private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.perform(#selector(openURL(_:)), with: url)
                return
            }
            responder = responder?.next
        }
    }
}
