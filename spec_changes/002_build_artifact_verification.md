# Specification Change 002: Build Artifact Verification

**Date:** 2026-08-23
**Status:** Implemented and validated
**Implementation commit:** `094e826 Harden build artifact verification`

## Purpose

This change records the correction made after a successful Xcode build was incorrectly reported as missing its application artifact during verification.

The issue was in the local `scripts/buildapp.sh` utility’s artifact discovery and promotion logic. The Xcode build itself was not changed or silenced. The fix makes the utility locate the generated app more robustly, verify it before promotion, and provide a useful diagnostic if no bundle is found.

## Changed file

```text
scripts/buildapp.sh
```

No application source code, project settings, entitlements, model behavior, or privacy behavior was changed for this fix.

## Artifact discovery behavior

After `xcodebuild` returns successfully, the script now uses the selected configuration’s products directory as the artifact root:

```text
<temporary-derived-data>/Build/Products/<configuration>
```

It first checks the expected product path:

```text
<products-directory>/VoiceFlow.app
```

If that exact path is absent, it searches the products directory for another top-level `.app` bundle. This prevents a valid product from being rejected solely because Xcode emitted a different app directory name or product representation.

If no app bundle is found, the script now reports:

- the products directory it searched; and
- any `.app` paths discovered during a bounded diagnostic search.

The failure remains non-zero and strict. A successful `xcodebuild` result is not treated as a successful app build unless an actual app bundle is found.

## Safe promotion behavior

The discovered app is first copied to:

```text
build/.VoiceFlow.app.staging
```

The staging bundle must contain:

```text
Contents/
Contents/Info.plist
```

Its bundle identifier must be:

```text
dha-aa.voiceflow
```

Only after those checks pass is the staging directory promoted to:

```text
build/VoiceFlow.app
```

The prior output app is not removed until the newly built artifact has been copied and validated. Temporary Xcode derived data continues to be cleaned up through the script’s existing exit trap.

## Verification run

The script was run after this change with:

```bash
./scripts/buildapp.sh --clean
```

The run completed with `BUILD SUCCEEDED` and `buildapp: done`. Independent verification confirmed:

| Check | Result |
|---|---|
| `build/VoiceFlow.app` exists | Passed |
| `VoiceFlow.app/Contents` exists | Passed |
| `VoiceFlow.app/Contents/Info.plist` exists | Passed |
| `VoiceFlow.app/Contents/MacOS/voiceflow` is executable | Passed |
| Bundle identifier | `dha-aa.voiceflow` |
| Temporary builder directories remaining | 0 |
| App launch | Not performed |
| App installation | Not performed |
| Tests | Not run by this invocation |

## Usage

Build the default unsigned Debug app:

```bash
./scripts/buildapp.sh
```

Clean the known generated app output before building:

```bash
./scripts/buildapp.sh --clean
```

Build and run the complete XCTest suite:

```bash
./scripts/buildapp.sh --test
```

The utility remains a local unsigned developer helper. It does not sign or notarize the app.

## Privacy and safety

This change adds no audio, transcript, injected text, clipboard, credential, or secret logging. Diagnostic output contains only safe paths and artifact categories. Cleanup remains limited to the script-owned temporary build directory, the known staging path, and the configured `build/VoiceFlow.app` output.
