# Meta Glasses to Teams Video Stream (NDI-over-USB)

Streams live video from Meta Ray-Ban AI glasses into Microsoft Teams meetings with ultra-low latency using NDI over a USB-tethered connection.

## Architecture

```
Meta Ray-Ban Glasses
        ↓ (Bluetooth)
   iOS Phone App       ← Meta Wearables SDK
        ↓ (SRT - Secure Reliable Transport)
   OBS Studio (macOS)
        ↓ (Virtual camera)
   Microsoft Teams
```

## Repo structure

```
ios-app/          # Swift iOS app — captures glasses video via Meta SDK and pushes via SRT
docs/             # Architecture notes, ADRs, setup guides
```

## Phase 0 decisions

| Decision          | Choice               |
|-------------------|----------------------|
| Mobile platform   | iOS (Swift 6)        |
| Teams integration | Virtual camera       |
| Hardware          | Mock Device Kit first |

## Getting started

See [PLAN.md](PLAN.md) for the full phased plan.

## Requirements

- iOS 15.2+ device
- Meta AI app installed and glasses paired (or Mock Device Kit)
- OBS Studio on macOS with an SRT input source configured (acts as the virtual camera bridge into Teams)
- Microsoft Teams account
