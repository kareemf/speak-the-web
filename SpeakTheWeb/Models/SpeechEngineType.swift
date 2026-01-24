import Foundation

enum SpeechEngineType: String, CaseIterable, Identifiable, Codable {
    case avSpeech
    case sherpaOnnx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avSpeech:
            "System (AVSpeech)"
        case .sherpaOnnx:
            "Sherpa-onnx (Piper)"
        }
    }
}
