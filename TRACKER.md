# Project Tracker

_Last updated: 2026-05-12_

**Current status:** Phases 0–2 complete. Phase 4 effectively complete via the OBS Studio pivot (commit `60d3315`). Phase 3 deferred — its reliability work has been folded into Phase 5. Next up: Phase 5 (Polish).

## Phase 0 — Access and decisions

- [x] Sign up at Meta Wearables Developer Center (confirm preview eligibility)
- [x] Pick mobile platform → **iOS**
- [x] Pick Teams integration path → **Virtual camera via OBS Studio**
- [x] Set up source control → **GitHub (private)**
- [x] Set up CI pipeline → **GitHub Actions**
- [x] Set up project board → replaced with this file

## Phase 1 — Glasses capture on phone ✅

- [x] Scaffold iOS Xcode project (xcodegen project.yml + generate.sh)
- [x] Add Meta Wearables SDK via SPM (MWDATCore + MWDATCamera)
- [x] Info.plist with MWDAT keys wired to xcconfig (gitignored secrets)
- [x] WearablesManager: registration → permission → session → stream lifecycle
- [x] ContentView: start/stop capture UI, live frame preview, status badges
- [x] MockCaptureTests: phase 1 exit criterion as XCTest (no hardware needed)
- [x] Fill in xcconfig credentials, run `generate.sh`, open in Xcode
- [x] MockCaptureTests green
- [x] **Exit criterion:** tap Start Capture → see glasses video on phone screen (mock device) — landed in commit `a3ec582`

## Phase 2 — Encode and stage a local stream ✅

- [x] Pull camera frames from Meta SDK; pipe to SRTHaishinKit (H.264 VideoToolbox encoder)
- [x] Mux in microphone audio (phone mic first, glasses mic later)
- [x] Push to local OBS Studio instance via SRT (Secure Reliable Transport)
- [x] **Exit criterion:** glasses → phone → OBS Studio → Teams Virtual Camera — landed in commit `70bc905`

## Phase 3 — Public outbound stream (DEFERRED)

Status: deferred. Reliability work (reconnect logic, stream-health UI) has been pulled into Phase 5. Revisit hosted endpoints only if a use case requires the macOS host to be off the phone's local network.

- [ ] ~~Replace local endpoint with hosted RTMP endpoint~~ (deferred)
- [→] Reconnect logic — moved to Phase 5
- [→] Adaptive bitrate / stream-health UI — moved to Phase 5
- [ ] ~~Preflight check~~ (deferred)
- [ ] ~~Exit criterion: stable 5-minute push to public RTMP URL over cellular~~ (deferred)

## Phase 4 — Teams integration (virtual camera via OBS Studio) ✅

Pivoted from a custom macOS companion app + CoreMediaIO DAL plugin to OBS Studio, which already provides SRT input and a virtual-camera output. Custom-companion work was retired in commit `60d3315`.

- [x] Choose OBS Studio as the macOS bridge
- [x] Configure OBS SRT input + virtual camera output (manual setup, documented in `docs/`)
- [x] Select OBS virtual camera in Teams; verify feed appears
- [x] **Exit criterion:** glasses video visible in a live Teams meeting

## Phase 5 — Polish (NEXT)

See `docs/PHASE5.md` for the detailed plan. Five workstreams:

### 5.1 Connection state machine
- [ ] Formalize states: `Idle → Registering → AwaitingPermission → Connecting → Streaming → Reconnecting → Error → Stopped`
- [ ] Drive UI off a single source of truth; disable invalid actions per state
- [ ] Surface SRT URL/port in-app for verification against OBS

### 5.2 Reconnect logic (pulled from Phase 3)
- [ ] Detect SRT disconnect events from HaishinKit
- [ ] Exponential backoff (1s → 2s → 4s, cap 30s)
- [ ] Cap on consecutive failures before user prompt
- [ ] Preserve session state across reconnects so OBS source stays alive
- [ ] "Reconnecting (attempt N of M)…" UI

### 5.3 Thermal & battery handling ✅
- [x] Subscribe to `ProcessInfo.thermalStateDidChangeNotification`
- [x] At `.serious`: drop bitrate/framerate (`SRTStreamManager.reduceThermalLoad()`), show warning banner
- [x] At `.critical`: pause SRT, set `AppState.paused(srtURL:)`, show modal (Resume / Stop)
- [x] `AppState.paused` — new case distinct from `.stopped`; carries the URL for Resume without a full reconnect
- [x] `SRTStreamManager.reduceThermalLoad()` and `restoreDefaultQuality()` named methods
- [x] Subscribe to `UIDevice.batteryLevelDidChangeNotification`; warn <20% (banner), prompt <10% (alert)
- [x] Non-blocking banners: thermal serious, battery low, glasses overheat hint (slide-in from top)
- [x] Battery critical alert: Stop Streaming / Keep Going (suppresses re-alert for session)

### 5.4 Permission & onboarding flows
- [ ] First-launch walkthrough: camera, Bluetooth, Meta AI registration handoff
- [ ] Recovery paths if permissions revoked mid-session (deep-link to Settings)
- [ ] Handle Meta-side de-authorization with a clear re-register CTA

### 5.5 End-of-stream summary
- [ ] On stop: duration, average bitrate, dropped frames, reconnect count
- [ ] Persist last N sessions for review

**Phase 5 exit criterion:** a non-technical user can launch the app cold, get glasses streaming into Teams via OBS in under 60 seconds, recover from a typical Wi-Fi dropout without intervention, and see a meaningful session summary at the end.

**Rough sequencing:** week 1 — state machine + reconnect; week 2 — thermal/battery + UX polish; week 3 — permissions/onboarding/summary; week 4 — exit-criteria sign-off.

## Phase 6 — Distribution and feedback

- [ ] TestFlight build for phone app
- [ ] Whitelist test accounts under Meta preview constraints
- [ ] Add telemetry: drop rate, latency, reconnect counts
- [ ] Decide on broader rollout once Meta preview opens
