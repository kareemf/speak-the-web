import Foundation

struct SherpaModel: Identifiable, Hashable, Codable {
    let id: String
    let languageCode: String
    let name: String
    let downloadURL: URL
    let compressedSizeBytes: Int

    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var languageDisplayName: String {
        let code = languageCode.replacingOccurrences(of: "_", with: "-")
        if let name = Locale.current.localizedString(forIdentifier: code) {
            return name.capitalized
        }
        return languageCode
    }
}

struct SherpaModelRecord: Identifiable, Codable {
    let id: String
    let languageCode: String
    let name: String
    let downloadURL: URL
    let compressedSizeBytes: Int
    let uncompressedSizeBytes: Int
    let localDirectory: String
    let modelPath: String
    let tokensPath: String?
    let configPath: String?

    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
