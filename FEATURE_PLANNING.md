# Next Feature Planning: Meta-Video-Stream (Phase 6+)

_Last updated: May 30, 2026_

## Current State Summary

**Completed:** Phases 0–5
- Ultra-low latency (<100ms) NDI-over-USB streaming from Meta Ray-Ban glasses to Microsoft Teams
- Robust state machine, thermal/battery handling, reconnection logic
- App appears as native camera source in Teams via NDI Virtual Input
- Ready for Phase 6: Distribution and telemetry

**Current Tech Stack:**
- iOS 15.2+ with Swift 6
- Meta Wearables Device Access Toolkit (DAT) v0.7
- NDI SDK for native camera streaming
- No external dependencies (OBS Studio eliminated in Phase 5)

---

## New Capability: Meta Ray-Ban Display (May 2026)

The **Meta Display** (glasses screen/visual output) became available to developers on **May 14, 2026**. Your project currently uses **only the camera**—the glasses' visual output is untapped.

### What the Display enables:

**Display Components:**
- Text, Images, Lists, Buttons, Video playback

**Input Methods:**
- Meta Neural Band (EMG wristband) for gesture input
- MRBD Cap Touch controls
- Device motion (accelerometer, gyroscope, compass)

**Supported Use Cases:**
- Information overlays
- Real-time data dashboards
- Hands-free UI control
- Navigation/status displays
- Gesture-controlled menus

---

## Recommended Roadmap

### Phase 6 — Distribution & Telemetry (Current, ~1-2 weeks)

**Goals:** Get the core app into early tester hands; gather usage data.

**Tasks:**
1. TestFlight build for iOS app
2. Set up telemetry pipeline (frame drops, latency, reconnect counts)
3. Whitelist test accounts under Meta preview constraints
4. Create user feedback loop (Slack/email)
5. Document known issues and troubleshooting

**Exit criterion:** 5–10 testers running the app successfully in real Teams meetings; telemetry flowing to analytics backend.

---

### Phase 7 — User-Entered Video URL on the Meta Display (~1 week)

**Goal:** Let the user type an MP4 URL and play it on the Meta Ray-Ban Display, by repurposing the existing "Watch Video on Glasses" real-estate that today plays a single hard-coded demo clip.

> Full detail lives in [PHASE_7_PLAN.md](PHASE_7_PLAN.md). Verified against full source + official DAT v0.7 docs. Summary below.

**Reality check (verified):** most of the plumbing already exists, and the hard part is the constraints, not the pipeline. Display is fully integrated (`addDisplay()` at connect, `DAMEnabled` already true, `.watchingVideo` state, `startWatchingVideo(url:)`/`stopWatchingVideo()`), and the SDK fetches/decodes the URL itself via `VideoPlayer(provider:.uri(url), codec:.mp4)`. So there's no DAM migration and no phone-side transcode (earlier drafts were wrong on both).

**The defining constraint:** the display video player accepts MP4 only, https only, and max 400px per side / 70,000 total pixels. That cap is tiny, a 720p video is ~25x over it; the demo clip is 266x150 (≈39,900 px) precisely to fit. So this is "play a small, pre-sized MP4 clip," not "play any internet video." `codec: .mp4` being hard-coded is correct.

**The real work** is validation and error handling, not playback. Today the code ignores the SDK's `onError`/`onPlaybackEvent` signals and the `DisplayError` enum, the `videoError` UI is never populated, and a bad URL tears down the whole session.

**Design note:** camera (NDI) and video are mutually-exclusive modes (both require `.connected`), not a dual stream. Plan keeps that model.

**Milestones (see plan for exit checks):**
- M1 — URL `TextField` + `@AppStorage("glassesVideoUrl")` in the existing button block (default to demo URL); helper text stating MP4/https/400px/70,000px limits.
- M2 — Client-side validation (https scheme, .mp4, optional `AVURLAsset` dimension pre-check) before sending.
- M3 — Wire `VideoPlayer(onError:)` + `display.onPlaybackEvent` + `DisplayError` into a published `videoError`; make the existing inline error UI actually work.
- M4 — Stop tearing down the session on a video error; return to `.connected` and allow retry; dedupe `startWatchingVideo` vs unused `playVideoOnGlasses`.
- M5 — State/lifecycle polish: optional `.watchingVideo(url:)`; decide whether thermal/battery (which today gate on `isActive`, excluding `.watchingVideo`) should cover playback.
- M6 — Mock-device tests + docs (document the constraints prominently).

**Exit criterion:** User enters an MP4 URL, taps Watch Video, it plays on the display; URL persists; an invalid/oversized/unreachable URL produces a clear inline error and the glasses stay connected.

**Note:** `onPlaybackEvent`, `VideoPlaybackError`, and `DisplayError` cases are preview-stage (v0.7); reconfirm against the iOS DisplayAccess sample before finalizing M3. Whether clips carry audio is unconfirmed, treat as out of scope.

---

## Feature Ideas (Future Phases)

These are additional features enabled by the Meta Display and Neural Band, recommended for post-Phase-7 implementation.

### Idea A — In-Glasses Status Display

**Goal:** Display lightweight streaming status and meeting info directly on the glasses, reducing phone glancing.

**Rationale:**
- Hands-free verification ("am I still streaming?")
- Wearer sees meeting participant count without unlocking phone
- Natural gaze feedback for environmental awareness
- Lightweight status overlay doesn't interfere with video playback

**Components:**
- Show stream status badge (Live/Reconnecting/Paused) on glasses corner
- Display FPS counter and thermal warnings
- Auto-hide after 5s idle; re-show on state change
- Integrate with `MWDATDisplay` status rendering

---

### Idea B — Gesture Control via Meta Neural Band

**Goal:** Enable pause/resume streaming without touching the phone—just wrist gestures.

**Rationale:**
- Hands-free streaming control during presentations/meetings
- More professional than fumbling with phone mid-meeting
- Unique interaction model unavailable on other glasses

**Gestures:**
- **Pinch**: pause/resume streaming
- **Swipe up**: show status on glasses
- **Swipe down**: stop streaming (with confirmation)

**Components:**
- Integrate `MWDATInput` (gesture API from Meta Neural Band)
- Haptic feedback via iOS Haptics engine on successful gesture
- Gesture state machine to prevent duplicate commands

---

### Idea C — Meeting Context on Glasses

**Goal:** Surface Teams meeting info (participant list, meeting name) directly on glasses display.

**Rationale:**
- Wearer knows who's watching and meeting status at a glance
- Reduces context-switching between phone/glasses/Teams desktop
- Complements video playback and status overlays

**Components:**
- Teams Graph API integration for participant list
- Compact display card with meeting name + participant count
- Local caching for offline resilience
- Auto-update when participants join/leave

---

### Idea D — Advanced Telemetry & Analytics Dashboard

**Goal:** Build an analytics backend to track stream health, user behavior, and platform gaps.

**Rationale:**
- Understand where the product breaks in the wild
- Decide on broader rollout once Meta preview opens
- Identify latency, reliability, and user behavior patterns

**Components:**
- Client-side telemetry: frame drops, bitrate, reconnects, thermal events, battery snapshots
- Server-side aggregation via CloudKit or Firebase
- Web dashboard showing success rates, per-user session history, thermal/battery trends
- Alert on high error rates or new device failures

---

## Risk & Opportunity Assessment

### Phase 7 Specific Risks
1. **AVPlayer latency:** Streaming to glasses over wireless may introduce latency. Test with both local video and remote streaming.
2. **Meta Display video codec support:** Verify which video formats MWDATDisplay supports; may not support all MP4/WebM profiles.
3. **Bandwidth:** Simultaneous NDI stream (camera to Teams) + video stream (URL to glasses) requires robust phone/network handling.
4. **URL validation:** Malformed or unreachable URLs need graceful error handling without crashing or freezing the app.

### General Opportunities
1. **First dual-screen capability:** Few apps yet stream camera to one destination (Teams) and video to another (glasses).
2. **Presenter use case:** Content creators can use glasses as a monitor while presenting on Teams.
3. **Accessibility:** Wearer sees notes/captions on glasses while meeting participants see clean camera feed.

### General Risks
1. **Meta Display is brand new:** APIs may shift in developer preview. Phase 7 locks in early learning.
2. **Audio path remains hard:** You've solved video output, but glasses audio input (Bluetooth HFP/A2DP) is still separate from the display—Phase 7 doesn't solve audio muxing.
3. **Distribution limits:** Meta preview caps at 100 testers per release channel. Complete Phase 6 before scaling Phase 7.

---

## Recommended Sequence

**Immediate (Next 1–2 weeks):**
1. **Complete Phase 6** — get core app into TestFlight, enable telemetry, gather early feedback.

**Near-term (Weeks 3–5):**
2. **Start Phase 7** — video URL streaming to glasses. High value, unlocks new use cases (presenter mode). Proves MWDATDisplay video rendering at scale.

**Mid-term (Weeks 6+):**
3. **Pick from Ideas A–D** based on Phase 6 feedback:
   - **Idea A (Status Display)**: Low risk, pairs well with Phase 7 (show video playback state on corner).
   - **Idea B (Gesture Control)**: Hands-free pause on video playback.
   - **Idea C (Meeting Context)**: Requires Teams API; independent of video streaming.
   - **Idea D (Analytics)**: Essential for production rollout decision.

---

## Architecture Notes for Phase 7

**New components:**
- `GlassesVideoManager.swift` — manages video loading, playback, and glasses display rendering
- Extend `AppState` or create `VideoState` enum for playback lifecycle
- Update `ContentView` with video URL input UI

**Modifications:**
- `WearablesManager`: Add property `let glassesVideo = GlassesVideoManager()` to coordinate with NDI stream
- No changes to `NDIStreamManager` (camera stream stays independent)
- No changes to thermal/battery logic (applies equally to video streaming)

**Architecture principle:**
- **Dual-stream independence**: NDI camera stream and glasses video stream are fully independent. Both can fail or succeed without affecting the other.

---

## Key Meta SDK Resources for Phase 7

| Feature | SDK | Docs | GitHub |
|---------|-----|------|--------|
| Display rendering (video) | MWDATDisplay | [Device Access Toolkit Docs](https://wearables.developer.meta.com/docs/develop/dat/) | [iOS DAT](https://github.com/facebook/meta-wearables-dat-ios) |
| Device lifecycle | MWDATCore | [Device Access Toolkit Docs](https://wearables.developer.meta.com/docs/develop/dat/) | [iOS DAT](https://github.com/facebook/meta-wearables-dat-ios) |

**Testing resources:**
- Apple's HLS test streams for validating video playback: `https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/manifest.m3u8`
- Mock Device Kit for testing without hardware

---

## Next Actions

1. **Review Phase 7 plan.** Validate video format support in MWDATDisplay and AVPlayer latency expectations.
2. **Assign Phase 6 sprint.** TestFlight + telemetry pipeline should complete by June 10.
3. **Spike Phase 7 (mid-June).** Test MWDATDisplay video rendering and AVPlayer integration with mock device.
4. **Validate Ideas A–D.** Based on Phase 6 feedback, prioritize post-Phase-7 roadmap.

