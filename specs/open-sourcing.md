# Release Preparation Plan: Speak the Web

## Overview
Preparing the iOS app "Speak the Web" for TestFlight/App Store release and open sourcing on GitHub.

**Current State:** ~70-75% release ready. Clean codebase, good architecture, privacy-focused.

**Codebase scan results:** No analytics, no tracking. Uses SherpaOnnx for local TTS inference (bundles sherpa-onnx, onnxruntime, and statically-linked dependencies). Only external connections: GitHub API for voice models, user-initiated URL fetches.

**Review Status:** ✅ APPROVED by external reviewer. Iteration 9 of 10.

---

## Part 1: Open Source Preparation

### 1.1 Add LICENSE file
- [x] Create `LICENSE` file in repo root with MIT license text
- [x] Include copyright line: `Copyright (c) 2026 Kareem Francis` (current year)
- README already states MIT, but standard practice is to have the file

### 1.2 Add THIRD_PARTY_NOTICES.md
- [ ] Create `THIRD_PARTY_NOTICES.md` with **full license texts** for bundled dependencies
- [ ] For Apache 2.0 components: include full license text
- [ ] **Verify NOTICE files:** Check each upstream repo for NOTICE files before release
- [ ] **Verify espeak-ng licensing:** README says GPL v3, but COPYING.APACHE exists - confirm with sherpa-onnx maintainers or legal counsel

**Bundled in binary (statically linked into sherpa-onnx.xcframework):**
| Library | License | Source | Notes |
|---------|---------|--------|-------|
| sherpa-onnx | Apache 2.0 | https://github.com/k2-fsa/sherpa-onnx | Verified |
| onnxruntime | MIT | https://github.com/microsoft/onnxruntime | Verified |
| espeak-ng | **UNVERIFIED** (GPL v3 or Apache 2.0?) | https://github.com/csukuangfj/espeak-ng (fork) | README says GPL v3, COPYING.APACHE exists — see Blocker 1 |
| piper-phonemize | MIT | https://github.com/rhasspy/piper-phonemize | Verified |
| kaldi-native-fbank | Apache 2.0 | https://github.com/csukuangfj/kaldi-native-fbank | Verified |
| kaldi-decoder | Apache 2.0 | https://github.com/k2-fsa/kaldi-decoder | Verified |
| kaldifst | Apache 2.0 | https://github.com/k2-fsa/kaldifst | Verified |
| openfst | Apache 2.0 | https://www.openfst.org | Verified |
| simple-sentencepiece | BSD-3 | https://github.com/pkufool/simple-sentencepiece | Verified |
| kissfft | BSD-3 | https://github.com/mborgerding/kissfft | Verified |
| eigen | MPL-2.0 (header-only) | https://eigen.tuxfamily.org | Some headers LGPL — see Blocker 2 |

**Linked via SwiftPM (in binary):**
| Library | License | Source | Notes |
|---------|---------|--------|-------|
| SWCompression | MIT | https://github.com/tsolomko/SWCompression | Verified |

**No other third-party assets:** No custom fonts, app icons are original

---

## LICENSE VERIFICATION TASKS

### Task 1: espeak-ng Licensing — Pending Verification
**Status:** UNVERIFIED

**Evidence found:**
- csukuangfj/espeak-ng fork README states: "GPL version 3 or later license"
- Same fork repo contains `COPYING.APACHE` file (contents unclear)
- Note: The fork's licensing is what applies, not upstream espeak-ng

**Verification tasks:**
1. [ ] Contact csukuangfj or sherpa-onnx maintainers to clarify which license applies to the fork
2. [ ] Check if COPYING.APACHE covers the fork's changes or is vestigial
3. [ ] Review sherpa-onnx build scripts for any license selection flags

### Task 2: eigen LGPL Modules — Pending Verification
**Status:** UNVERIFIED

**Context:** Eigen is header-only. LGPL obligations only apply if LGPL-licensed headers are actually included.

**Evidence found:**
- Eigen primary license: MPL-2.0
- Some headers under LGPL 2.1 (per COPYING.README)
- `EIGEN_MPL2_ONLY` flag NOT set in sherpa-onnx build

**Verification tasks:**
1. [ ] Identify which Eigen headers sherpa-onnx actually includes
2. [ ] Check if any LGPL-licensed headers are used
3. [ ] If LGPL headers used, document obligations

---

## APP STORE RELEASE BLOCKERS

**⚠️ CRITICAL GATING REQUIREMENT:**
NO release (App Store OR open source) may proceed until license verification is complete and documented. This is not optional — releasing with unverified GPL/LGPL dependencies risks:
- App Store removal (GPLv3 incompatibility)
- Legal liability for license violations
- Forced removal of features post-release

**Required artifacts before ANY release:**
- [ ] Reproducible SBOM with commit hashes, license file paths, and build flags
- [ ] Written license evidence (email confirmation, issue response, or documented file contents)
- [ ] Store artifacts in `docs/license-evidence/` directory

**License evidence file requirements:**
- **Naming convention:** `{library-name}-license-evidence-{YYYY-MM-DD}.md`
- **Required metadata in each file:**
  ```markdown
  # License Evidence: {Library Name}

  **Date captured:** YYYY-MM-DD
  **Source URL:** {URL where evidence was obtained}
  **Source commit/version:** {commit hash or version tag}
  **Evidence type:** {email | issue response | file contents | legal opinion}
  **SHA256 of attached evidence:** {hash if file attached}

  ## Summary
  {Brief statement of license determination}

  ## Raw Evidence
  {Full text of email, issue comment, or license file}
  ```
- **Attachments:** If evidence is a file (e.g., COPYING.APACHE), include copy in same directory
- **Verification:** Hash the evidence file to detect tampering

These must be resolved before App Store/TestFlight submission.

### Blocker A1: espeak-ng License Verification (CRITICAL)
**Depends on:** Task 1 above

**⚠️ IMPORTANT: GPL v3 is incompatible with App Store distribution.**

Apple's App Store terms (particularly DRM and usage restrictions) conflict with GPLv3 requirements. This is a well-documented legal incompatibility — "accept GPL obligations" is NOT a viable path for App Store release.

**If GPL v3 confirmed — available options:**
1. **Rebuild sherpa-onnx without espeak-ng** — Requires custom build, removes some voice options
2. **Use alternative phonemizer** — Check if piper-phonemize alone is sufficient
3. **Request dual-licensing** — Contact csukuangfj to clarify if Apache 2.0 applies
4. **Open source only** — Release on GitHub but not App Store

**⚠️ Feasibility testing required for options 1-2:**
Before committing to a GPL workaround, verify functionality:
- [ ] Test which voice models require espeak-ng vs piper-phonemize
- [ ] Document which languages/voices would be lost
- [ ] Define acceptance criteria: "App is acceptable if X% of voices work" or "English must work"
- [ ] Build test binary without espeak-ng and validate speech quality

**If Apache 2.0 confirmed via COPYING.APACHE:**
- Proceed with App Store release
- Include Apache 2.0 notice in THIRD_PARTY_NOTICES

**Decision required before proceeding with App Store submission.**

### Blocker A2: eigen LGPL Verification
**Depends on:** Task 2 above

**⚠️ IMPORTANT: LGPL + static linking requires concrete verification.**

The assumption that "header-only = attribution only" is incorrect. If ANY LGPL headers are compiled into the binary, LGPL obligations apply — header inclusion IS linkage for licensing purposes. **Assume LGPL obligations apply unless proven otherwise.**

**Required verification steps:**
1. [ ] Grep sherpa-onnx source for `#include` directives referencing Eigen
2. [ ] Cross-reference included headers against Eigen's COPYING.README to identify LGPL files
3. [ ] Check if sherpa-onnx can be built with `EIGEN_MPL2_ONLY=1` flag

**If LGPL headers are used:**
- **Option A (preferred):** Rebuild sherpa-onnx with `EIGEN_MPL2_ONLY` — excludes LGPL modules
- **Option B:** Provide LGPL notice + offer to provide object files for relinking (complex for App Store)

---

## OPEN SOURCE RELEASE BLOCKERS

These must be resolved before publishing repo on GitHub.

### Blocker O1: THIRD_PARTY_NOTICES Accuracy
**Depends on:** Tasks 1 & 2 above

**Note on open source vs App Store alignment:**
While open-sourcing the code itself has fewer distribution constraints (MIT is GPL-compatible), the same license verification is needed for both paths:
- Open source release: Must include accurate license texts for all dependencies
- App Store release: Must comply with all dependency licenses for binary distribution

**Important:** If GPL dependencies block App Store release, this creates a divergence:
- GitHub repo: Full source with all features
- App Store binary: May need to exclude GPL components

**Action:** Complete license verification first. This determines whether both releases can proceed in parallel or require separate strategies.

---

### 1.3 Add CONTRIBUTING.md
- [ ] Contribution guidelines
- [ ] Development setup instructions
- [ ] Code style requirements with **exact pinned versions** for reproducibility:
  - `swiftformat 0.55.3` — install via `brew install swiftformat` or pin version
  - `swiftlint 0.57.1` — install via `brew install swiftlint` or pin version
  - Config files: `.swiftformat`, `.swiftlint.yml`
  - **Installation commands to include:**
    ```bash
    brew install swiftformat
    brew install swiftlint
    # Or with version pinning:
    brew install swiftformat@0.55.3
    ```
- [ ] Instructions for local signing configuration (see 1.7)
- [ ] Git hooks setup: `git config core.hooksPath .githooks`
- [ ] PR process
- [ ] Model checksum verification process (see 2.1.1)

### 1.4 Fix pre-commit hook bug
- [ ] File: `.githooks/pre-commit`
- Search for `CareKeeper.xcodeproj` and replace with `SpeakTheWeb.xcodeproj` (2 occurrences)

### 1.5 Improve README for contributors
- [ ] Add badges (license, platform, Swift version)
- [ ] Clarify sherpa-onnx build process
- [ ] Add section for contributors pointing to CONTRIBUTING.md
- [ ] Document recommended tool versions

### 1.6 Add CHANGELOG.md
- [ ] Document version history starting with 1.0

### 1.6.1 Add SECURITY.md (Best Practice)
- [ ] Create `SECURITY.md` with:
  - Supported versions table
  - Security vulnerability reporting process (email or GitHub private vulnerability reporting)
  - Expected response timeline
  - Disclosure policy

### 1.6.2 Add CODE_OF_CONDUCT.md (Best Practice)
- [ ] Adopt Contributor Covenant or similar
- [ ] Required if expecting community contributions

### 1.6.3 Add Machine-Readable SBOM (Best Practice)
- [ ] Generate SPDX or CycloneDX format SBOM
- [ ] Include exact versions, source URLs, and commit hashes for all dependencies
- [ ] Store in `sbom/` directory or as `bom.json`
- **Rationale:** Compliance audits and supply chain security require machine-readable dependency lists

### 1.7 Make DEVELOPMENT_TEAM configurable
- [ ] Remove `DEVELOPMENT_TEAM: 8C7EB23ZZP` from `project.yml` (line 12)
- [ ] Run `xcodegen generate` to regenerate project without hardcoded team
- [ ] Document in CONTRIBUTING.md: "Select your development team in Xcode > Signing & Capabilities"

**Rationale:** Removing DEVELOPMENT_TEAM lets Xcode's "Automatically manage signing" work correctly. Contributors select their team in Xcode UI, which stores it in their local xcuserdata (already gitignored).

**Note:** The local.xcconfig approach was considered but XcodeGen doesn't support optional includes - a missing config file would fail the build.

### 1.8 Review sensitive data

**Secrets sweep checklist (completed):**
- [x] project.yml - no API keys/tokens (DEVELOPMENT_TEAM to be removed per 1.7)
- [x] .xcconfig files - none present
- [x] Info.plist - no secrets
- [x] .githooks - no secrets
- [x] Vendor/ - no credentials
- [x] .env files - none present

**Known configuration:**
- Bundle ID (`com.kareemf.SpeakTheWeb`) - acceptable for open source

---

## Part 2: App Store Release Preparation

### 2.1 Add Privacy Manifest (Required for iOS 17+)
- [ ] Create `SpeakTheWeb/PrivacyInfo.xcprivacy` file
- [ ] **Audit app and dependencies for required-reason APIs** (see verification task below)

**Privacy manifest inventory:**

| Category | Value |
|----------|-------|
| NSPrivacyTracking | false |
| NSPrivacyTrackingDomains | [] (empty) |
| NSPrivacyCollectedDataTypes | [] (empty - no data collection) |

**Required reason APIs (verified):**
- UserDefaults (C617.1 - app functionality: voice preferences, reading progress)
- File timestamp (DDA9.1 - cache management for articles/models)

**⚠️ API Audit Task (must complete before submission):**

**Reference:** Use Apple's current required-reason API list:
https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api

Must verify usage of:
- [ ] File timestamp APIs (`stat`, `fstat`, `getattrlist`) — Reason: DDA9.1 (cache management)
- [ ] System boot time APIs (`systemUptime`, `mach_absolute_time`) — Check SherpaOnnx
- [ ] Disk space APIs (`volumeAvailableCapacityKey`) — Check if used
- [ ] Active keyboard APIs — Not expected, verify
- [ ] User defaults APIs — Reason: C617.1 (app functionality)

**Verification steps (comprehensive):**
```bash
# 1. Build app for device (Release config) and archive

# 2. Multiple symbol analysis methods (nm may miss Swift/stripped symbols):
# App binary
nm -u SpeakTheWeb.app/SpeakTheWeb | grep -E "stat|fstat|getattrlist|systemUptime|mach_absolute_time|volumeAvailable"
strings SpeakTheWeb.app/SpeakTheWeb | grep -E "stat|fstat|getattrlist|mach_absolute_time"
otool -Iv SpeakTheWeb.app/SpeakTheWeb | grep -E "stat|mach_absolute_time"

# 3. Check each xcframework slice
for fw in Vendor/*.xcframework/ios-arm64/*/*.framework/*; do
  echo "=== $fw ==="
  nm -u "$fw" 2>/dev/null | grep -E "stat|mach_absolute_time" || true
  strings "$fw" 2>/dev/null | grep -E "NSFileSystemFreeSize|volumeAvailable" || true
done

# 4. Source code grep for API usage
grep -r "FileManager.*availableCapacity\|systemUptime\|mach_absolute_time\|stat(" SpeakTheWeb/
```

**Privacy manifest identifiers (use exact Apple keys):**
- File timestamp: `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `DDA9.1`
- User defaults: `NSPrivacyAccessedAPICategoryUserDefaults` with reason `C617.1`

**Additional verification using Xcode:**
- [ ] After archive, use Xcode's "Generate Privacy Report" (Product > Generate Privacy Access Report)
- [ ] This produces comprehensive report of all required-reason APIs in app + dependencies
- [ ] Cross-reference with privacy manifest entries

**Note:** Apple's list changes periodically. Check the reference URL before each submission.

**Third-party SDKs — EXPLICIT AUDIT REQUIRED:**
- SherpaOnnx - local inference only, no network calls, no tracking
- onnxruntime - inference engine, may use timing/performance APIs

**⚠️ Bundled framework audit (must complete before submission):**
The app code may not use required-reason APIs directly, but bundled frameworks might.
- [ ] Audit `sherpa_onnx.xcframework` binary for required-reason API calls
- [ ] Audit `onnxruntime` for `mach_absolute_time` (common in ML frameworks for timing)
- [ ] Check for `stat`/`fstat` calls in xcframeworks (file handling)
- [ ] Check for disk space APIs (`volumeAvailableCapacity`, `NSFileSystemFreeSize`)
- [ ] Check for system boot time APIs (`systemUptime`, `ProcessInfo.processInfo.systemUptime`)
- [ ] If frameworks use APIs, add corresponding entries to Privacy Manifest with appropriate reasons

**Acceptance criteria for found APIs:**
- **If required-reason API found:** Add to Privacy Manifest with most appropriate reason code from Apple's list
- **If no suitable reason code exists:** Document the API usage and contact Apple DTS for guidance before submission
- **If API usage seems unnecessary:** Consider filing issue with upstream (sherpa-onnx) requesting removal or conditional compilation
- **Blocking condition:** If an API has NO valid reason code and cannot be removed, this blocks App Store submission

**Network access:**
- GitHub API (`api.github.com/repos/k2-fsa/sherpa-onnx`) - voice model downloads
- User-provided URLs - article fetching

### 2.1.1 Voice Model Integrity Verification (NEW)
**⚠️ Supply chain security:** Models downloaded from GitHub could be tampered with.

**Current state:** Models downloaded from GitHub releases without verification.

**Required mitigations:**
1. **Checksum + version verification:**
   - [ ] Store expected SHA256 checksums in app bundle for known models
   - [ ] Store expected version AND file size alongside checksum
   - [ ] Verify all three (checksum, version, size) after download
   - [ ] Reject models that fail any verification

2. **Rollback/replay protection:**
   - [ ] Maintain monotonic version expectation: never accept older version than currently installed
   - [ ] If server offers older version, reject unless user explicitly approves downgrade

3. **Implementation:**
   - [ ] Store verification data in compiled code (not plist) — prevents tampering on jailbroken devices
   - [ ] Create `struct ModelManifest { sha256: String, version: String, expectedSize: Int }`
   - [ ] Implement `verifyModelIntegrity(at path: URL, expected: ModelManifest) -> Bool`
   - [ ] Clear corrupted/tampered downloads immediately

4. **Update strategy:**
   - When new models are released, app update includes new manifest
   - Unknown models (not in manifest) are rejected with clear error
   - **Use pinned release asset URLs, not "latest" tags** — prevents accidental use of yanked/modified releases

   **Checksum source and maintenance:**
   - [ ] Source checksums from official sherpa-onnx releases (download, verify manually, compute SHA256)
   - [ ] Store checksums in `SpeakTheWeb/Models/ModelManifest.swift` (compiled into binary)
   - [ ] **Release checklist step:** Before each app release, verify all model checksums are current
   - [ ] Document checksum verification process in CONTRIBUTING.md
   - [ ] If upstream changes a model file, treat as new version (update app manifest)

5. **Fallback for unavailable models:**
   - If GitHub release is yanked or asset removed, show graceful error: "This voice model is no longer available. Please update the app for the latest models."
   - Do NOT fall back to unverified sources
   - App remains functional with other verified models

6. **Download robustness (availability protection):**
   - [ ] Implement retry with exponential backoff: 3 attempts, delays of 1s, 2s, 4s
   - [ ] Support resumable downloads using HTTP Range headers
   - [ ] Verify partial downloads with chunk hashing (if GitHub supports range requests)
   - [ ] If partial download fails verification, restart from beginning
   - [ ] Show progress UI with cancel option
   - [ ] Handle network changes gracefully (Wi-Fi → cellular)
   - [ ] Validate TLS for GitHub CDN (use system defaults, no custom trust)

**Trade-off:** This prevents automatic discovery of new models. Acceptable for security.

### 2.2 App Transport Security

**Current setting:** `NSAllowsArbitraryLoads: true` in Info.plist

**⚠️ RISK: Global ATS exception is a common App Review rejection reason.**

**Decision: Keep `NSAllowsArbitraryLoads: true` with justification and mitigations.**

Apple's documentation acknowledges this is acceptable for apps that fetch arbitrary user-provided URLs (like browsers and RSS readers). The key is providing clear justification.

**Why alternatives don't work:**
- `NSAllowsArbitraryLoadsInWebContent` — Only applies to WKWebView, NOT URLSession ❌
- `NSExceptionDomains` — Cannot predict user URLs ❌
- Require HTTPS only — Breaks legitimate HTTP sites, poor UX ❌

**Required implementation before submission:**
- [ ] Implement HTTPS-first: Upgrade `http://` to `https://` automatically
- [ ] **HTTPS-first policy (DECISION MADE):** ALWAYS attempt HTTPS first, even when user explicitly enters `http://`. This maximizes security without requiring user to know which sites support HTTPS.
  - User enters `http://example.com` → app tries `https://example.com` first
  - If HTTPS succeeds → use secure connection (no prompt needed)
  - If HTTPS fails → then prompt for HTTP confirmation
- [ ] **Explicit per-host HTTP confirmation:** If HTTPS fails, prompt user with host-specific confirmation: "example.com doesn't support secure connections. Allow HTTP for this site?"
  - Confirmation is per-host, not global
  - **Session-only by default:** Confirmation does NOT persist across app restarts
  - No option to "remember" — prevents silent downgrade risk
  - User must re-confirm for different hosts
  - Also required for HTTPS→HTTP redirect downgrades
  - **Host identity definition:** Use the full hostname (not eTLD+1) for matching. For IP literals, use the canonical IP string. Confirmation for `www.example.com` does NOT apply to `example.com` or `api.example.com`.
  - Consistent matching across redirects: if redirect changes host, re-confirm for new host
- [ ] Add visual indicator for HTTP connections after user confirms
- [ ] Add URL scheme/host validation (see 2.2.1 below)

**URLSession configuration for arbitrary URLs:**
- [ ] Use `URLSessionConfiguration.ephemeral` — no persistent cache/cookies
- [ ] Set `httpCookieStorage = nil` — prevents cookie leakage
- [ ] Set `urlCredentialStorage = nil` — prevents credential storage
- [ ] Set `urlCache = nil` — no caching at all (ephemeral still uses in-memory cache by default)
- [ ] Set `requestCachePolicy = .reloadIgnoringLocalCacheData` — defense in depth
- [ ] Document `allowsConstrainedNetworkAccess` / `allowsExpensiveNetworkAccess` behavior

**TLS/Certificate verification constraints (CRITICAL):**
- [ ] **Do NOT implement custom `URLSessionDelegate` trust evaluation** — use system defaults
- [ ] If `URLSessionDelegate` is needed for other purposes, do NOT override `urlSession(_:didReceive:completionHandler:)` for server trust
- [ ] If delegate trust method must be implemented, ONLY call `completionHandler(.performDefaultHandling, nil)` — NEVER `.useCredential` with custom trust
- [ ] **Explicitly deny any certificate pinning bypass or trust exceptions**
- [ ] Do NOT set `tlsMinimumSupportedProtocolVersion` below `.TLSv12`
- [ ] Log TLS errors for debugging but do NOT allow user to bypass

**ATS justification supplementary documentation:**
Why scoped exceptions don't work:
- `NSAllowsArbitraryLoadsInWebContent` — Only applies to WKWebView; app uses URLSession for fetching ❌
- `NSAllowsArbitraryLoadsInMedia` — Not applicable; app fetches text, not media ❌
- `NSExceptionDomains` — Cannot enumerate all possible user-provided domains ❌

Mitigations demonstrated in code and UI:
1. HTTPS-first with explicit HTTP opt-in confirmation
2. Comprehensive URL validation blocking dangerous schemes/hosts
3. Visual indicator for insecure connections
4. No data transmitted to fetched sites (read-only fetch)

**App Review justification (for App Store Connect notes):**
> This app is a text-to-speech reader for web articles. Users provide URLs directly (via paste or Share Extension). The app must support HTTP because:
> 1. Many older articles and archives are HTTP-only (legacy content, Internet Archive, etc.)
> 2. The app does not curate or suggest URLs — users control all content
> 3. No user data is transmitted; content flows one-way (fetch → local TTS)
>
> Security mitigations implemented:
> - HTTPS-first: All URLs upgraded to HTTPS; HTTP only allowed after explicit per-host user confirmation
> - Comprehensive URL validation blocks dangerous schemes, private IPs, and localhost
> - Redirect validation: Security checks re-applied after each redirect
> - Visual indicator displayed for insecure connections
>
> Content handling:
> - The app does NOT use WKWebView to render fetched content
> - HTML is parsed with a non-executing parser (no JavaScript evaluation)
> - The app does NOT load remote resources (images, stylesheets, iframes, etc.)
> - The app does NOT modify device network settings
> - Content is text-only extraction for TTS playback

### 2.2.2 HTML Parsing Security
- [ ] **Use non-executing HTML parser** (e.g., SwiftSoup, libxml2) — NOT WKWebView
- [ ] Extract text content only; do not evaluate scripts or load remote resources
- [ ] Sanitize extracted text: strip any remaining HTML entities, null bytes, or control characters
- [ ] Document parser choice in code comments for security audit

**⚠️ No subresource fetching (explicit policy):**
- [ ] **Do NOT fetch any URLs found in HTML** — no images, stylesheets, scripts, iframes, fonts, etc.
- [ ] **Do NOT resolve relative URLs** in parsed content
- [ ] **Do NOT follow `<link rel="canonical">` or `<meta http-equiv="refresh">`**
- [ ] Parser extracts text content ONLY — all `src`, `href`, `srcset` attributes are ignored
- [ ] Verification: Code review to confirm no secondary URL fetches from parsed HTML

### 2.2.1 URL Scheme & Host Security (NEW)
**⚠️ Security requirement:** Validate URL schemes AND hosts before fetching.

**Allowed schemes:**
- `https://` — Primary, preferred
- `http://` — Allowed only with explicit user confirmation (not just a badge)

**Blocked schemes (reject with user-friendly error):**
- `file://`, `ftp://`, `data:`, `javascript:`, `mailto:`, `about:`, `blob:` — Not supported

**Blocked hosts (prevent SSRF/local access):**

**IPv4 reserved ranges (block all):**
- `0.0.0.0/8` (current network)
- `10.0.0.0/8` (private)
- `100.64.0.0/10` (carrier-grade NAT)
- `127.0.0.0/8` (loopback)
- `169.254.0.0/16` (link-local)
- `172.16.0.0/12` (private)
- `192.0.0.0/24` (IETF protocol assignments)
- `192.168.0.0/16` (private)
- `198.18.0.0/15` (benchmarking)
- `224.0.0.0/4` (multicast)
- `240.0.0.0/4` (reserved/future)

**IPv6 reserved/special-purpose ranges (block all per IANA):**
- `::/128` (unspecified)
- `::1/128` (loopback)
- `::/96` (IPv4-compatible, deprecated)
- `::ffff:0:0/96` (IPv4-mapped — also check mapped IPv4 against IPv4 rules)
- `100::/64` (discard-only)
- `2001:2::/48` (benchmarking)
- `2001:10::/28` (ORCHID)
- `2001:db8::/32` (documentation)
- `fe80::/10` (link-local)
- `fc00::/7` (unique local)
- `ff00::/8` (multicast)

**Tunnel prefixes (special handling — see NAT64 section below):**
- `64:ff9b::/96` (NAT64) — **Do NOT block outright; extract and validate embedded IPv4**
- `2001::/32` (Teredo) — **Extract and validate embedded IPv4**
- `2002::/16` (6to4) — **Extract and validate embedded IPv4**

**NAT64/DNS64 handling (revised for App Review compliance):**
Apple requires apps to work on IPv6-only networks. Blocking `64:ff9b::/96` entirely would fail this requirement.

**Revised approach:**
- [ ] Do NOT block `64:ff9b::/96` outright
- [ ] Instead, extract the embedded IPv4 address from NAT64 addresses (last 32 bits)
- [ ] Validate the extracted IPv4 against blocked IPv4 ranges
- [ ] Example: `64:ff9b::127.0.0.1` → extract `127.0.0.1` → blocked
- [ ] Example: `64:ff9b::93.184.216.34` → extract `93.184.216.34` → allowed (public IP)
- [ ] Same logic for 6to4 (`2002::/16`): extract embedded IPv4 from first 48 bits

This preserves IPv6-only network compatibility while still blocking tunneled access to private IPv4 ranges.

**Hostname patterns:**
- `localhost`, `localhost.`, `*.localhost`
- `*.local` (mDNS/Bonjour)

**IP literal handling:**
- [ ] If URL host is an IP literal (IPv4, IPv6, IPv4-mapped IPv6), validate directly — skip DNS resolution
- [ ] Normalize IPv6 representations before validation

**DNS rebinding protection (defense in depth):**

**Policy decision and rationale:**
- **Goal:** Prevent SSRF attacks while not breaking legitimate sites
- **Trade-off:** Strict blocking = some CDNs may break; permissive = potential bypass
- **Decision:** Use "at least one public IP" policy with post-connect verification as safety net
- **Rationale:** Post-connect validation catches actual connection to blocked IP even if DNS returned mixed results

Pre-fetch validation:
- [ ] Resolve hostname before fetching using `getaddrinfo`
- [ ] Check ALL A/AAAA records against blocked IP ranges
- [ ] **Mixed-record policy:** Reject if ALL resolved IPs are in blocked ranges. If at least one public IP exists, allow (CDNs may have some private IPs for internal routing).
- [ ] If ALL records are blocked, reject with error
- [ ] **Transient DNS failure handling:** On DNS failure, retry up to 2 times with exponential backoff (1s, 2s). If all retries fail, reject with user-friendly error: "Unable to reach this website. Please check the URL and try again."
- [ ] If resolution fails after retries, reject with error (fail-closed)

Post-connect validation (iOS URLSession can re-resolve):
- [ ] Use `URLSessionTaskDelegate` + `URLSessionTaskMetrics` to get actual resolved IP
- [ ] Check `transactionMetrics.remoteAddress` after connection
- [ ] Abort and reject if actual connected IP is in blocked range
- [ ] **Fail-closed behavior:** If `remoteAddress` is nil, redacted, or missing, reject the request. Do not allow connection without IP verification.
- [ ] **VPN/Proxy handling (DECISION MADE):** Block fetch with user-friendly error:
  > "Unable to verify connection security. If you're using a VPN or proxy, try disabling it temporarily to load this article."
- [ ] Log failures for debugging (no PII)

**Redirect validation (CRITICAL):**
- [ ] Re-validate URL after EACH HTTP redirect (30x responses)
- [ ] Apply full scheme/host/IP validation to redirect target
- [ ] **Handle relative and scheme-relative `Location` headers:** Resolve against current request URL before validation
- [ ] **Block HTTPS→HTTP downgrades** unless user explicitly confirms for target host
- [ ] Confirm on effective host (after DNS resolution) AND on every redirect target
- [ ] Follow redirect chain with validation at each hop
- [ ] Limit redirect depth (max 10) to prevent loops

**Additional URL edge cases:**
- [ ] Reject URLs with embedded credentials (`user:pass@host`)
- [ ] **IDN/punycode policy (revised):**
  - Allow ASCII-only hostnames (standard domains)
  - Allow punycode hostnames (`xn--...`) — these are ASCII-encoded IDNs, safe to process
  - Reject raw Unicode/non-ASCII hostnames — display error: "Please use the ASCII version of this domain"
  - After allowing punycode, validate the ASCII form against blocked hostname patterns
  - Rationale: Punycode is common for legitimate international domains; rejecting all IDN is overly restrictive for a reader app
- [ ] Handle trailing dots in hostnames (strip before validation)
- [ ] Handle mixed-case schemes (normalize to lowercase)
- [ ] **Reject non-standard IPv4 forms:**
  - Parsing location: Validate host string BEFORE passing to URLSession
  - Use `inet_pton(AF_INET, host, &addr)` which rejects octal/hex/partial forms
  - If host looks like IPv4 but `inet_pton` fails, reject with error
  - Accept only strict dotted-decimal (four octets, decimal digits only)
  - For IPv6 literals, use `inet_pton(AF_INET6, host, &addr6)`
- [ ] Handle Share Extension URLs (may include fragments, non-HTTP schemes)
- [ ] **Share Extension uses same URLValidator** — validation logic is shared, not duplicated

**Implementation:**
- [ ] Create `URLValidator` class with comprehensive validation
- [ ] Return clear, localized error messages for each rejection reason
- [ ] Log validation failures for debugging (no PII)

**Local network toggle (REMOVED):**
Reviewer concern: LAN access toggle increases App Review risk. Decision: Do NOT implement LAN toggle. Block all private/local addresses unconditionally.

### 2.3 Update Privacy Policy
- [ ] Update `docs/privacy.html` to specify voice model source:
  - Models fetched from [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) on GitHub
- [ ] Add disclosure: GitHub's standard logs may record basic request metadata
- [ ] Add disclosure for user-provided URLs:
  > When you enter a URL, the app fetches content directly from that website. The website may log your IP address and device information according to its own privacy practices.

### 2.3.1 Terms of Service / Content Disclaimer
- [ ] Add Terms of Service (`docs/terms.html`) or disclaimer section in privacy policy

**Required disclosures for user-provided URL fetching:**
> **Content Responsibility:** You are responsible for ensuring you have the right to access content from URLs you provide. The app fetches content directly from websites you specify — we do not curate, filter, or review this content.
>
> **Third-Party Terms:** Websites you access may have their own terms of service, paywalls, or access restrictions. By using this app, you agree to comply with the terms of any website you access.
>
> **No Endorsement:** The app does not endorse, verify, or take responsibility for content from user-provided URLs.

### 2.3.2 User-Generated Content & Age Rating
**⚠️ App Review consideration:** Arbitrary URL fetching means the app can display any web content.

**Explicit policy statement (for App Review and legal clarity):**
> This app does NOT curate, index, recommend, or share content. The app has NO content discovery features, NO bookmarking with sync, NO history sharing, and NO social features. Users provide URLs manually via paste or Share Extension — the app simply fetches and reads aloud what the user explicitly requests.

This distinction is important: App Review's UGC moderation requirements (reporting, blocking objectionable content) apply to apps that **curate or index** content. A pure reader/fetcher app that only processes user-provided URLs does not trigger these requirements.

**Mitigations for App Review:**
1. **Age Rating:** Set to 12+ or 17+ with "Unrestricted Web Access" indicated
2. **App Review Notes:** Explain that:
   - Users supply all URLs; app has no content discovery features
   - No content curation, recommendation, or sharing
   - App is a "reader" not a "browser" — renders text only, no scripts/images
   - No UGC moderation required per App Store guidelines (no indexing/curation)
3. **In-app disclaimer:** First-launch notice that user is responsible for content they access
- [ ] Add first-launch disclaimer/onboarding screen (optional but recommended)

### 2.3.3 UX Placement Specifications
**HTTP indicator and disclaimer placement (required for ATS justification):**

**HTTP connection indicator:**
- [ ] Location: In the article header/title area (visible during playback)
- [ ] Design: Red/orange "Insecure" badge or unlocked padlock icon
- [ ] Behavior: Tap reveals explanation: "This article was loaded over an insecure HTTP connection"
- [ ] Persistence: Visible as long as article is displayed

**First-launch disclaimer:**
- [ ] Trigger: Show once on first app launch (store flag in UserDefaults)
- [ ] Design: Full-screen modal or dedicated onboarding screen
- [ ] Content: "You control what content this app reads. You are responsible for the URLs you provide."
- [ ] Dismissal: Require explicit "I understand" button tap (not swipe-to-dismiss)
- [ ] Screenshot: Include in App Review submission to demonstrate mitigation

### 2.4 Version numbers
- Current: `1.0` (build 1) - looks good for initial release
- Ensure these are correct in `project.yml`

### 2.5 App Store Connect Setup (Manual)
- Create app listing
- Upload screenshots
- Write description and keywords
- Set privacy policy URL (docs/privacy.html on GitHub Pages)
- Set support URL
- Choose category: Utilities (already set in plist)
- **Age rating: 17+** (select "Unrestricted Web Access" in questionnaire)
  - Decision: Use 17+ to avoid App Review rejection. Apps with arbitrary URL access typically require 17+.
  - This is conservative but safer than risking rejection and resubmission.

### 2.5.1 App Review Artifacts (Required for ATS Justification)
**⚠️ CRITICAL: Prepare these BEFORE submission to avoid rejection:**

**Screenshots demonstrating security mitigations:**
- [ ] Screenshot: First-launch disclaimer modal
- [ ] Screenshot: HTTP confirmation dialog ("Allow HTTP for example.com?")
- [ ] Screenshot: HTTP indicator badge visible on insecure article
- [ ] Screenshot: Error message for blocked URL (localhost, private IP, etc.)
- [ ] Screenshot: Error for NAT64-tunneled private IP (if distinct from above, e.g., different error message)

**App Review Notes (copy to App Store Connect):**
Save the justification text from section 2.2 in a separate file for easy copy-paste during submission.
- [ ] Create `docs/app-review-notes.txt` with ATS justification
- [ ] Include clear statement: "User-provided URLs only, no content curation"
- [ ] Reference specific security mitigations implemented

**Demo account / test instructions:**
- [ ] No account needed (state this explicitly in review notes)
- [ ] Provide sample HTTP URL for testing HTTP confirmation flow
- [ ] Provide sample article URL that works well for TTS demo

**Privacy Questionnaire (App Privacy "Nutrition Label"):**
- [ ] Data Types Collected: **None** (select "No" for all categories)
- [ ] Data Used to Track You: **No**
- [ ] Data Linked to You: **No**
- Note: Even when collecting no data, you must complete this questionnaire

### 2.6 Build and sign for TestFlight
- Ensure provisioning profiles are set up
- Archive and upload to App Store Connect

---

## Part 3: Code/Config Changes Needed

| Task | File(s) | Priority | Status |
|------|---------|----------|--------|
| Create LICENSE file | `/LICENSE` | High | [ ] |
| Create THIRD_PARTY_NOTICES | `/THIRD_PARTY_NOTICES.md` | High | **BLOCKED** (see Release Blockers) |
| Create CONTRIBUTING.md | `/CONTRIBUTING.md` | High | [ ] |
| Fix pre-commit hook | `.githooks/pre-commit` | High | [ ] |
| Remove DEVELOPMENT_TEAM from project.yml | `project.yml` | High | [ ] |
| Add Privacy Manifest | `SpeakTheWeb/PrivacyInfo.xcprivacy` | High | [ ] |
| Audit required-reason APIs | App + dependencies | High | [ ] |
| Update privacy policy | `docs/privacy.html` | High | [ ] |
| Add Terms of Service / disclaimer | `docs/terms.html` | High | [ ] |
| **Create URLValidator with comprehensive validation** | URL handling code | **High** | [ ] |
| **Implement HTTPS-first with per-host session-only confirmation** | URL handling code | **High** | [ ] |
| **Add DNS rebinding protection (pre-fetch + post-connect)** | URL handling code | **High** | [ ] |
| **Add redirect validation with scheme downgrade blocking** | URL handling code | **High** | [ ] |
| **Handle IP literals (IPv4, IPv6, mapped, non-standard forms)** | URL handling code | **High** | [ ] |
| **Configure ephemeral URLSession (no cookies/credentials)** | Networking code | **High** | [ ] |
| **Share URLValidator with Share Extension** | Extension code | **High** | [ ] |
| **Add model integrity verification (checksum+version+size)** | Model download code | **High** | [ ] |
| Add HTTP connection indicator | Article view UI | Medium | [ ] |
| Add first-launch disclaimer | Onboarding UI | Medium | [ ] |
| Add CHANGELOG | `/CHANGELOG.md` | Medium | [ ] |
| Update README | `/README.md` | Medium | [ ] |
| Add SECURITY.md | `/SECURITY.md` | Medium | [ ] |
| Add CODE_OF_CONDUCT.md | `/CODE_OF_CONDUCT.md` | Low | [ ] |
| Generate SBOM | `sbom/bom.json` | Medium | [ ] |
| Create app-review-notes.txt | `docs/app-review-notes.txt` | High | [ ] |
| Capture App Review screenshots | Screenshots folder | High | [ ] |

---

## Part 4: Verification

### 4.1 Development Verification
- [ ] Run `git config core.hooksPath .githooks` and make test commit to verify pre-commit hook
- [ ] Run `xcodegen generate` to regenerate project
- [ ] Build and run on simulator
- [ ] Build and run on physical device
- [ ] Test Share Extension from Safari
- [ ] Test both TTS engines (System and Piper)
- [ ] Test background audio playback
- [ ] Verify Privacy Manifest appears in Xcode project settings
- [ ] Check docs/privacy.html renders correctly

### 4.2 Security Verification
- [ ] Test URL validation: verify localhost/private IP rejection
- [ ] Test HTTP confirmation flow: verify dialog appears, session-only behavior
- [ ] Test redirect validation: verify HTTPS→HTTP downgrade prompts
- [ ] Test embedded credential rejection: `user:pass@example.com`

### 4.3 IPv6-Only Network Testing (Required for App Review)
**⚠️ Apple tests apps on IPv6-only networks. NAT64 handling must work.**
- [ ] Set up Mac as NAT64 gateway (System Settings > Sharing > Internet Sharing > "Create NAT64 Network")
- [ ] Connect test device to NAT64 network
- [ ] Verify app can fetch articles via NAT64
- [ ] Verify blocked IPv4 ranges are still blocked via NAT64 (test `64:ff9b::127.0.0.1` equivalent)

### 4.4 App Store Submission
- [ ] Archive for TestFlight upload
- [ ] Capture all required screenshots (see 2.5.1)
- [ ] Copy app-review-notes.txt to App Store Connect
