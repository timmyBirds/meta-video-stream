# Project Tracker

_Last updated: 2026-05-13_

**Current status:** Phases 0–5 complete. Successfully pivoted from SRT-over-Wi-Fi to **NDI-over-USB** for ultra-low latency. Eliminated the need for OBS Studio as a bridge—the glasses now appear as a native camera source in Teams via NDI Virtual Input. Phase 5 is officially signed off.

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

## Phase 5 — Polish & NDI Migration (COMPLETE) ✅

Successfully pivoted from SRT to NDI-over-USB to achieve ultra-low latency and native camera support in Teams.

### 5.1 Connection state machine ✅
- [x] Formalize states: `Idle → Registering → AwaitingPermission → Starting NDI → Live → Paused → Reconnecting → Error → Stopped`
- [x] Drive UI off a single source of truth (AppState enum)
- [x] Surface NDI source name in-app for verification

### 5.2 NDI-over-USB Implementation ✅
- [x] Integrate NDI iOS SDK with C-bridging header
- [x] Implement high-performance GPU conversion (YUV/NV12 to BGRA) via CIContext
- [x] Optimize frame handoff with explicit stride/pitch management (fixes skewing)
- [x] Broadcast as "Meta Glasses" over the USB-tethered network

### 5.3 Thermal & battery handling ✅
- [x] Subscribe to `ProcessInfo.thermalStateDidChangeNotification`
- [x] At `.serious`: drop framerate (thermalFrameDropRatio), show warning banner
- [x] At `.critical`: pause NDI stream, set `AppState.paused`, show modal
- [x] Subscribe to battery level notifications; warn <20%, prompt <10%
- [x] Non-blocking banners for thermal/battery/overheat hints

### 5.4 Git LFS Integration ✅
- [x] Configure Git LFS for large SDK binaries (`libndi_ios.a`)
- [x] Clean history to ensure large files are handled as pointers

**Phase 5 exit criterion:** Successfully achieved 100ms latency stream from glasses to Teams via NDI Virtual Input without needing OBS Studio.

## Phase 6 — Distribution and feedback

- [ ] TestFlight build for phone app
- [ ] Whitelist test accounts under Meta preview constraints
- [ ] Add telemetry: drop rate, latency, reconnect counts
- [ ] Decide on broader rollout once Meta preview opens
