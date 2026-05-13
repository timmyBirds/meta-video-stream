# Phase 5 — Polish (detailed plan)

_Status: planned, not started. Drafted 2026-05-12._

## Goal

Take the working `glasses → iOS app → SRT → OBS Studio → Teams virtual camera` pipeline from "works on my desk" to "Tim hands this to a colleague and they can stream a full meeting without help."

## Entry state

- Phases 0–2 complete; Phase 4 effectively complete via the OBS pivot (commit `60d3315`).
- iOS app captures glasses video via the Meta Wearables SDK and pushes an SRT stream to a local OBS instance, which exposes a virtual camera consumed by Teams.
- Phase 3 (public outbound stream) deferred; its reliability work is pulled into 5.2 below.

## Workstreams

### 5.1 Connection state machine

Centralize the app's lifecycle in a single explicit state machine:

```
Idle
  → Registering          (user taps "Connect")
  → AwaitingPermission   (Meta AI handoff)
  → Connecting           (SRT handshake to OBS)
  → Streaming
  → Reconnecting         (transient SRT drop)
  → Error                (unrecoverable)
  → Stopped              (user-initiated)
```

Implementation notes:
- Promote to a Swift `enum` with associated values; expose as a `@Published` on `WearablesManager` (or a new `StreamCoordinator`).
- All UI affordances derive from current state — no ad-hoc booleans.
- Surface the SRT URL/port the app is pushing to so the user can verify against OBS without leaving the app.
- Each state has a user-facing copy string ("Waiting for OBS to accept the SRT stream…").

**Out of scope:** persisting state across cold launches. Crash recovery is a Phase 6 concern.

### 5.2 Reconnect logic (pulled from Phase 3)

- Subscribe to SRT disconnect events from HaishinKit.
- Exponential backoff: 1s, 2s, 4s, 8s, 16s, cap 30s.
- After 5 consecutive failures, transition to `Error` and prompt the user.
- Preserve the SRT session key/port across reconnects so OBS's source doesn't tear down.
- UI: "Reconnecting (attempt 3 of 5)…" with elapsed time.

Edge cases to design for:
- Phone goes to sleep mid-stream — distinguish from network drop.
- OBS quit on the macOS side — reconnect will fail until it's relaunched; surface a specific error string for this case.
- Wi-Fi → cellular switch — depends on whether OBS host is reachable on cellular at all (usually not on a home network). For now, treat as fatal.

### 5.3 Thermal & battery handling

**Thermal (phone-side only; glasses thermal is not exposed by the SDK):**
- Subscribe to `ProcessInfo.thermalStateDidChangeNotification`.
- `.nominal`, `.fair`: no action.
- `.serious`: drop bitrate (e.g. 4 → 2 Mbps) and framerate (30 → 24); show a non-blocking warning banner.
- `.critical`: pause stream, show modal alert, require user action to resume.

**Battery:**
- Subscribe to `UIDevice.batteryLevelDidChangeNotification` (requires `isBatteryMonitoringEnabled = true`).
- Under 20%: warning banner.
- Under 10%: modal prompt offering to stop.

**Glasses thermal proxy:** track stream duration and frame-pacing irregularities; if frames stall in a pattern consistent with glasses-side throttling, surface a "glasses may be overheating" hint. This is a soft signal — don't gate streaming on it.

### 5.4 Permission & onboarding flows

- First-launch walkthrough: 3–4 screens explaining why we need camera, Bluetooth, and the Meta AI registration handoff.
- Re-entrant: if permissions are revoked mid-session, return to the appropriate onboarding step with a "Open Settings" deep link.
- Handle Meta-side de-authorization (user revokes the app's wearables access in the Meta AI app) with a clear "Re-register with Meta" CTA, not a generic error.
- Edge case: first-launch on a device where the Meta AI app isn't installed — link to the App Store with copy explaining the dependency.

### 5.5 End-of-stream summary

On transition to `Stopped`:
- Duration
- Average bitrate (encoded), peak bitrate
- Dropped frames (encoder-side and SRT-side, separately if available)
- Reconnect count
- Highest thermal state observed

Persist the last 10 sessions in `UserDefaults` (small payload, no DB needed). Show a "Recent sessions" view from the home screen.

## Out of scope for Phase 5

- In-app Teams meeting picker (no longer needed with the OBS bridge).
- In-app sign-in / auth (deferred to Phase 6 if needed for telemetry).
- Hosted/cellular SRT endpoint (Phase 3, deferred indefinitely).
- Glasses-mic audio routing (still pending across phases; phone mic remains the audio source until we have a clear use case).

## Sequencing

| Week | Work |
|------|------|
| 1    | State machine (5.1) + reconnect logic (5.2). 5.1 lands first because 5.2 surfaces new states. |
| 2    | Thermal/battery handling (5.3) + UX polish on top of the state machine. |
| 3    | Permission flows and onboarding (5.4); end-of-stream summary (5.5). |
| 4    | Exit-criteria sign-off; doc cleanup; dogfood with one external tester. |

## Exit criterion

A non-technical user can:
1. Launch the app cold.
2. Get glasses streaming into Teams via OBS in **under 60 seconds**.
3. Recover from a typical Wi-Fi dropout **without touching the phone**.
4. See a **useful session summary** when they stop.

When all four hold for a tester who hasn't seen the app before, Phase 5 is done.
