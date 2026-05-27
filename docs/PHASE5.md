# Phase 5 — Polish & NDI Migration (COMPLETE) ✅

_Status: Complete. Successfully pivoted from SRT to NDI-over-USB for ultra-low latency._

## Goal

Take the glasses streaming pipeline from a high-latency SRT/OBS setup to a professional, ultra-low latency **NDI-over-USB** solution that appears as a native camera in Microsoft Teams.

## Final Architecture

```
Meta Ray-Ban Glasses
        ↓ (Bluetooth)
   iOS Phone App       ← Meta Wearables SDK + NDI SDK
        ↓ (NDI - Network Device Interface)
   USB-Tethered Connection
        ↓ (NDI Virtual Input)
   Microsoft Teams (Native Camera Source)
```

## Workstreams Completed

### 5.1 Connection state machine ✅

Centralized the app's lifecycle in a single explicit state machine:

```
Idle
  → Registering          (user taps "Connect")
  → AwaitingPermission   (Meta AI handoff)
  → Starting NDI         (Handshake to local NDI hub)
  → Live                 (Frames flowing)
  → Paused               (Thermal critical)
  → Reconnecting         (Transient drop)
  → Error                (Unrecoverable)
  → Stopped              (User-initiated)
```

**Achievements:**
- Promoted to a Swift `enum` with associated values in `AppState.swift`.
- All UI affordances in `ContentView.swift` derive from the current state.
- Surface the NDI source name ("Meta Glasses") for verification on the Mac side.

### 5.2 NDI-over-USB Implementation ✅

- **Native NDI SDK**: Integrated the NDI iOS SDK (`libndi_ios.a`) and configured C-bridging.
- **GPU Conversion**: Implemented a high-performance `CIContext` render pipeline to convert the glasses' native YUV/NV12 frames into **BGRA** for NDI compatibility.
- **Stride Alignment**: Optimized memory mapping to ensure correct row bytes (stride), fixing previous "skewed" video artifacts.
- **USB Pathing**: Configured the stream to prioritize the USB-tethered network interface, achieving <100ms latency.

### 5.3 Thermal & battery handling ✅

- **Thermal Management**: 
    - Subscribed to `ProcessInfo.thermalStateDidChangeNotification`.
    - At `.serious`: drop framerate via `thermalFrameDropRatio` to reduce encoder load.
    - At `.critical`: pause NDI stream and show a modal alert for user recovery.
- **Battery Monitoring**:
    - Warning banner at <20%.
    - Modal prompt to stop at <10%.
- **Glasses Thermal Proxy**: Surfaces a "glasses may be warm" hint based on frame-pacing irregularities detected in the Meta SDK stream.

### 5.4 Git LFS Integration ✅

- Since the NDI library (`libndi_ios.a`) is 127MB, the project was migrated to use **Git LFS**.
- Repository history was cleaned using `git lfs migrate` to ensure small clones for other developers.

## Results

A non-technical user can now:
1. Connect iPhone to Mac via USB.
2. Tap "Connect" in the app.
3. Select "Meta Glasses" in **NDI Virtual Input** on the Mac.
4. Use the glasses as a **native camera** in Teams settings.

**Exit criterion met:** Ultra-low latency (<100ms), no OBS Studio required, stable for 60+ minute meetings.
