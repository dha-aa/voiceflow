# Change 025: Persistent Application Audio Storage

## Summary

VoiceFlow recordings are now written to a dedicated `audio` directory inside the app’s Application Support container instead of macOS’s temporary directory.

The resulting layout is:

```text
~/Library/Application Support/<bundle identifier>/audio/recording_<UUID>.wav
```

For the production bundle, the directory is normally:

```text
~/Library/Application Support/dha-aa.voiceflow/audio/
```

In a sandboxed build, Foundation resolves the same logical location inside the application container.

## Recording lifecycle

`AudioRecorder` owns the output directory and creates it before opening the WAV file. The default directory is exposed as `AudioRecorder.appAudioDirectory`, while tests and controlled callers can inject another directory without changing recording behavior.

Each completed recording receives a unique filename in the form `recording_<UUID>.wav`. VoiceFlow continues to record 16 kHz, mono, PCM float32 audio compatible with the local transcription engines.

The lifecycle is:

> Fn hold → create or verify app audio directory → record → close the audio file on stop → return the completed WAV URL → transcribe and inject

Stopping a recording releases the active `AVAudioFile` and audio engine references, but the completed WAV remains in the app audio folder. This makes the file available for later inspection or future audio-management UI. It is not automatically dismissed after transcription or injection.

If recording setup fails, VoiceFlow removes the incomplete output file and resets the recorder state. A recording that ends normally is retained. Users or a future audio-management feature may remove retained recordings explicitly.

## Privacy and storage behavior

Audio remains local to the Mac. The storage change does not create a network request and does not alter WhisperKit, FluidAudio, AI, snippets, selection-aware processing, or text-injection behavior.

Diagnostics continue to avoid microphone samples and transcription contents. Logs contain only non-content metadata such as an opaque recording identifier, duration, frame counts, write errors, and file byte count. The existing human-readable recording path print remains a local filesystem path and does not expose audio content.

The audio folder is application data, not the model folder. Models continue to use the separate Application Support `models` directory.

## Implementation

The change is implemented in `voiceflow/Core/Audio/AudioRecorder.swift`:

| Component | Behavior |
|---|---|
| `AudioRecorder.appAudioDirectory` | Resolves `<Application Support>/<bundle identifier>/audio` and ensures the directory exists. |
| `AudioRecorder.audioDirectory` | Stores the normalized directory used by an individual recorder instance. |
| `AudioRecorder.init(..., audioDirectory:)` | Allows test isolation or an explicitly selected directory while defaulting to the production app audio folder. |
| `startRecording()` | Creates the configured directory before creating the WAV output file. |
| Start-failure cleanup | Removes the incomplete output path and clears recorder state. |
| `stopRecording()` | Flushes/releases the file, returns the completed URL, and leaves the file retained in the audio folder. |

## Acceptance criteria

| Area | Acceptance criterion |
|---|---|
| Default location | Production recordings are created below the VoiceFlow Application Support `audio` directory. |
| Directory creation | The audio directory is created automatically before the first recording if it does not exist. |
| File format | Recordings remain 16 kHz, mono, PCM float32 WAV files. |
| Unique files | Each recording uses a UUID-based filename and does not overwrite another recording. |
| Retention | A successfully stopped recording remains available at the returned URL after the recorder stops. |
| Failure cleanup | Failed recording setup removes the incomplete file and leaves the recorder safe to reuse. |
| Isolation | Tests can inject a temporary audio directory without writing into the user’s real app data. |
| Privacy | No audio content or transcription text is added to logs, and no network request is introduced. |
| Compatibility | Existing Fn push-to-talk, local transcription, AI processing, snippets, injection, overlay, and model workflows remain unchanged. |

## Verification evidence

The test-first sequence was completed with a red compile validation before implementation. The focused `AudioRecorderTests` suite then completed with **9 tests and zero failures**, including configured-directory placement and default `audio` folder assertions. The complete `voiceflowTests` suite completed with **174 tests and zero failures**.

The storage test uses an injected temporary directory and removes that fixture during teardown. The production path is asserted to use the VoiceFlow bundle identifier and `audio` directory without requiring a real microphone recording.

## Known boundary

Completed recordings are retained until removed by the user or a future cleanup feature. macOS may independently remove application temporary data, but these files are no longer placed in the temporary directory and should be treated as persistent app data. A future Settings or maintenance action can safely add explicit recording deletion or retention limits.
