import Foundation

enum SherpaOnnxRuntime {
    static var isAvailable: Bool {
#if canImport(SherpaOnnx)
        return true
#else
        return false
#endif
    }
}
