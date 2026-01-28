import Foundation

enum ReaderMode: String, CaseIterable, Identifiable {
    case text = "Text"
    case safari = "Safari"

    var id: String {
        rawValue
    }
}
