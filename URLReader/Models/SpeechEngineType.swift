import Foundation

enum SpeechEngineType: String, CaseIterable, Identifiable, Codable {
    case avSpeech
    case sherpaOnnx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avSpeech:
            return "System (AVSpeech)"
        case .sherpaOnnx:
            return "Sherpa-onnx (Piper)"
        }
    }
}
