# VoiceFlow Release Guide

VoiceFlow can be distributed either as an unsigned DMG for development/private sharing or as a Developer ID-signed, notarized DMG for public production distribution. The local and GitHub Actions workflows use the same `scripts/release.sh` pipeline so that build, packaging, verification, and checksum behavior is not duplicated.

> The release pipeline never stores Apple credentials, certificates, private keys, or keychain passwords in the repository. Do not paste secret values into shell output or issue comments.

## Production configuration

The current Xcode project is an application target named `voiceflow` in `voiceflow.xcodeproj`. Its production configuration is the `Release` configuration, with the following metadata:

| Setting | Value/source |
|---|---|
| Product name | `voiceflow` target; display name `VoiceFlow` in `Info.plist` |
| Bundle identifier | `dha-aa.voiceflow` |
| Deployment target | macOS 14.0 |
| Marketing version | `MARKETING_VERSION`, supplied by the release version argument |
| Build number | `CURRENT_PROJECT_VERSION`, supplied by `BUILD_NUMBER` or the GitHub run number |
| Application icon | `AppIcon` asset catalog |
| Signing | `Developer ID Application`, supplied by `DEVELOPER_ID_APPLICATION` |
| Runtime | Hardened Runtime enabled for Release |
| Sandbox | Disabled because global Fn monitoring and cross-process Accessibility injection require it |
| Microphone | `com.apple.security.device.audio-input` entitlement |

The release script validates these settings before doing the expensive build or submitting anything to Apple.

## Local release

The script supports two local release paths. The default path requires a Mac with the full Xcode installation selected, a Developer ID Application certificate, and Apple notarization credentials. The unsigned path requires only the full Xcode installation. The script prefers `DEVELOPER_DIR` and otherwise uses `/Applications/Xcode.app/Contents/Developer` when present.

For App Store Connect API-key authentication, configure the following environment variables in the invoking shell or a secure secret manager:

| Variable | Meaning |
|---|---|
| `DEVELOPER_ID_APPLICATION` | Full Developer ID Application certificate identity, or the identity prefix `Developer ID Application` |
| `APPLE_API_KEY_PATH` | Path to a local App Store Connect private `.p8` key; never commit this file |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_ISSUER_ID` | App Store Connect issuer ID |
| `BUILD_NUMBER` | Optional numeric build number; defaults to `1` locally |
| `DEVELOPER_DIR` | Optional Xcode developer directory |

Alternatively, use a previously stored `notarytool` keychain profile by setting `NOTARY_KEYCHAIN_PROFILE` instead of the three `APPLE_*` API-key variables. Apple documents both `notarytool` submission and keychain-profile authentication in its [custom notarization workflow guide][1].

Run the inexpensive environment and project check first:

```bash
./scripts/release.sh --check
```

The check mode does not build, submit to Apple, staple, or create an artifact. When it passes, create the release with one version argument:

```bash
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
APPLE_API_KEY_PATH="$HOME/.private/AuthKey_KEYID.p8" \
APPLE_API_KEY_ID='KEYID' \
APPLE_ISSUER_ID='ISSUER-UUID' \
./scripts/release.sh 1.0.0
```

The final files are written to `dist/`:

```text
dist/VoiceFlow-1.0.0.dmg
dist/SHA256SUMS.txt
```

If Apple credentials are unavailable, create an unsigned DMG locally with:

```bash
./scripts/release.sh --unsigned 1.0.0
```

The unsigned path builds the Release app, creates a normal mountable DMG containing `VoiceFlow.app` and an `Applications` shortcut, verifies the DMG structure, and computes a SHA-256 checksum. It deliberately skips signing, notarization, stapling, and Gatekeeper assessment. The default path additionally verifies the app signature, submits the DMG with `xcrun notarytool --wait`, staples the ticket, validates the stapled DMG, and runs Gatekeeper assessment before computing the checksum.

## GitHub release

The workflow in `.github/workflows/release.yml` supports both pushed tags and manual runs. Pushed tags matching `v*` automatically build and publish an **unsigned DMG**, which does not require Apple secrets:

```bash
git tag v1.0.0
git push origin v1.0.0
```

A successful tag run creates a GitHub Release containing `VoiceFlow-1.0.0.dmg` and `SHA256SUMS.txt`. The release title and generated notes identify the artifact as unsigned. The workflow uses a pinned `macos-15` runner and selects Xcode `16.4`, which is compatible with the project’s macOS 14 deployment target. GitHub-hosted runner images are maintained separately from the workflow, so the workflow selects an explicit Xcode version rather than depending on `macos-latest` defaults. The setup action’s documented version-selection behavior is described in [Setup Xcode version][2], and GitHub documents hosted-runner image maintenance in [About GitHub-hosted runners][3].

A tag-triggered unsigned run checks out the tag, validates the version, runs the XCTest suite, calls `./scripts/release.sh --unsigned VERSION`, uploads the unsigned DMG and checksum, and creates the GitHub Release. It does not attempt signing, notarization, stapling, or Gatekeeper verification.

### Manual workflow execution

Open **Actions → Release VoiceFlow → Run workflow**, choose the branch containing the workflow, and select one of these modes:

| Mode | Apple secrets required | Result |
|---|---:|---|
| `unsigned` | No | Builds, checks, and publishes an unsigned DMG to a GitHub Release |
| `checks` | No | Runs tests and builds an unsigned app without publishing a Release |
| `production-release` | Yes | Builds, signs, notarizes, staples, verifies, and publishes a production DMG |

For `unsigned`, optionally enter a version such as `1.0.0`. If omitted, the workflow uses `0.0.0-manual.<run-number>`. The workflow creates a unique release tag such as `unsigned-v1.0.0-123` so repeated manual runs do not overwrite a normal version tag. The `production-release` mode intentionally fails early unless the Apple secrets below are configured.

### Required GitHub Actions secrets

The secrets are required only for `production-release` mode. Pushed version tags use unsigned mode and do not require any of them. The credential-free `checks` mode also does not require any secrets.

Configure these repository or organization secrets before running a production release:

| Secret | Required for production | Purpose |
|---|---:|---|
| `DEVELOPER_ID_APPLICATION` | Yes | Developer ID Application identity string |
| `DEVELOPER_CERTIFICATE_P12_BASE64` | Yes | Base64-encoded exported Developer ID certificate and private key |
| `DEVELOPER_CERTIFICATE_PASSWORD` | Yes | Password protecting the `.p12` export |
| `KEYCHAIN_PASSWORD` | Yes | One-time password for the temporary CI keychain |
| `APPLE_API_KEY_BASE64` | Yes | Base64-encoded App Store Connect private `.p8` key |
| `APPLE_API_KEY_ID` | Yes | App Store Connect API key ID |
| `APPLE_ISSUER_ID` | Yes | App Store Connect issuer ID |

`GITHUB_TOKEN` is supplied by GitHub Actions through `github.token`; the workflow requests `contents: write` so it can create the release. The workflow does not print secret values. The manual `checks` mode does not create a GitHub Release, while the manual `unsigned` mode creates one using the automatic `GITHUB_TOKEN`.

To create the certificate secret, export the Developer ID Application certificate and private key from Keychain Access as a password-protected `.p12`, then base64-encode it locally. To create the API-key secret, base64-encode the downloaded App Store Connect `.p8` file. Delete any temporary encoded files after adding the secrets. Never commit `.p12`, `.cer`, `.pem`, `.p8`, provisioning profiles, or Apple credentials.

## Release verification

The signed production pipeline is intentionally fail-fast and does not create a GitHub Release when signing, notarization, stapling, DMG verification, Gatekeeper assessment, or checksum generation fails. The unsigned pipeline has a separate contract: it verifies that the DMG mounts and contains the expected app and Applications shortcut, then publishes the clearly labeled unsigned artifact without claiming Apple trust.

| Stage | Verification |
|---|---|
| Project | Scheme, bundle identifier, AppIcon, Hardened Runtime, and non-sandbox configuration |
| Build | Release `.app` exists with requested version and build number |
| Signature | Required only for signed production mode: `codesign --verify --deep --strict --verbose=2` plus signature metadata inspection |
| DMG | `hdiutil verify`, read-only mount, app presence, and Applications shortcut; signed mode also verifies the nested app signature |
| Notarization | Required only for signed production mode: `xcrun notarytool submit ... --wait` must return success |
| Stapling | Required only for signed production mode: `xcrun stapler staple` followed by `xcrun stapler validate` |
| Gatekeeper | Required only for signed production mode: `spctl --assess --type execute --verbose=4` |
| Checksum | SHA-256 generated from the final DMG after all applicable verification steps |

A real Apple notarization submission requires valid Apple credentials and a valid Developer ID certificate. Without those credentials, the unsigned workflow is still usable for development or private distribution, but the artifact is not Apple-trusted and must not be described as signed or notarized.

## Troubleshooting

**Signing identity not found.** Run `security find-identity -v -p codesigning` and confirm that the Developer ID Application certificate and private key are present. Set `DEVELOPER_ID_APPLICATION` to the exact identity string. Do not weaken the script to ad-hoc signing for a production release.

**Certificate import failure in CI.** Verify that the `.p12` secret was exported with its private key, encoded without line-wrapping corruption, and paired with the correct certificate password. The temporary keychain must be unlocked before importing and must be deleted after the job.

**Missing credentials.** This is expected in `unsigned` and `checks` modes; both deliberately skip signing and notarization. Use `unsigned` when you want an automatic GitHub Release containing a DMG. For a signed production release, configure all seven required secrets and verify that the `.p8` key belongs to the issuer and key ID configured in the workflow.

**Notarization rejection.** Download the submission log with `xcrun notarytool log` using the same authentication method. Common causes include an invalid nested signature, missing Hardened Runtime, invalid entitlements, or unsigned embedded code. Do not continue to stapling or publishing after a rejected submission.

**Invalid entitlements.** VoiceFlow intentionally uses the audio-input entitlement and explicitly disables App Sandbox. Do not add entitlements blindly. Global Fn monitoring and Accessibility injection are incompatible with the current sandboxed design.

**DMG creation or mount failure.** Confirm that `hdiutil` is available, the output disk has sufficient space, and the generated DMG is not being copied into its own staging directory. The script creates the DMG outside its temporary staging directory and immediately runs `hdiutil verify` and a read-only mount check.

**Stapling failure.** Confirm that the notarization status was accepted and that the runner can reach Apple’s ticket service. The script stops before checksum generation if stapling or validation fails.

**Gatekeeper warning for an unsigned DMG.** This is expected. On the Mac receiving the app, open the DMG and move VoiceFlow to Applications. Then Control-click `VoiceFlow.app`, choose **Open**, and confirm the prompt. If macOS still blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway** for VoiceFlow. Users may need to repeat this after replacing the app. A signed and notarized release avoids this extra step.

**Missing or incompatible Xcode.** Install the full Xcode version selected by `DEVELOPER_DIR` or by the GitHub workflow. Command Line Tools alone are not sufficient for the project build, `xcodebuild`, `notarytool`, and `stapler` operations used here.

**GitHub Release already exists.** A pushed-tag run uses the version tag and verifies it. A manual unsigned run uses a unique `unsigned-v<version>-<run-number>` tag. If a release for the same tag already exists, resolve the release/tag state intentionally rather than deleting or overwriting artifacts automatically.

## References

[1]: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow "Apple: Customizing the notarization workflow"
[2]: https://github.com/marketplace/actions/setup-xcode-version "GitHub Marketplace: Setup Xcode version"
[3]: https://docs.github.com/en/actions/concepts/runners/github-hosted-runners#overview-of-github-hosted-runners "GitHub Docs: About GitHub-hosted runners"
