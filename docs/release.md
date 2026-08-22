# VoiceFlow Release Guide

VoiceFlow supports two distribution modes. The default path creates an **unsigned, unnotarized DMG** for development or private sharing without Apple credentials. The optional production path creates a Developer ID-signed and notarized DMG when Apple signing and notarization credentials are available.

> An unsigned DMG can be published to GitHub Releases, but it is not Apple-trusted. macOS may show a security warning when a recipient opens the application.

## Release metadata

The Xcode project and release script use the following production configuration:

| Setting | Value |
|---|---|
| Xcode project | `voiceflow.xcodeproj` |
| Scheme | `voiceflow` |
| Product bundle | `VoiceFlow.app` |
| Swift module | `voiceflow` |
| Bundle identifier | `dha-aa.voiceflow` |
| Deployment target | macOS 14.0 |
| Application icon | `AppIcon` asset catalog |
| Release runtime | Hardened Runtime enabled |
| App Sandbox | Disabled for global Fn monitoring and Accessibility injection |
| Microphone entitlement | `com.apple.security.device.audio-input` |
| Marketing version | Supplied as `MARKETING_VERSION` by the release version |
| Build number | Supplied as `CURRENT_PROJECT_VERSION` by `BUILD_NUMBER` or the GitHub run number |

The release script reads the project configuration before building. It does not patch the generated app bundle or `Info.plist` after the build.

## Local unsigned DMG

A local unsigned release requires only the full Xcode installation. Command Line Tools alone are not sufficient. From the repository root, run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./scripts/release.sh --unsigned 1.0.0
```

The script performs the following steps:

1. Resolves the Xcode project and Release configuration.
2. Validates the product name, bundle identifier, AppIcon, Hardened Runtime, and non-sandbox configuration.
3. Cleans the release derived-data directory.
4. Builds `VoiceFlow.app` with the supplied marketing version and build number.
5. Creates `VoiceFlow-1.0.0.dmg` with an `Applications` shortcut.
6. Runs `hdiutil verify` and mounts the DMG read-only to confirm its structure.
7. Generates `SHA256SUMS.txt` from the final unsigned DMG.

The default output directory is `dist/`. To keep generated artifacts outside the repository, use temporary paths:

```bash
OUTPUT_DIR=/tmp/voiceflow-unsigned/dist \
DERIVED_DATA_DIR=/tmp/voiceflow-unsigned/derived-data \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./scripts/release.sh --unsigned 1.0.0
```

The unsigned local artifacts are:

```text
dist/VoiceFlow-1.0.0.dmg
dist/SHA256SUMS.txt
```

## Local signed and notarized DMG

The default release-script path is for production distribution and requires a Developer ID Application certificate plus Apple notarization credentials. The script supports either a stored `notarytool` keychain profile or an App Store Connect API key.

For API-key authentication, configure these variables in a secure shell or secret manager:

| Variable | Purpose |
|---|---|
| `DEVELOPER_ID_APPLICATION` | Developer ID Application identity or its full certificate identity string |
| `APPLE_API_KEY_PATH` | Local path to the App Store Connect private `.p8` key |
| `APPLE_API_KEY_ID` | App Store Connect key ID |
| `APPLE_ISSUER_ID` | App Store Connect issuer ID |
| `BUILD_NUMBER` | Optional numeric build number; defaults to `1` locally |
| `DEVELOPER_DIR` | Optional full Xcode developer directory |

Alternatively, set `NOTARY_KEYCHAIN_PROFILE` and use a profile stored by `xcrun notarytool store-credentials`. Never commit any certificate, private key, password, or credential file.

Run the production preflight first:

```bash
./scripts/release.sh --check
```

The preflight checks Xcode, the scheme, project metadata, Hardened Runtime, signing identity, notarization tooling, and credentials. It does not build, submit, staple, or publish anything.

After the preflight passes, create the signed release:

```bash
DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)' \
APPLE_API_KEY_PATH="$HOME/.private/AuthKey_KEYID.p8" \
APPLE_API_KEY_ID='KEYID' \
APPLE_ISSUER_ID='ISSUER-UUID' \
./scripts/release.sh 1.0.0
```

The signed path verifies the app signature, creates the DMG, submits the DMG with `xcrun notarytool --wait`, staples and validates the ticket, assesses the mounted app with Gatekeeper, and generates the checksum only after those steps succeed.

## GitHub Actions workflow

The workflow is located at `.github/workflows/release.yml`. It uses a pinned `macos-15` runner and selects Xcode `16.4`. The workflow has two triggers.

### Pushed version tags

Pushing a tag matching `v*` automatically selects the unsigned mode and does not require Apple secrets:

```bash
git checkout main
git pull origin main
git tag v1.0.0
git push origin v1.0.0
```

A successful tag run executes the XCTest suite, builds and verifies `VoiceFlow-1.0.0.dmg`, generates `SHA256SUMS.txt`, and creates a GitHub Release containing both files. The Release is clearly labeled as unsigned. No signing, notarization, stapling, or Gatekeeper claim is made.

### Manual workflow runs

Open **GitHub → Actions → Release VoiceFlow → Run workflow**, select the branch, choose a mode, and optionally enter a version.

| Mode | Apple credentials | Behavior |
|---|---:|---|
| `unsigned` | Not required | Builds an unsigned DMG, uploads the artifact, and creates a GitHub Release. |
| `checks` | Not required | Runs tests and builds an unsigned Release app, but does not publish a DMG or GitHub Release. |
| `production-release` | Required | Imports the signing certificate, signs, notarizes, staples, verifies, checksums, and publishes a production DMG. |

For manual `unsigned` runs, a version such as `1.0.0` creates a unique release tag such as `unsigned-v1.0.0-123`. If no version is entered, the workflow uses `0.0.0-manual.<run-number>`.

## Required production secrets

No secrets are needed for unsigned tags or the manual `unsigned` and `checks` modes. Configure the following encrypted GitHub Actions secrets only when using `production-release`:

| Secret | Purpose |
|---|---|
| `DEVELOPER_ID_APPLICATION` | Developer ID Application signing identity |
| `DEVELOPER_CERTIFICATE_P12_BASE64` | Base64-encoded password-protected certificate and private key |
| `DEVELOPER_CERTIFICATE_PASSWORD` | Password for the `.p12` file |
| `KEYCHAIN_PASSWORD` | Password for the temporary CI keychain |
| `APPLE_API_KEY_BASE64` | Base64-encoded App Store Connect private `.p8` key |
| `APPLE_API_KEY_ID` | App Store Connect key ID |
| `APPLE_ISSUER_ID` | App Store Connect issuer ID |

The workflow materializes certificate and API-key files only under `$RUNNER_TEMP` and removes them in an `always()` cleanup step. Never print or commit secret values. `GITHUB_TOKEN` is supplied automatically by GitHub Actions and is used to create the Release.

## Artifact verification

The unsigned workflow verifies the artifact’s structure and checksum. The signed workflow performs the additional trust checks:

| Check | Unsigned mode | Signed production mode |
|---|---:|---:|
| Release app builds | Yes | Yes |
| Correct bundle metadata | Yes | Yes |
| DMG exists | Yes | Yes |
| `hdiutil verify` | Yes | Yes |
| Read-only mount contains `VoiceFlow.app` | Yes | Yes |
| Applications shortcut exists | Yes | Yes |
| `codesign --verify` | No | Yes |
| Apple notarization | No | Yes |
| Stapled ticket validation | No | Yes |
| Gatekeeper assessment | No | Yes |
| SHA-256 checksum | Yes | Yes, after stapling |

A successful unsigned build must not be described as signed, notarized, stapled, or Gatekeeper-approved.

## Installing an unsigned DMG

An unsigned DMG is suitable for development or private sharing, but recipients may see an unidentified-developer warning. To install it, open the DMG and drag `VoiceFlow.app` to Applications. The first time it is opened, Control-click `VoiceFlow.app`, choose **Open**, and confirm the macOS prompt.

If macOS continues to block the app, open **System Settings → Privacy & Security**, locate the blocked VoiceFlow message, and choose **Open Anyway**. Users may need to repeat this process after replacing the application with a newer unsigned build. Signed and notarized distribution avoids this extra installation step.

## Security and privacy rules

Never commit `.p12`, `.cer`, `.pem`, `.p8`, provisioning profiles, Apple credentials, keychain passwords, audio recordings, model artifacts, or generated DMGs. The release workflow must not print secrets.

VoiceFlow’s application diagnostics are privacy-safe metadata logs. They may include model identifiers, paths, durations, byte counts, process identifiers, and error categories. They must not contain microphone audio, transcription results, inserted text, clipboard contents, or secret values.

## Troubleshooting

**The unsigned workflow fails before creating a DMG.** Open the workflow log and check the Xcode version, scheme, available disk space, and the exact error from `xcodebuild` or `hdiutil`. The unsigned path should not require a Developer ID certificate or Apple notarization credentials.

**The GitHub Actions Run workflow button is missing.** Confirm that `.github/workflows/release.yml` exists on the selected branch and that the workflow has been pushed to GitHub. Refresh the Actions page and select **Release VoiceFlow**.

**A manual unsigned run does not create a Release.** Confirm that `mode` is `unsigned`, not `checks`. The `checks` mode intentionally publishes nothing.

**A signed production run reports a missing identity.** Confirm that the certificate and private key were exported together, the base64 value is intact, and `DEVELOPER_ID_APPLICATION` matches the identity shown by `security find-identity -v -p codesigning`.

**Notarization is rejected.** Use `xcrun notarytool log` with the same credentials to inspect Apple’s submission log. Common causes include invalid nested signatures, missing Hardened Runtime, invalid entitlements, or unsigned embedded code. Do not publish a signed release after a rejected submission.

**The DMG cannot be mounted.** Run `hdiutil verify` against the downloaded file and confirm that the download completed. A checksum mismatch means the artifact should be downloaded again rather than installed.

**Gatekeeper blocks VoiceFlow.** This is expected for an unsigned DMG. Use Control-click → **Open**, followed by **System Settings → Privacy & Security → Open Anyway** if necessary.

## References

[1]: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow "Apple: Customizing the notarization workflow"
[2]: https://github.com/marketplace/actions/setup-xcode-version "GitHub Marketplace: Setup Xcode version"
[3]: https://docs.github.com/en/actions/concepts/runners/github-hosted-runners#overview-of-github-hosted-runners "GitHub Docs: About GitHub-hosted runners"
[4]: https://support.apple.com/en-gb/guide/mac-help/mh40616/mac "Apple Support: Safely open apps on Mac"
