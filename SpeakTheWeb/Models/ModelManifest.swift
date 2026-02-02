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

    // swiftlint:disable function_body_length
    /// Dictionary of model ID to expected integrity values.
    ///
    /// **IMPORTANT**: These checksums were computed from official sherpa-onnx releases.
    /// Last verified: 2026-02-01 from https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models
    ///
    /// Format: `"model-id": Entry(sha256: "...", releaseTag: "...", compressedSize: ...)`
    static let knownModels: [String: Entry] = [
        // MARK: - Arabic (ar)

        "vits-piper-ar_JO-kareem-medium": Entry(
            sha256: "da63872ef668f08fa1e57aeafeda1ddcf3c485c787be06b5142b2dead6b774a8",
            releaseTag: "tts-models",
            compressedSize: 4_947_968,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ar_JO-kareem-medium.tar.bz2"
        ),

        // MARK: - Catalan (ca)

        "vits-piper-ca_ES-upc_ona-medium": Entry(
            sha256: "85d418ac93cf1b4c9e0d690cdc9425cffb7f211275aafd325f54d3469a5ace8f",
            releaseTag: "tts-models",
            compressedSize: 6_205_440,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ca_ES-upc_ona-medium.tar.bz2"
        ),

        // MARK: - Czech (cs)

        "vits-piper-cs_CZ-jirka-medium": Entry(
            sha256: "5cca49293662c2b2455e58af2ab6b5e850a4c32644014f1581d64894a634d15c",
            releaseTag: "tts-models",
            compressedSize: 6_729_728,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-cs_CZ-jirka-medium.tar.bz2"
        ),

        // MARK: - Welsh (cy)

        "vits-piper-cy_GB-bu_tts-medium": Entry(
            sha256: "e7988aaa246d230cefb1863c0f6a6f74ec57ee48c9b5253d8ef747df8233b9cf",
            releaseTag: "tts-models",
            compressedSize: 7_139_328,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-cy_GB-bu_tts-medium.tar.bz2"
        ),
        "vits-piper-cy_GB-gwryw_gogleddol-medium": Entry(
            sha256: "faaa8cdffef180c1acf0be147ed1246464db856edd159c45a4d10780ed2268bb",
            releaseTag: "tts-models",
            compressedSize: 7_987_200,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-cy_GB-gwryw_gogleddol-medium.tar.bz2"
        ),

        // MARK: - Danish (da)

        "vits-piper-da_DK-talesyntese-medium": Entry(
            sha256: "5997be8a693ac9984886112519adf92b79871d2d11af1f6d1719bcba55164f2f",
            releaseTag: "tts-models",
            compressedSize: 3_977_216,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-da_DK-talesyntese-medium.tar.bz2"
        ),

        // MARK: - German (de)

        "vits-piper-de_DE-glados_turret-medium": Entry(
            sha256: "1df978cf1d0a9e35cf5f32416ea99bc060207a75f5ebcfac3f363a079d711207",
            releaseTag: "tts-models",
            compressedSize: 6_152_192,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-de_DE-glados_turret-medium.tar.bz2"
        ),
        "vits-piper-de_DE-glados-medium": Entry(
            sha256: "de01396808dec54fa5c0393396b6c80706b08c0bd2faa1a4d4bf043f16a77d97",
            releaseTag: "tts-models",
            compressedSize: 7_073_792,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-de_DE-glados-medium.tar.bz2"
        ),
        "vits-piper-de_DE-thorsten_emotional-medium": Entry(
            sha256: "c238ef2accc3b43a062117bd1d6a93d670abced9682afecdbff84a9b84eb13b7",
            releaseTag: "tts-models",
            compressedSize: 8_253_440,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-de_DE-thorsten_emotional-medium.tar.bz2"
        ),
        "vits-piper-de_DE-thorsten-medium": Entry(
            sha256: "8df40bd63a0737877edd68b591eeeabff3e4c609949e2432a9da85312a0452cc",
            releaseTag: "tts-models",
            compressedSize: 6_156_288,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-de_DE-thorsten-medium.tar.bz2"
        ),

        // MARK: - English UK (en_GB)

        "vits-piper-en_GB-alan-medium": Entry(
            sha256: "bb5424e6cb3486ff034b3a790b9b5cea46c9399e176f17d814c0abb10b8ca839",
            releaseTag: "tts-models",
            compressedSize: 8_122_368,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alan-medium.tar.bz2"
        ),
        "vits-piper-en_GB-alba-medium": Entry(
            sha256: "1e44a513469319d40e300dc6634e8e20f17238034885a7999348690a31674a3f",
            releaseTag: "tts-models",
            compressedSize: 5_255_168,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2"
        ),
        "vits-piper-en_GB-aru-medium": Entry(
            sha256: "14430d8bf4ef1b6c2222c7225a5a712cb1ec9b10e23ce9c6e5f0b61d835627c0",
            releaseTag: "tts-models",
            compressedSize: 7_655_424,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-aru-medium.tar.bz2"
        ),
        "vits-piper-en_GB-cori-medium": Entry(
            sha256: "2d66f11c0310a488d5014c91e087739fa7375a4d05858e19b84b4762b4895442",
            releaseTag: "tts-models",
            compressedSize: 6_385_664,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-cori-medium.tar.bz2"
        ),
        "vits-piper-en_GB-jenny_dioco-medium": Entry(
            sha256: "eb2448d5b58f790519c318e9543c5d3af8b3c9d680db6e39f3c2e57d6a4ed2e5",
            releaseTag: "tts-models",
            compressedSize: 5_500_928,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-jenny_dioco-medium.tar.bz2"
        ),
        "vits-piper-en_GB-northern_english_male-medium": Entry(
            sha256: "26185f9b590114dbe46f9f21202faecf7bc79b6e7605ea1cffbc273390e44ae7",
            releaseTag: "tts-models",
            compressedSize: 6_594_560,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-northern_english_male-medium.tar.bz2"
        ),
        "vits-piper-en_GB-semaine-medium": Entry(
            sha256: "33053a2b326a63c6ab0d685ecfce3f3a7dd53b493f1a742d3f42f33b37aadbfc",
            releaseTag: "tts-models",
            compressedSize: 6_369_280,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-semaine-medium.tar.bz2"
        ),
        "vits-piper-en_GB-southern_english_female-medium": Entry(
            sha256: "61b4fdc3d15b7a860624750acafc624a0c8b23d86c8cbd6628fee43e2e735407",
            releaseTag: "tts-models",
            compressedSize: 6_938_624,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-southern_english_female-medium.tar.bz2"
        ),
        "vits-piper-en_GB-southern_english_male-medium": Entry(
            sha256: "5cb4ade1e6a600fc1b8e47976046384ef0df97dfca828cdc204fd258cb6df083",
            releaseTag: "tts-models",
            compressedSize: 4_403_200,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-southern_english_male-medium.tar.bz2"
        ),
        "vits-piper-en_GB-vctk-medium": Entry(
            sha256: "1a464c9ae3de430b1a8530936ae34958bdb256d6835416156dea07e8960c8c56",
            releaseTag: "tts-models",
            compressedSize: 9_236_480,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-vctk-medium.tar.bz2"
        ),

        // MARK: - English US (en_US)

        "vits-piper-en_US-arctic-medium": Entry(
            sha256: "f90fe24ea0abb1a98435804a21bec1bdbdfd347fb84d4d785f6f78de61818d8e",
            releaseTag: "tts-models",
            compressedSize: 6_627_328,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-arctic-medium.tar.bz2"
        ),
        "vits-piper-en_US-bryce-medium": Entry(
            sha256: "f96d359a9c05a9304490310e95530163c1c33d5ae3bccf887b4c11328b926130",
            releaseTag: "tts-models",
            compressedSize: 8_151_040,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-bryce-medium.tar.bz2"
        ),
        "vits-piper-en_US-hfc_female-medium": Entry(
            sha256: "4b556ce98654db87fe7f2754d468478a5500c06c620999f0407e344826002101",
            releaseTag: "tts-models",
            compressedSize: 6_303_744,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-hfc_female-medium.tar.bz2"
        ),
        "vits-piper-en_US-hfc_male-medium": Entry(
            sha256: "5adeef2c9d5f5dc3843be7ab9f708d03c08277bdf6669aeb2c88147714cd1ada",
            releaseTag: "tts-models",
            compressedSize: 3_944_448,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-hfc_male-medium.tar.bz2"
        ),
        "vits-piper-en_US-joe-medium": Entry(
            sha256: "665e2c6c4d05fffaf7325b16dbca7d2e90b873992df785a971bf760772431312",
            releaseTag: "tts-models",
            compressedSize: 4_452_352,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-joe-medium.tar.bz2"
        ),
        "vits-piper-en_US-john-medium": Entry(
            sha256: "f7a7d34b98abcd421adf438dbfc45cacdb753737ed1c915fab9a7898b09ff85f",
            releaseTag: "tts-models",
            compressedSize: 8_351_744,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-john-medium.tar.bz2"
        ),
        "vits-piper-en_US-kristin-medium": Entry(
            sha256: "ac3c8a6b113156cd9166b7bbf488c8c5c05539a1d795eb482d920db07cbe071f",
            releaseTag: "tts-models",
            compressedSize: 5_206_016,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-kristin-medium.tar.bz2"
        ),
        "vits-piper-en_US-kusal-medium": Entry(
            sha256: "fd2afaea88f9e9950378e3f2e6aa3ba840dd10aadd9f2eb56b40be38c8c7240c",
            releaseTag: "tts-models",
            compressedSize: 5_124_096,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-kusal-medium.tar.bz2"
        ),
        "vits-piper-en_US-l2arctic-medium": Entry(
            sha256: "18c60933a421cb7141e309041cf50d4b2e502e5b1db4e268909d1301615ec745",
            releaseTag: "tts-models",
            compressedSize: 7_086_080,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-l2arctic-medium.tar.bz2"
        ),
        "vits-piper-en_US-lessac-medium": Entry(
            sha256: "617aa81b5d6f1fd11ab10a52c6d979adb93779d3188b624f3df31cd30952f927",
            releaseTag: "tts-models",
            compressedSize: 5_173_248,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2"
        ),
        "vits-piper-en_US-libritts_r-medium": Entry(
            sha256: "20472019fb05612d416cd96196aea6ec404dc9186a108065883a1080dc970d0e",
            releaseTag: "tts-models",
            compressedSize: 4_337_664,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-libritts_r-medium.tar.bz2"
        ),
        "vits-piper-en_US-ljspeech-medium": Entry(
            sha256: "6f316df2645ffc0f83f76cb7a72db309bca06608554bb22efb10fe0d18d3d972",
            releaseTag: "tts-models",
            compressedSize: 2_863_104,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ljspeech-medium.tar.bz2"
        ),
        "vits-piper-en_US-norman-medium": Entry(
            sha256: "9229375578ac7a5d2abc98a5c82eefcc3dbdccee19663a16b53ce56148366182",
            releaseTag: "tts-models",
            compressedSize: 8_699_904,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-norman-medium.tar.bz2"
        ),
        "vits-piper-en_US-reza_ibrahim-medium": Entry(
            sha256: "c5d9c7efa4a135aab896bd71a138b60819c161dd4fdeaeac204310beda70cfc9",
            releaseTag: "tts-models",
            compressedSize: 6_438_912,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-reza_ibrahim-medium.tar.bz2"
        ),
        "vits-piper-en_US-ryan-medium": Entry(
            sha256: "cdfc5e77f149fcbf2f3982e413b6b54de06b22114022a7c9c30aa08d555e7d85",
            releaseTag: "tts-models",
            compressedSize: 3_796_992,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ryan-medium.tar.bz2"
        ),
        "vits-piper-en_US-sam-medium": Entry(
            sha256: "591cc05aa138fcd30f1bc3de9518d38c37e12ac3eaec85b9d7f37cee70e9d8a0",
            releaseTag: "tts-models",
            compressedSize: 4_358_144,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-sam-medium.tar.bz2"
        ),

        // MARK: - Spanish (es)

        "vits-piper-es_ES-davefx-medium": Entry(
            sha256: "146c58a303fcd2798416f2c1539ecb9d409fbc98e2529cb63934078eb5e34b9f",
            releaseTag: "tts-models",
            compressedSize: 3_485_696,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_ES-davefx-medium.tar.bz2"
        ),
        "vits-piper-es_ES-glados-medium": Entry(
            sha256: "2b85a2df8ccce9f815533ab1551bcbf626d30af394be14c3741d2068e14d7b0a",
            releaseTag: "tts-models",
            compressedSize: 4_681_728,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_ES-glados-medium.tar.bz2"
        ),
        "vits-piper-es_ES-sharvard-medium": Entry(
            sha256: "d98e7a953ebd3424ab277db06b038c47c8bafdd6c839c49a24842253f88ba5ca",
            releaseTag: "tts-models",
            compressedSize: 8_351_744,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_ES-sharvard-medium.tar.bz2"
        ),
        "vits-piper-es_MX-ald-medium": Entry(
            sha256: "1fb2c1e2510e88544b5d92a87fa665ccfb40fdee436942d6664ef7180927b823",
            releaseTag: "tts-models",
            compressedSize: 5_005_312,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es_MX-ald-medium.tar.bz2"
        ),
        "vits-piper-es-glados-medium": Entry(
            sha256: "fef632cc256ee62989fbcd4a0f13d9a1f885cf2e5ff164cd33f2a328f8df8a63",
            releaseTag: "tts-models",
            compressedSize: 5_136_384,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-es-glados-medium.tar.bz2"
        ),

        // MARK: - Persian (fa)

        "vits-piper-fa_en-rezahedayatfar-ibrahimwalk-medium": Entry(
            sha256: "c8552b2175bb69abf01f7e550cfc28e9ce130c294bb6ec8ffe84b3d7cda79622",
            releaseTag: "tts-models",
            compressedSize: 5_419_008,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fa_en-rezahedayatfar-ibrahimwalk-medium.tar.bz2"
        ),
        "vits-piper-fa_IR-amir-medium": Entry(
            sha256: "f3efa49c7c98b1a431ab10584d7b4dd67eeef9dc39dbaa57a288573ee5a6882a",
            releaseTag: "tts-models",
            compressedSize: 6_656_000,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fa_IR-amir-medium.tar.bz2"
        ),
        "vits-piper-fa_IR-ganji_adabi-medium": Entry(
            sha256: "b79012f534ad7fa4e8dd7d78a597e53fc9b81148d84a6542d1c82b570ccbbaac",
            releaseTag: "tts-models",
            compressedSize: 6_746_112,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fa_IR-ganji_adabi-medium.tar.bz2"
        ),
        "vits-piper-fa_IR-ganji-medium": Entry(
            sha256: "c22b2d0caad51c1794d5ed45eb5e90540da758882371fa1613a4e6ed498b04c3",
            releaseTag: "tts-models",
            compressedSize: 2_879_488,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fa_IR-ganji-medium.tar.bz2"
        ),
        "vits-piper-fa_IR-gyro-medium": Entry(
            sha256: "a80a8c0338d82da6b6578c758f540a3aa3b9734c10df3c2b8e24797fa15fe6fb",
            releaseTag: "tts-models",
            compressedSize: 6_103_040,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fa_IR-gyro-medium.tar.bz2"
        ),
        "vits-piper-fa_IR-reza_ibrahim-medium": Entry(
            sha256: "9c4873401a5e87d8b8492caf3be3f05d4639b46c3970ea28278cb02b26701e5c",
            releaseTag: "tts-models",
            compressedSize: 7_860_224,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fa_IR-reza_ibrahim-medium.tar.bz2"
        ),

        // MARK: - Finnish (fi)

        "vits-piper-fi_FI-harri-medium": Entry(
            sha256: "b273988dcffe3bb961a0042419da60cee275d79ccda435c20ca4873486385096",
            releaseTag: "tts-models",
            compressedSize: 2_961_408,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fi_FI-harri-medium.tar.bz2"
        ),

        // MARK: - French (fr)

        "vits-piper-fr_FR-siwis-medium": Entry(
            sha256: "19e89ee0be64b71213811a97ca03389960c1d6e720360a83752b77470bb0bc0c",
            releaseTag: "tts-models",
            compressedSize: 4_665_344,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-siwis-medium.tar.bz2"
        ),
        "vits-piper-fr_FR-tom-medium": Entry(
            sha256: "8b4291418f61134ba92f5011d292bbeb19c9e3a891702e779e5bf2109554c661",
            releaseTag: "tts-models",
            compressedSize: 8_937_472,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-tom-medium.tar.bz2"
        ),
        "vits-piper-fr_FR-upmc-medium": Entry(
            sha256: "c2340e6ed0d09b2187ae84b58516b34a3fe7edae917c25409a2704dc99be840e",
            releaseTag: "tts-models",
            compressedSize: 4_169_728,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-upmc-medium.tar.bz2"
        ),

        // MARK: - Hindi (hi)

        "vits-piper-hi_IN-pratham-medium": Entry(
            sha256: "660133b64e0d28aca9209c91e13ead4ceeeb156de5257b44dadbba74678f8d73",
            releaseTag: "tts-models",
            compressedSize: 5_705_728,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-hi_IN-pratham-medium.tar.bz2"
        ),
        "vits-piper-hi_IN-priyamvada-medium": Entry(
            sha256: "b679abaaf3f2476c4e300d207554d016f1f73fa3766269f82f8bd98eb5b6f4c3",
            releaseTag: "tts-models",
            compressedSize: 5_943_296,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-hi_IN-priyamvada-medium.tar.bz2"
        ),
        "vits-piper-hi_IN-rohan-medium": Entry(
            sha256: "4ddc6c5af9a288ee96b9ab039a590f53243d8d72b3a87de57696bcdcba0f53b5",
            releaseTag: "tts-models",
            compressedSize: 6_836_224,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-hi_IN-rohan-medium.tar.bz2"
        ),

        // MARK: - Hungarian (hu)

        "vits-piper-hu_HU-anna-medium": Entry(
            sha256: "ba0009677b3bd89b044b526e85b56db0212a1fc56154e68994c025879ac51552",
            releaseTag: "tts-models",
            compressedSize: 5_877_760,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-hu_HU-anna-medium.tar.bz2"
        ),
        "vits-piper-hu_HU-berta-medium": Entry(
            sha256: "9311387197ca128a65ec51d4c544894bb4fde42813f02ba8309c62f41da020f7",
            releaseTag: "tts-models",
            compressedSize: 5_947_392,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-hu_HU-berta-medium.tar.bz2"
        ),
        "vits-piper-hu_HU-imre-medium": Entry(
            sha256: "aa1d5b28e4be5d070566fd672dbeb91b07bf1363808489d3e0e7e356ca7c53e7",
            releaseTag: "tts-models",
            compressedSize: 8_163_328,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-hu_HU-imre-medium.tar.bz2"
        ),

        // MARK: - Indonesian (id)

        "vits-piper-id_ID-news_tts-medium": Entry(
            sha256: "28dbc3bc6b255e09a916dc757c46fc76010e099893cca44876e56518b38e395e",
            releaseTag: "tts-models",
            compressedSize: 5_304_320,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-id_ID-news_tts-medium.tar.bz2"
        ),

        // MARK: - Icelandic (is)

        "vits-piper-is_IS-bui-medium": Entry(
            sha256: "032ef8b88b161ee70d7be955372bad5154df0aa880776e0fd6fb8ed197c01d87",
            releaseTag: "tts-models",
            compressedSize: 8_548_352,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-is_IS-bui-medium.tar.bz2"
        ),
        "vits-piper-is_IS-salka-medium": Entry(
            sha256: "4257b13fdc0c4540c792661314212f789b1016366b1d0607fec506029403395f",
            releaseTag: "tts-models",
            compressedSize: 5_369_856,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-is_IS-salka-medium.tar.bz2"
        ),
        "vits-piper-is_IS-steinn-medium": Entry(
            sha256: "fc14eba81b87627266f056a4e527724a7d573318a87b2686944194a2f9d843d2",
            releaseTag: "tts-models",
            compressedSize: 7_680_000,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-is_IS-steinn-medium.tar.bz2"
        ),
        "vits-piper-is_IS-ugla-medium": Entry(
            sha256: "527d12838c666316f0980b83084fc29f504722c513e2fce0a52598442cf1c5bc",
            releaseTag: "tts-models",
            compressedSize: 4_042_752,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-is_IS-ugla-medium.tar.bz2"
        ),

        // MARK: - Italian (it)

        "vits-piper-it_IT-paola-medium": Entry(
            sha256: "161d1c54f47665dad8b8fa4664c43c0c41c0b464182d5ef9656ec8febfcae0a9",
            releaseTag: "tts-models",
            compressedSize: 5_926_912,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-it_IT-paola-medium.tar.bz2"
        ),

        // MARK: - Georgian (ka)

        "vits-piper-ka_GE-natia-medium": Entry(
            sha256: "e2b6c417a80e607a8d9170826ee286bbefa82ce4dd1fe24f8998a586a54850f9",
            releaseTag: "tts-models",
            compressedSize: 5_304_320,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ka_GE-natia-medium.tar.bz2"
        ),

        // MARK: - Luxembourgish (lb)

        "vits-piper-lb_LU-marylux-medium": Entry(
            sha256: "77ada7ec69f572551b3d1623a97e3d6a84413235cab0538732cef93ca5124c58",
            releaseTag: "tts-models",
            compressedSize: 8_429_568,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-lb_LU-marylux-medium.tar.bz2"
        ),

        // MARK: - Latvian (lv)

        "vits-piper-lv_LV-aivars-medium": Entry(
            sha256: "552c39dfac9d81b16e6633cfcdd6b32f0db27e2d51b87dddacc43d0a16aab82a",
            releaseTag: "tts-models",
            compressedSize: 6_385_664,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-lv_LV-aivars-medium.tar.bz2"
        ),

        // MARK: - Malayalam (ml)

        "vits-piper-ml_IN-arjun-medium": Entry(
            sha256: "6e2fb5dffb949c2ac095195869ed5a301ea556dfa44db55680c4078c374acc2f",
            releaseTag: "tts-models",
            compressedSize: 4_419_584,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ml_IN-arjun-medium.tar.bz2"
        ),
        "vits-piper-ml_IN-meera-medium": Entry(
            sha256: "78ad819cb384dd2b2419b956aa6a8eb5ccfc7b2338e81b56bc98063bf1863574",
            releaseTag: "tts-models",
            compressedSize: 4_632_576,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ml_IN-meera-medium.tar.bz2"
        ),

        // MARK: - Nepali (ne)

        "vits-piper-ne_NP-chitwan-medium": Entry(
            sha256: "6bcf43bd1a37ea70750b80c8e92bc476ffb00f9c0c34eec08b2706c751dea404",
            releaseTag: "tts-models",
            compressedSize: 7_319_552,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ne_NP-chitwan-medium.tar.bz2"
        ),
        "vits-piper-ne_NP-google-medium": Entry(
            sha256: "8f07fcf41a128151d3368bb187420cacb5c1b4a28de3a90a6880c93cb9d21e5b",
            releaseTag: "tts-models",
            compressedSize: 5_287_936,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ne_NP-google-medium.tar.bz2"
        ),

        // MARK: - Dutch (nl)

        "vits-piper-nl_BE-nathalie-medium": Entry(
            sha256: "baa209262b9fafaeae74f60e313343b76fc0cdefc49d9e04418c317fcc75b66b",
            releaseTag: "tts-models",
            compressedSize: 8_441_856,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-nl_BE-nathalie-medium.tar.bz2"
        ),
        "vits-piper-nl_BE-rdh-medium": Entry(
            sha256: "3096113d72e7e56c8be07ab1b0d8fecdf34c9f378a98c06d0780fbed3164f7b6",
            releaseTag: "tts-models",
            compressedSize: 5_013_504,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-nl_BE-rdh-medium.tar.bz2"
        ),
        "vits-piper-nl_NL-pim-medium": Entry(
            sha256: "c6760b49ba0806d57e8a135545dc94adb2cd26ca0e158d85047932493c1000ac",
            releaseTag: "tts-models",
            compressedSize: 6_369_280,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-nl_NL-pim-medium.tar.bz2"
        ),
        "vits-piper-nl_NL-ronnie-medium": Entry(
            sha256: "1f153387d9ddc11021b0b81c20202e9dc88426a527d3ba5ebe229ff41504ab03",
            releaseTag: "tts-models",
            compressedSize: 6_713_344,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-nl_NL-ronnie-medium.tar.bz2"
        ),

        // MARK: - Norwegian (no)

        "vits-piper-no_NO-talesyntese-medium": Entry(
            sha256: "237d82772bdfc41c0ca5f0f8b228550dc2b2ef2d7192ad4f68a2a856661ec24f",
            releaseTag: "tts-models",
            compressedSize: 6_139_904,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-no_NO-talesyntese-medium.tar.bz2"
        ),

        // MARK: - Polish (pl)

        "vits-piper-pl_PL-darkman-medium": Entry(
            sha256: "951d84ddf93a2add3ace097623040783d3ff51c9eb6e7c0090b1c0a9bc3acafd",
            releaseTag: "tts-models",
            compressedSize: 4_108_288,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-darkman-medium.tar.bz2"
        ),
        "vits-piper-pl_PL-gosia-medium": Entry(
            sha256: "decf4b235864fc1bab21bd12fc4d020b5adf10b5a38879ecce7f830cde683b49",
            releaseTag: "tts-models",
            compressedSize: 7_045_120,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-gosia-medium.tar.bz2"
        ),
        "vits-piper-pl_PL-jarvis_wg_glos-medium": Entry(
            sha256: "95d6b10df127dd2399501bb93834c430c1317ea4399e0c44bde7ea8246e133cc",
            releaseTag: "tts-models",
            compressedSize: 4_780_032,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-jarvis_wg_glos-medium.tar.bz2"
        ),
        "vits-piper-pl_PL-justyna_wg_glos-medium": Entry(
            sha256: "35314a8481483e629a7b98f5c36c8806e29b87f7591db4fff24ef671e5498d66",
            releaseTag: "tts-models",
            compressedSize: 5_390_336,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-justyna_wg_glos-medium.tar.bz2"
        ),
        "vits-piper-pl_PL-mc_speech-medium": Entry(
            sha256: "7ae60e05ed8db6777330c69cc19d556400030f96768714d07dcba62c8736ef70",
            releaseTag: "tts-models",
            compressedSize: 3_551_232,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-mc_speech-medium.tar.bz2"
        ),
        "vits-piper-pl_PL-meski_wg_glos-medium": Entry(
            sha256: "ed117e4a24ab22f8d742e40fa5209a3eea3e12a232cd47b089d2bf9bcf535052",
            releaseTag: "tts-models",
            compressedSize: 6_942_720,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-meski_wg_glos-medium.tar.bz2"
        ),
        "vits-piper-pl_PL-zenski_wg_glos-medium": Entry(
            sha256: "f911854b21f9b40ceebb8fa7b169e0c3480f81751423f61adf142a0d78fada46",
            releaseTag: "tts-models",
            compressedSize: 8_019_968,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-zenski_wg_glos-medium.tar.bz2"
        ),

        // MARK: - Portuguese (pt)

        "vits-piper-pt_BR-cadu-medium": Entry(
            sha256: "5017e8838a4f9da07e45bdcd296a60f4b76ad98b26393ac4e934fbc54918acf3",
            releaseTag: "tts-models",
            compressedSize: 13_938_688,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pt_BR-cadu-medium.tar.bz2"
        ),
        "vits-piper-pt_BR-faber-medium": Entry(
            sha256: "b90ce1e81ece77f5a05d659d5d026a536b91cd8cb8d3f87f14d384bbc2b6587a",
            releaseTag: "tts-models",
            compressedSize: 3_698_688,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pt_BR-faber-medium.tar.bz2"
        ),
        "vits-piper-pt_BR-jeff-medium": Entry(
            sha256: "511c6e77481ed78d71bbee9bc787af37d2d540e4edeb3368d2f10c4bb2238422",
            releaseTag: "tts-models",
            compressedSize: 3_829_760,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pt_BR-jeff-medium.tar.bz2"
        ),
        "vits-piper-pt_PT-tugao-medium": Entry(
            sha256: "de3d133965414ac3e17161add4db9ef1684cbec7da410fd444df7a345609242a",
            releaseTag: "tts-models",
            compressedSize: 4_698_112,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pt_PT-tugao-medium.tar.bz2"
        ),

        // MARK: - Romanian (ro)

        "vits-piper-ro_RO-mihai-medium": Entry(
            sha256: "285670973b964f4c8de1a8567e74568f2f8fc6b4722e5068a5ae3558648f856d",
            releaseTag: "tts-models",
            compressedSize: 7_057_408,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ro_RO-mihai-medium.tar.bz2"
        ),

        // MARK: - Russian (ru)

        "vits-piper-ru_RU-denis-medium": Entry(
            sha256: "31b2d7df0ba1ea395c75ce60cd0f67fcd4082df5881a59aabab3dbdab6fe78f1",
            releaseTag: "tts-models",
            compressedSize: 5_238_784,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-denis-medium.tar.bz2"
        ),
        "vits-piper-ru_RU-dmitri-medium": Entry(
            sha256: "ccc2c4aa79f967fc998f85ca94cee806661c1aecd4b6700707287e2f0531171c",
            releaseTag: "tts-models",
            compressedSize: 6_557_696,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-dmitri-medium.tar.bz2"
        ),
        "vits-piper-ru_RU-irina-medium": Entry(
            sha256: "0b84524a0a18abf105dc38d984b4fc24193d4717306346537751a9c2eb1c6278",
            releaseTag: "tts-models",
            compressedSize: 6_320_128,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-irina-medium.tar.bz2"
        ),
        "vits-piper-ru_RU-ruslan-medium": Entry(
            sha256: "0c33b2f65a18d1c8f0023232444dbfde4f12da8bf2e27eb466fecf9acf3dcfe9",
            releaseTag: "tts-models",
            compressedSize: 9_986_048,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-ru_RU-ruslan-medium.tar.bz2"
        ),

        // MARK: - Slovak (sk)

        "vits-piper-sk_SK-lili-medium": Entry(
            sha256: "56afec730db287c657f9b6869c6c954143417dfeded0117b602ba4cfbceae6d0",
            releaseTag: "tts-models",
            compressedSize: 3_686_400,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-sk_SK-lili-medium.tar.bz2"
        ),

        // MARK: - Slovenian (sl)

        "vits-piper-sl_SI-artur-medium": Entry(
            sha256: "a4efb10a0cbe13dbaac1ed173d277cd6dc94a30f771dac557b66bfa1438f72e7",
            releaseTag: "tts-models",
            compressedSize: 8_400_896,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-sl_SI-artur-medium.tar.bz2"
        ),

        // MARK: - Serbian (sr)

        "vits-piper-sr_RS-serbski_institut-medium": Entry(
            sha256: "d71f1072402dcaebcb79340d88950a0ea9c034145b5a27ad0711518584cb9c64",
            releaseTag: "tts-models",
            compressedSize: 6_533_120,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-sr_RS-serbski_institut-medium.tar.bz2"
        ),

        // MARK: - Swedish (sv)

        "vits-piper-sv_SE-lisa-medium": Entry(
            sha256: "0e15dc11c8af5c16383af9444b9f2db4fcf9e499b60086f3030536122ef86c34",
            releaseTag: "tts-models",
            compressedSize: 6_762_496,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-sv_SE-lisa-medium.tar.bz2"
        ),
        "vits-piper-sv_SE-nst-medium": Entry(
            sha256: "1df1ff967cf19ad483cf9b983ffa189a239948feb37387d21945f5f7f6da8729",
            releaseTag: "tts-models",
            compressedSize: 6_434_816,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-sv_SE-nst-medium.tar.bz2"
        ),

        // MARK: - Swahili (sw)

        "vits-piper-sw_CD-lanfrica-medium": Entry(
            sha256: "28cf2426dbfd6df96ae982b1189740ad39ef5c28b10de3f70620bc496f1735c8",
            releaseTag: "tts-models",
            compressedSize: 7_786_496,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-sw_CD-lanfrica-medium.tar.bz2"
        ),

        // MARK: - Turkish (tr)

        "vits-piper-tr_TR-dfki-medium": Entry(
            sha256: "b417f47c153363fdddbde1771a90e82862add465c2e98972e2a3496f9ff2d2e3",
            releaseTag: "tts-models",
            compressedSize: 4_894_720,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-tr_TR-dfki-medium.tar.bz2"
        ),
        "vits-piper-tr_TR-fahrettin-medium": Entry(
            sha256: "ffe6b3b41f3628431fba878e3059a1dd813d965faa44c462ed49f14eb817cd53",
            releaseTag: "tts-models",
            compressedSize: 7_303_168,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-tr_TR-fahrettin-medium.tar.bz2"
        ),
        "vits-piper-tr_TR-fettah-medium": Entry(
            sha256: "59d33b4be1d1fda6352b0ff1493eece7995bae67cace3203789c06096312a362",
            releaseTag: "tts-models",
            compressedSize: 10_055_680,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-tr_TR-fettah-medium.tar.bz2"
        ),

        // MARK: - Ukrainian (uk)

        "vits-piper-uk_UA-ukrainian_tts-medium": Entry(
            sha256: "e8818a26503f77d12190ef8ff040a8ce1fdb07615ffffdc9d3171054044e9c13",
            releaseTag: "tts-models",
            compressedSize: 7_737_344,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-uk_UA-ukrainian_tts-medium.tar.bz2"
        ),

        // MARK: - Vietnamese (vi)

        "vits-piper-vi_VN-vais1000-medium": Entry(
            sha256: "3aa5fc085a2c59a0c37f1a7cbc373716fade5dcb052117f950c55704c4fec16b",
            releaseTag: "tts-models",
            compressedSize: 5_132_288,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-vi_VN-vais1000-medium.tar.bz2"
        ),

        // MARK: - Chinese (zh)

        "vits-piper-zh_CN-huayan-medium": Entry(
            sha256: "0944547dcfd933fb5ddade60c7ec68653ed69b14813e68eb33b95125670406c3",
            releaseTag: "tts-models",
            compressedSize: 11_800_576,
            sourceURL: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-huayan-medium.tar.bz2"
        ),
    ]
    // swiftlint:enable function_body_length

    // MARK: - Verification API

    /// Verifies integrity of a downloaded model archive.
    ///
    /// - Parameters:
    ///   - archiveURL: URL to the downloaded archive file
    ///   - modelId: The model identifier (e.g., "vits-piper-en_US-lessac-medium")
    /// - Returns: Verification result indicating success or specific failure
    static func verify(archiveAt archiveURL: URL, modelId: String) -> VerificationResult {
        // Check if model is in manifest
        guard let expected = knownModels[modelId] else {
            return .unknownModel
        }

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
