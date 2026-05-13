# Meta Ray-Ban Glasses → MS Teams Video Streaming

Project plan for an app that streams video from Meta Ray-Ban AI glasses into Microsoft Teams.

## Key constraints (from the Meta Wearables Device Access Toolkit)

- The SDK is **mobile-only** — iOS 15.2+/Swift 6 or Android 10+. The glasses pair to a phone over Bluetooth via the Meta AI app, so there is no direct desktop connection. The data path has to be: glasses → phone → relay → Teams.
- The toolkit gives **camera access** directly. **Microphone and speakers** come through standard iOS/Android Bluetooth profiles, not the SDK. Audio and video take different paths and have to be muxed by the phone app.
- A **Mock Device Kit** is available, so much of the work can proceed without owning glasses.
- Publishing is still restricted to "select partners" during developer preview. Broader publishing was promised for 2026 but is not confirmed open. Distribution will likely be limited to whitelisted test accounts for a while.
- Only available in markets where the AI glasses are sold.

## Teams integration paths

Three options with very different complexity:

1. **RTMP-In to a Teams Live Event / Town Hall.** Simplest. Push RTMP from the phone (or a small relay) and viewers see a broadcast. Downside: ~20–30s latency, broadcast-only, not a real meeting participant.
2. **Virtual camera into a regular Teams meeting.** Phone streams to a small desktop helper, which exposes the feed as a webcam to Teams. Low latency, works in any normal meeting. Requires a desktop companion.
3. **Media bot via Microsoft Graph Communications.** Glasses appear as a real meeting participant. Most powerful but heaviest: Azure-hosted bot, tenant admin consent, real-time media stack.

## Phased plan

### Phase 0 — Access and decisions (no code)

- Sign up at the Meta Wearables Developer Center; confirm preview eligibility.
- Pick mobile platform (iOS or Android) to start.
- Pick Teams integration path (one of the three above).
- If bot route, set up Azure tenant and an M365 dev tenant.
- Set up source control, a CI pipeline, and a project board.

### Phase 1 — Glasses capture working on a phone

- Install Meta SDK; get sample app running.
- Pair with Mock Device Kit (or real glasses if available).
- Replace sample preview with minimal UI: start/stop capture, render the live camera feed locally.
- **Exit criterion:** tap a button, see glasses video on the phone screen with the mock device.

### Phase 2 — Encode and stage a local stream

- Pull camera frames out of the Meta SDK; pipe to SRTHaishinKit (H.264 VideoToolbox).
- Mux in microphone audio (initially phone mic, later glasses mic via Bluetooth HFP/A2DP).
- Push to a local OBS Studio instance via SRT (Secure Reliable Transport).
- **Exit criterion:** end-to-end glasses → phone → OBS Studio → Teams Virtual Camera.

### Phase 3 — Public outbound stream (DEFERRED)

Deferred as of 2026-05-12. With OBS-on-LAN working end-to-end after Phase 2, hosted/cellular streaming is no longer on the critical path. The reliability pieces of this phase (reconnect logic, adaptive bitrate, stream-health UI) have been folded into Phase 5. Revisit hosted endpoints only when a use case requires the macOS host to be off the phone's local network.

### Phase 4 — Teams integration (path-dependent)

- *RTMP-In path:* create a Town Hall or Live Event, grab the ingest URL/key, stream from the phone app, verify attendees see the feed.
- *Virtual camera path (Chosen):* Use OBS Studio as the macOS companion. It receives the SRT stream and exposes it as a virtual camera to Teams. Select it as the camera in Teams.
- *Media bot path:* scaffold a Graph Calling/Media bot, deploy to Azure, handle the `joinCall` flow, feed the RTMP-decoded frames into the bot's media stack.

### Phase 5 — Polish

Take the working `glasses → SRT → OBS → Teams` pipeline from "works on my desk" to "Tim hands this to a colleague and they stream a full meeting without help." Five workstreams (full breakdown in `docs/PHASE5.md` and `TRACKER.md`):

1. **Connection state machine** — formalize `Idle → Registering → AwaitingPermission → Connecting → Streaming → Reconnecting → Error → Stopped`; drive UI off it; surface SRT URL/port in-app.
2. **Reconnect logic** (pulled from Phase 3) — detect SRT disconnects, exponential backoff (1s→2s→4s, cap 30s), preserve OBS-side session, clear "Reconnecting (N of M)…" UI.
3. **Thermal & battery handling** — react to `ProcessInfo.thermalStateDidChangeNotification` (degrade at `.serious`, pause at `.critical`) and battery thresholds (<20%, <10%). Note: glasses thermal isn't exposed by the SDK; we proxy via phone thermal + session duration.
4. **Permission & onboarding flows** — first-launch walkthrough; recovery paths if permissions revoked mid-session; clear re-register CTA on Meta-side de-authorization.
5. **End-of-stream summary** — duration, average bitrate, dropped frames, reconnect count; persist last N sessions.

**Note on dropped items:** the previous Phase 5 list included an "auth and meeting/event picker." With OBS as the bridge, Teams meeting selection happens entirely on the macOS side — the iOS app has nothing to pick. In-app sign-in would only be needed for telemetry, which fits Phase 6 better.

**Exit criterion:** a non-technical user can launch the app cold, get glasses streaming into Teams via OBS in under 60 seconds, recover from a typical Wi-Fi dropout without intervention, and see a meaningful session summary at the end.

### Phase 6 — Distribution and feedback

- TestFlight / Android internal track for the phone app.
- Whitelist test accounts under Meta preview constraints.
- Telemetry: drop rate, latency, reconnect counts.
- Decide whether to wait for broader Meta publishing before going wider.

## Top risks

1. **Audio path is the hardest part.** Glasses mic comes through Bluetooth, not the SDK. Muxing it with SDK video frames in proper A/V sync takes real work.
2. **Meta preview restrictions** mean we cannot ship publicly for an unknown stretch.
3. **Bot path complexity.** If the experience must be a real meeting participant (not a broadcast), the bot path is the only option and it roughly triples engineering effort.
4. **Latency expectations differ a lot by path:** bot ≈ <500ms, virtual cam ≈ 1–3s, Live Event ≈ 20–30s.

## Recommended defaults (pending confirmation)

- **Teams path:** Virtual camera in meetings — most useful day-to-day, low latency, avoids Azure bot complexity.
- **Mobile platform:** iOS — Meta SDK calls out Swift 6 explicitly, and the iOS RTMP/encoding stack is well-trodden.
- **Hardware:** Start on the Mock Device Kit so we are not blocked on glasses.

## Sources

- [Meta Wearables Device Access Toolkit FAQ](https://developers.meta.com/wearables/faq/)
