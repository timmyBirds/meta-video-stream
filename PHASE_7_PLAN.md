# Phase 7 Plan: User-Entered Video URL on the Meta Display

_Created: May 30, 2026 · Verified against full source + official DAT v0.7 docs_

## Goal

Let the user type a video URL in the app and play it on the Meta Ray-Ban Display, by repurposing the existing "Watch Video on Glasses" real-estate that today plays a single hard-coded demo clip.

## Verified facts (full code read + official docs)

This plan was reconciled against the actual code (`WearablesManager.swift`, `ContentView.swift`, `AppState.swift`, `Info.plist`) and the official iOS display docs (`develop/dat/display-ios`, `display-overview`). Findings that shaped it:

- Display is already fully integrated. `addDisplay()` runs during `startDeviceSession()`, so `display` is live in `.connected`, `.streaming`, and `.watchingVideo`. `DAMEnabled` is already `true` in Info.plist. There is no DAM migration to do (earlier drafts were wrong on this).
- The SDK fetches and decodes the URL itself via `VideoPlayer(provider: .uri(url), codec: .mp4)`. There is no phone-side transcode (earlier "relay" framing was wrong).
- The display video player has hard constraints, and they dominate the design:
  - Format: MP4 only (HLS and other formats are not supported).
  - URL scheme: https only.
  - Max dimensions: 400 px per side AND 70,000 total pixels.
  - Concurrency: one video at a time per display session.
  - Display renders at 600x600; dims at 20s idle, sleeps at 25s.
- Because of the 70,000-pixel cap, this is not "play any internet video." A 1280x720 clip is ~25x over the limit. The existing demo (`video_266x150_faststart.mp4`, ≈39,900 px) is sized specifically to fit. The feature is realistically "play a small, pre-sized MP4 clip from a URL."
- `codec: .mp4` is hard-coded and that is correct, MP4 is the only supported format. No codec-detection work is needed (earlier draft was wrong to flag this).
- The current code ignores the SDK's failure signals. `VideoPlayer(... onError:)` and `display.onPlaybackEvent` (`.started/.ended/.error/.stopped`) exist but are unused, and `DisplayError` (incl. `.invalidVideoURL`) is not caught specifically. The `videoError` field in `ContentView` is declared but never set, so the inline error UI is dead.
- On failure, `startWatchingVideo` calls `teardown(...)`, which tears down the whole session (display + device). A bad URL therefore disconnects the glasses entirely, which is too heavy.

### What exists today (file:line)

- `ContentView.swift:244-258` — purple "Watch Video on Glasses" button; action calls `startWatchingVideo(url:)` with a hard-coded demo URL.
- `ContentView.swift:277-297` — Active Video Controls (Stop Video button + unused `videoError` text) shown when `appState == .watchingVideo`.
- `WearablesManager.swift:375-401` — `startWatchingVideo(url:)`: sends a wake/loading FlexBox, waits 300ms, sends `VideoPlayer(provider:.uri(url), codec:.mp4)`; on throw sets `.error` and tears down.
- `WearablesManager.swift:403-410` — `stopWatchingVideo()`: `display.sendVideoStop()` then standby view, back to `.connected`.
- `WearablesManager.swift:173-184` — `playVideoOnGlasses(url:)`: a duplicate lower-level send path, currently unused by the UI.
- `AppState.swift:33` — `.watchingVideo` case (no associated URL).

### Design note: mode-exclusive

`startStreaming()` and `startWatchingVideo()` both require `appState == .connected`, so camera (NDI) and video are mutually-exclusive modes, not a dual stream. This plan keeps that model. (Simultaneous operation would also contend for Bluetooth and is out of scope.)

## Scope of work

### M1 — Add URL input to the existing real-estate
- In the `ContentView.swift:244-258` block, add a `TextField` above the existing button, backed by `@AppStorage("glassesVideoUrl")` (mirrors the existing `@AppStorage("streamUrl")` pattern), defaulting to the current demo URL so first-run still works.
- The button calls `startWatchingVideo(url: glassesVideoUrl.trimmed)` instead of the hard-coded string.
- Add a short helper line under the field stating the real limits: "MP4 only, https, max 400px per side / 70,000 px total."
- Exit check: editing the field and tapping plays the entered URL; value persists across relaunch.

### M2 — Client-side validation before sending
- Reject before calling the SDK: empty input, non-`https` scheme, and (warn or block) a path that doesn't end in `.mp4`. Surface via `videoError`, do not enter `.watchingVideo` on invalid input.
- Optional but recommended: probe the asset with `AVURLAsset`/`loadValuesAsynchronously` to read natural dimensions and reject anything over 400px/side or 70,000 px before sending, turning a silent on-glasses failure into a clear in-app message. (Note: this downloads headers/initial bytes; keep it lightweight and time-boxed.)
- Exit check: bad scheme/format/size fails fast with an inline reason; no session disruption.

### M3 — Wire up the SDK's failure + playback signals (the real hardening)
- Pass an `onError` closure to `VideoPlayer(...)` and route its `VideoPlaybackError` cases (`.urlInvalid`, `.alreadyPlaying`, `.playbackFailed`, `.unknown`) into a published `videoError` on `WearablesManager`.
- Subscribe to `display.onPlaybackEvent`; on `.ended`/`.stopped` return to `.connected` and standby view; on `.error` surface the message.
- Catch `DisplayError` specifically in `startWatchingVideo` (e.g. `.invalidVideoURL`, `.deviceDisconnected`) and show targeted messages.
- Bind `ContentView`'s `videoError` to the manager's published value so the existing (currently dead) inline error text actually appears.
- Exit check: a too-large/non-MP4/unreachable URL produces a visible, specific in-app error and the glasses recover.

### M4 — Don't tear down the session on a video error
- Change the failure path in `startWatchingVideo` so a video error returns to `.connected` (keep the display + device session alive) instead of calling `teardown(...)`. Reserve teardown for genuine session/device loss (`DisplayError.deviceDisconnected`).
- Decide between `startWatchingVideo(url:)` and the unused `playVideoOnGlasses(url:)`; standardize on one and remove the other to avoid drift.
- Exit check: after a failed video the user is still connected and can immediately retry or switch modes.

### M5 — State + lifecycle polish
- Optionally carry the URL on the state (`.watchingVideo(url:)`) so the status row can show what's playing, matching how `streamName` is surfaced for NDI.
- Confirm thermal/battery handling: today `handleThermalChange`/`handleBatteryChange` gate on `appState.isActive`, which is only `.connecting/.streaming/.reconnecting`, so `.watchingVideo` is NOT covered. Decide whether display playback should also respond to thermal/battery (likely low priority since there's no camera/NDI load, but document the decision).
- Respect display sleep (20s/25s): playing video counts as activity, but confirm behavior if a video ends and the view goes idle.
- Exit check: documented, consistent behavior across thermal/battery/sleep while in `.watchingVideo`.

### M6 — Tests & docs
- Mock-device tests (Phase 1 `MockCaptureTests` pattern): URL validation (scheme/format/size), `.connected → .watchingVideo → .connected` transition, and the error path staying connected.
- Update README and `docs/`: the button now takes a user MP4 URL; document the 400px/70,000px/https/MP4 constraints prominently.

## Files to touch

- `ContentView.swift` — URL `TextField` + `@AppStorage` + helper text (M1), validation glue (M2), bind `videoError` to manager (M3).
- `WearablesManager.swift` — `onError`/`onPlaybackEvent` wiring + `DisplayError` handling + published `videoError` (M3), non-destructive failure path + dedupe video methods (M4), optional `.watchingVideo(url:)` + thermal/battery decision (M5).
- `AppState.swift` — optional `.watchingVideo(url:)` associated value (M5).
- Tests target — validation + state-transition tests (M6).

## Environment & build readiness (verified May 30, 2026)

- SDK version is pinned and resolved. `project.yml` declares `MetaWearablesDAT from: "0.7.0"`; `Package.resolved` pins it to exactly **0.7.0** (revision `c40db39`). This matches the official v0.7 docs the plan references, so the code in the repo is written against the same API surface documented for `VideoPlayer`, `onPlaybackEvent`, and `DisplayError`. (Also resolved: HaishinKit 1.9.9, Logboard 2.5.0.)
- DAM is enabled: `Info.plist` contains `MWDAT > DAMEnabled = true`. Confirmed.
- NDI binary is present: `Vendor/libndi_ios.a` (~127MB) is materialized, so Git LFS pulled correctly.
- Tests use the Mock Device Kit: `Tests/MetaVideoStreamTests/MockCaptureTests.swift` pairs a mock device via `MockDeviceKit.shared.pairRaybanMeta()` and asserts session/stream/frame plumbing. M6 video tests should follow this pattern, BUT note the mock pairs a Ray-Ban Meta (camera) device; whether `MWDATMockDevice` 0.7.0 can simulate a Display device and `onPlaybackEvent` is unverified, the next agent must check the MockDevice API before assuming display playback is testable without hardware.

### Build cannot be verified in this environment — do it on a Mac
- This workspace is Linux (aarch64) with no `xcodebuild`, `swift`, or `xcodegen`. iOS apps require macOS + Xcode, so the project was NOT compiled here; buildability is unverified by compilation. The next agent must build on a Mac.
- Build steps: from `ios-app/`, run `./generate.sh` (installs xcodegen if needed, regenerates `MetaVideoStream.xcodeproj`), then open in Xcode or `xcodebuild`.
- Credentials are placeholders. `Config/Debug.xcconfig` and `Config/Release.xcconfig` exist but contain `META_APP_ID = REPLACE_WITH_YOUR_META_APP_ID`, `CLIENT_TOKEN = REPLACE_WITH_YOUR_CLIENT_TOKEN`, and `DEVELOPMENT_TEAM = XXXXXXXXXX`. Real Meta app credentials are needed to run against hardware/registration. Note a possible team-ID conflict: `project.yml` and `generate.sh` hardcode team `B5WNGX3893`, while the xcconfig says `XXXXXXXXXX`, reconcile these before signing.
- First action for the executing agent: on a Mac, fill in the xcconfig, run `./generate.sh`, build, and run `MockCaptureTests` green to confirm a clean baseline before starting M1.

## Risks
- The 70,000-pixel cap is the defining limitation. Set expectations in the UI; consider shipping a curated set of known-good clip URLs rather than a free-form field, or pairing the field with the optional dimension pre-check (M2).
- Preview-stage API: `onPlaybackEvent`, `VideoPlaybackError`, and `DisplayError` cases are v0.7; reconfirm names against the iOS DisplayAccess sample before finalizing M3.
- Audio: docs describe a silent/full-screen video player; whether clips carry audio to the open-ear speakers is unconfirmed. Treat as out of scope unless verified.

## Open questions
1. Free-form URL field vs. a curated clip list (or both) given the size cap? Product decision.
2. Should display playback react to thermal/battery, or is leaving `.watchingVideo` outside `isActive` acceptable?
3. Do display video clips carry audio, and to where?
4. Worth pre-validating dimensions with `AVURLAsset` (M2 optional) to avoid silent on-glasses rejections?

## Sources
- [iOS display integration guide (Video section: MP4, 400px/70,000px, https, onPlaybackEvent, DisplayError)](https://wearables.developer.meta.com/docs/develop/dat/display-ios/)
- [Display overview (constraints, lifecycle, best practices)](https://wearables.developer.meta.com/docs/develop/dat/display-overview/)
- [Device Access Toolkit v0.7 release notes](https://github.com/facebook/meta-wearables-dat-ios/discussions/178)
- [iOS DisplayAccess sample app](https://github.com/facebook/meta-wearables-dat-ios/tree/main/samples/DisplayAccess)
