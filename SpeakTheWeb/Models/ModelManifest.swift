import CryptoKit
import Foundation

/// Model integrity manifest for supply chain security.
/// Contains expected checksums, versions, and sizes for verified voice models.
///
/// This data is compiled into the binary (not a plist) to prevent tampering
/// on jailbroken devices.
///
/// ## Adding new models
/// 1. Download the model archive from the official GitHub release
/// 2. Compute SHA256: `shasum -a 256 <archive-file>`
/// 3. Note the exact file size in bytes
/// 4. Add entry to `knownModels` dictionary below
/// 5. Update app version and re-test
enum ModelManifest {
    /// Manifest entry for a verified model
    struct Entry {
        /// SHA256 hash of the compressed archive (hex string, lowercase)
        let sha256: String
        /// GitHub release tag version (e.g., "tts-models")
        let releaseTag: String
        /// Expected compressed file size in bytes
        let compressedSize: Int
        /// Source URL for verification (not used for download, just documentation)
        let sourceURL: String
    }

    /// Verification result
    enum VerificationResult {
        case verified
        case unknownModel
        case checksumMismatch(expected: String, actual: String)
        case sizeMismatch(expected: Int, actual: Int)
        case fileReadError(Error)
    }

    // MARK: - Known Models Registry

    /// Dictionary of model ID to expected integrity values.
    ///
    /// **IMPORTANT**: These checksums must be verified manually before release.
    /// Download each model from the official release, compute SHA256, and update.
    ///
    /// Format: `"model-id": Entry(sha256: "...", releaseTag: "...", compressedSize: ...)`
    static let knownModels: [String: Entry] = [
        // English models
        "vits-piper-en_US-amy-medium": Entry(
            sha256: "PLACEHOLDER_CHECKSUM_REQUIRED",
            releaseTag: "tts-models",
            compressedSize: 0,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-amy-medium.tar.bz2"
        ),
        "vits-piper-en_US-lessac-medium": Entry(
            sha256: "PLACEHOLDER_CHECKSUM_REQUIRED",
            releaseTag: "tts-models",
            compressedSize: 0,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2"
        ),
        "vits-piper-en_GB-alba-medium": Entry(
            sha256: "PLACEHOLDER_CHECKSUM_REQUIRED",
            releaseTag: "tts-models",
            compressedSize: 0,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2"
        ),
    ]

    // MARK: - Verification API

    /// Verifies integrity of a downloaded model archive.
    ///
    /// - Parameters:
    ///   - archiveURL: URL to the downloaded archive file
    ///   - modelId: The model identifier (e.g., "vits-piper-en_US-amy-medium")
    /// - Returns: Verification result indicating success or specific failure
    static func verify(archiveAt archiveURL: URL, modelId: String) -> VerificationResult {
        // Check if model is in manifest
        guard let expected = knownModels[modelId] else {
            return .unknownModel
        }

        // Skip verification for placeholder entries (dev mode only)
        #if DEBUG
            if expected.sha256 == "PLACEHOLDER_CHECKSUM_REQUIRED" {
                print(
                    "[ModelManifest] WARNING: Model '\(modelId)' has placeholder checksum - skipping verification in DEBUG mode"
                )
                return .verified
            }
        #else
            if expected.sha256 == "PLACEHOLDER_CHECKSUM_REQUIRED" {
                // In release builds, reject models without real checksums
                return .checksumMismatch(expected: "valid-checksum-required", actual: "placeholder")
            }
        #endif

        // Get file size (fast check before reading file content)
        let fileSize: Int
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
            fileSize = (attributes[.size] as? Int) ?? 0
        } catch {
            return .fileReadError(error)
        }

        // Verify size first (fast check)
        if expected.compressedSize > 0, fileSize != expected.compressedSize {
            return .sizeMismatch(expected: expected.compressedSize, actual: fileSize)
        }

        // Compute SHA256 by streaming to avoid loading entire file in memory
        // Model archives can be 50-100MB+, so we read in 1MB chunks
        let actualChecksum: String
        do {
            actualChecksum = try computeSHA256(of: archiveURL)
        } catch {
            return .fileReadError(error)
        }

        // Compare checksums (expected may be mixed case from manual input)
        if actualChecksum != expected.sha256.lowercased() {
            return .checksumMismatch(expected: expected.sha256, actual: actualChecksum)
        }

        #if DEBUG
            print("[ModelManifest] Model '\(modelId)' verified successfully")
        #endif

        return .verified
    }

    /// Computes SHA256 by streaming file in chunks to avoid loading entire file in memory.
    /// Model archives can be 50-100MB+, so we read in 1MB chunks.
    private static func computeSHA256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1MB chunks

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Checks if a model is in the known manifest (without verifying integrity).
    ///
    /// - Parameter modelId: The model identifier
    /// - Returns: true if the model is in the manifest, false otherwise
    static func isKnownModel(_ modelId: String) -> Bool {
        knownModels[modelId] != nil
    }

    /// Returns the expected entry for a model, if known.
    ///
    /// - Parameter modelId: The model identifier
    /// - Returns: The manifest entry, or nil if unknown
    static func entry(for modelId: String) -> Entry? {
        knownModels[modelId]
    }
}

// MARK: - Error Descriptions

extension ModelManifest.VerificationResult {
    var errorDescription: String? {
        switch self {
        case .verified:
            nil
        case .unknownModel:
            "This voice model is not in the verified models list. For security, only models with verified checksums can be used."
        case let .checksumMismatch(expected, actual):
            "Model integrity check failed. Expected checksum \(expected.prefix(8))..., got \(actual.prefix(8)).... The downloaded file may be corrupted or tampered with."
        case let .sizeMismatch(expected, actual):
            "Model size mismatch. Expected \(expected) bytes, got \(actual) bytes. The download may be incomplete."
        case let .fileReadError(error):
            "Could not read model file for verification: \(error.localizedDescription)"
        }
    }

    var isSuccess: Bool {
        if case .verified = self { return true }
        return false
    }
}
