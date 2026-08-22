# VoiceFlow Release Guide

VoiceFlow is distributed as a Developer ID-signed, Hardened Runtime macOS application inside a notarized disk image. The local and GitHub Actions workflows use the same `scripts/release.sh` pipeline so that build, signing, packaging, notarization, verification, and checksum behavior is not duplicated.

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

A local release requires a Mac with the full Xcode installation selected, a Developer ID Application certificate in the login or a dedicated build keychain, and Apple notarization credentials. The script prefers `DEVELOPER_DIR` and otherwise uses `/Applications/Xcode.app/Contents/Developer` when present.

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

The script cleans its own release derived-data and output paths, builds Release with the supplied `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, verifies the app signature, creates a normal mountable DMG containing `VoiceFlow.app` and an `Applications` shortcut, submits the DMG with `xcrun notarytool --wait`, staples the ticket, validates the stapled DMG, runs Gatekeeper assessment, and only then computes the SHA-256 checksum.

## GitHub release

The workflow in `.github/workflows/release.yml` runs for tags matching `v*`. A release is created by pushing a version tag after the implementation has been committed:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow uses a pinned `macos-15` runner and selects Xcode `16.4`, which is compatible with the project’s macOS 14 deployment target. GitHub-hosted runner images are maintained separately from the workflow and can change over time, so the workflow selects an explicit Xcode version rather than depending on `macos-latest` defaults. The setup action’s documented version-selection behavior is described in [Setup Xcode version][2], and GitHub documents hosted-runner image maintenance in [About GitHub-hosted runners][3].

The workflow performs these stages in order:

1. It checks out the tag and validates that it is a version tag such as `v1.0.0`.
2. It imports an encrypted Developer ID certificate into a temporary keychain, with the certificate file and keychain removed in an `always()` cleanup step.
3. It materializes the encrypted App Store Connect `.p8` key only under `$RUNNER_TEMP`.
4. It runs the XCTest suite.
5. It runs `./scripts/release.sh --check`.
6. It runs `./scripts/release.sh VERSION`, which performs the build, signing, DMG creation, notarization, stapling, Gatekeeper verification, and checksum generation.
7. It uploads only the final DMG and `SHA256SUMS.txt` as workflow artifacts.
8. It creates the GitHub Release with generated notes and those two final artifacts.

### Required GitHub Actions secrets

Configure these repository or organization secrets before pushing the first release tag:

| Secret | Required | Purpose |
|---|---:|---|
| `DEVELOPER_ID_APPLICATION` | Yes | Developer ID Application identity string |
| `DEVELOPER_CERTIFICATE_P12_BASE64` | Yes | Base64-encoded exported Developer ID certificate and private key |
| `DEVELOPER_CERTIFICATE_PASSWORD` | Yes | Password protecting the `.p12` export |
| `KEYCHAIN_PASSWORD` | Yes | One-time password for the temporary CI keychain |
| `APPLE_API_KEY_BASE64` | Yes | Base64-encoded App Store Connect private `.p8` key |
| `APPLE_API_KEY_ID` | Yes | App Store Connect API key ID |
| `APPLE_ISSUER_ID` | Yes | App Store Connect issuer ID |

`GITHUB_TOKEN` is supplied by GitHub Actions through `github.token`; the workflow requests only `contents: write` so it can create the release. The workflow does not print secret values.

To create the certificate secret, export the Developer ID Application certificate and private key from Keychain Access as a password-protected `.p12`, then base64-encode it locally. To create the API-key secret, base64-encode the downloaded App Store Connect `.p8` file. Delete any temporary encoded files after adding the secrets. Never commit `.p12`, `.cer`, `.pem`, `.p8`, provisioning profiles, or Apple credentials.

## Release verification

The production pipeline is intentionally fail-fast. It does not create a GitHub Release when signing, notarization, stapling, DMG verification, Gatekeeper assessment, or checksum generation fails.

| Stage | Verification |
|---|---|
| Project | Scheme, bundle identifier, AppIcon, Hardened Runtime, and non-sandbox configuration |
| Build | Release `.app` exists with requested version and build number |
| Signature | `codesign --verify --deep --strict --verbose=2` plus signature metadata inspection |
| DMG | `hdiutil verify`, read-only mount, app presence, Applications shortcut, and nested app signature |
| Notarization | `xcrun notarytool submit ... --wait` must return success |
| Stapling | `xcrun stapler staple` followed by `xcrun stapler validate` |
| Gatekeeper | `spctl --assess --type execute --verbose=4` on the built app |
| Checksum | SHA-256 generated after stapling from the final DMG |

A real Apple notarization submission requires valid Apple credentials and a valid Developer ID certificate. Without those credentials, the source, project configuration, strict preflight, unsigned Release build, tests, and script syntax can still be validated, but notarization and Gatekeeper acceptance must be reported as unverified rather than claimed as successful.

## Troubleshooting

**Signing identity not found.** Run `security find-identity -v -p codesigning` and confirm that the Developer ID Application certificate and private key are present. Set `DEVELOPER_ID_APPLICATION` to the exact identity string. Do not weaken the script to ad-hoc signing for a production release.

**Certificate import failure in CI.** Verify that the `.p12` secret was exported with its private key, encoded without line-wrapping corruption, and paired with the correct certificate password. The temporary keychain must be unlocked before importing and must be deleted after the job.

**Missing credentials.** For local releases, set either `NOTARY_KEYCHAIN_PROFILE` or the App Store Connect API-key variables. For CI, verify all seven required secrets exist and that the `.p8` key belongs to the issuer and key ID configured in the workflow.

**Notarization rejection.** Download the submission log with `xcrun notarytool log` using the same authentication method. Common causes include an invalid nested signature, missing Hardened Runtime, invalid entitlements, or unsigned embedded code. Do not continue to stapling or publishing after a rejected submission.

**Invalid entitlements.** VoiceFlow intentionally uses the audio-input entitlement and explicitly disables App Sandbox. Do not add entitlements blindly. Global Fn monitoring and Accessibility injection are incompatible with the current sandboxed design.

**DMG creation or mount failure.** Confirm that `hdiutil` is available, the output disk has sufficient space, and the generated DMG is not being copied into its own staging directory. The script creates the DMG outside its temporary staging directory and immediately runs `hdiutil verify` and a read-only mount check.

**Stapling failure.** Confirm that the notarization status was accepted and that the runner can reach Apple’s ticket service. The script stops before checksum generation if stapling or validation fails.

**Gatekeeper rejection.** Inspect the verbose `spctl` and `codesign` output, verify the app was built with Developer ID signing, and confirm the final DMG was notarized. A local machine may apply policy differently from a clean end-user machine; test the mounted artifact on a clean macOS installation when possible.

**Missing or incompatible Xcode.** Install the full Xcode version selected by `DEVELOPER_DIR` or by the GitHub workflow. Command Line Tools alone are not sufficient for the project build, `xcodebuild`, `notarytool`, and `stapler` operations used here.

**GitHub Release already exists.** A tag-triggered run uses `gh release create` with `--verify-tag`. If a release for the same tag already exists, resolve the release/tag state intentionally rather than deleting or overwriting artifacts automatically.

## References

[1]: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow "Apple: Customizing the notarization workflow"
[2]: https://github.com/marketplace/actions/setup-xcode-version "GitHub Marketplace: Setup Xcode version"
[3]: https://docs.github.com/en/actions/concepts/runners/github-hosted-runners#overview-of-github-hosted-runners "GitHub Docs: About GitHub-hosted runners"
