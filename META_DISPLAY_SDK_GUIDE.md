# Meta Display SDK - Latest Guide (May 2026)

## Overview

Meta released developer preview access to the Meta Ray-Ban Display glasses display on May 14, 2026. This enables developers to build visual experiences on AI glasses already in the hands of real users. There are two primary development paths: the native Mobile SDK (Device Access Toolkit) and Web Apps.

## Two Development Paths

### Path 1: Meta Wearables Device Access Toolkit (Native Mobile SDK)

**Best for:** Extending existing iOS/Android apps to the glasses display with deep hardware integration.

#### Supported Platforms
- **iOS**: iOS 15.2+ with Swift
- **Android**: Android 10+ with Kotlin
- **Devices**: Ray-Ban Meta (Gen 1 & 2), Ray-Ban Meta Optics, Meta Ray-Ban Display

#### Display Components Available
- Text
- Images
- Lists
- Buttons
- Video playback

#### Device Capabilities
Beyond display, access to:
- Camera/video streaming
- Audio and microphones
- Open-ear audio
- Gesture input via Meta Neural Band (surface electromyography/EMG)

#### Key Features
- Deep hardware integration
- Hands-free experiences
- Natural wearer perspective
- Session and device management
- Permission handling
- Mock Device Kit for testing without hardware

#### GitHub Repositories
- **Android**: https://github.com/facebook/meta-wearables-dat-android
- **iOS**: https://github.com/facebook/meta-wearables-dat-ios

#### Latest API Version
- Current version: 0.7

#### Distribution
- Create organizations and manage projects
- Set up release channels for testing
- Support up to 100 testers via release channels
- Version management

#### AI-Assisted Development Support
- Claude Code integration
- GitHub Copilot support
- Cursor IDE support
- DAT MCP (Model Context Protocol) available
- AGENTS.md for agentic workflows

---

### Path 2: Web Apps

**Best for:** Building new standalone experiences with standard web technologies. Fast iteration and deployment.

#### Technology Stack
- Standard HTML/CSS/JavaScript
- No proprietary frameworks required
- No new languages to learn

#### Available Capabilities
- Meta Ray-Ban Display (MRBD) display rendering
- Input signals from Meta Neural Band
- MRBD Cap Touch controls
- Device motion/orientation data:
  - Accelerometer
  - Gyroscope
  - Compass
- User location (from connected mobile devices)
- Local storage

#### Development Workflow
1. Build and preview in browser (fast iteration)
2. Deploy to glasses via URL
3. Share with testers via password-protected URLs

#### Deployment & Testing
- Password-protected URL sharing
- No need for release channels or formal distribution
- Easy rapid prototyping
- Lightweight utilities and experimental interactions

#### GitHub Resources
- **Starter Kit**: https://github.com/facebookincubator/meta-wearables-webapp
- Includes AI coding tool integration

#### AI-Assisted Development Support
- Pre-loaded with agentic coding skills
- Compatible with:
  - Claude Code
  - Cursor IDE
  - GitHub Copilot
  - Other AI coding tools

---

## Supported Use Cases

With access to the display, developers can build:
- **Information overlays**: Real-time data displays, scores, status updates
- **Micro-apps and utilities**: Quick tools and experimental interactions
- **Streaming media**: Video playback and media consumption
- **Gaming**: Games and interactive experiences
- **Transit tools**: Navigation and travel assistance
- **Cooking guides**: Recipe assistance and kitchen utilities
- **Grocery lists**: Shopping and inventory management
- **Instrument practice**: Music learning aids

---

## Gesture Input: Meta Neural Band

Meta Ray-Ban Display glasses support gesture controls powered by **surface electromyography (EMG)** via Meta Neural Band, enabling:
- Subtle finger and hand movements
- Discrete, effortless input without touching or speaking
- Unique interaction model unavailable on other glasses

---

## Getting Started

### For Native Mobile SDK
1. Visit [Wearables Developer Center](https://wearables.developer.meta.com/docs/develop/dat/)
2. Set up iOS or Android project
3. Clone the appropriate GitHub repository
4. Integrate the SDK using Swift (iOS) or Kotlin (Android)
5. Use Mock Device Kit for testing without hardware
6. Create organization and manage release channels

### For Web Apps
1. Visit [Web Apps Documentation](https://wearables.developer.meta.com/docs/develop/webapps/)
2. Clone the [starter kit](https://github.com/facebookincubator/meta-wearables-webapp)
3. Build using HTML/CSS/JavaScript
4. Test in your browser
5. Deploy via URL to glasses

---

## Documentation & Resources

### Official Documentation
- **Main Developer Center**: https://wearables.developer.meta.com/docs/develop/
- **API Reference**: https://wearables.developer.meta.com/docs/reference/
- **Device Access Toolkit Docs**: https://wearables.developer.meta.com/docs/develop/dat/
- **Web Apps Docs**: https://wearables.developer.meta.com/docs/develop/webapps/
- **Support**: https://wearables.developer.meta.com/docs/support/

### API Reference by Platform
- **Android DAT**: https://wearables.developer.meta.com/docs/reference/android/dat/0.7
- **iOS DAT**: https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.7

### Blog & Announcements
- [Launch Announcement](https://developers.meta.com/blog/build-for-display-glasses/)

---

## Key Documentation Topics

### Device Access Toolkit Sections
- Getting started and setup
- Build integrations (iOS/Android)
- Display integration guide
- Icons and UI elements
- Session and device lifecycle management
- Permissions and registration
- Microphone and speaker management
- Mock Device Kit for testing
- AI-assisted development (Claude Code, GitHub Copilot, Cursor, MCP)
- Distribution and release channels
- Troubleshooting and known issues
- Version dependencies

### Web Apps Sections
- Setup and initialization
- Build guide and best practices
- Testing and deployment
- Troubleshooting
- AI coding plugin integration

---

## Hardware Requirements

### For Testing
- Ray-Ban Meta (Gen 1 or Gen 2)
- Ray-Ban Meta Optics
- Meta Ray-Ban Display (latest hardware)
- Connected mobile device (iOS 15.2+ or Android 10+)

### For Web Apps Testing
- Can test in browser before deploying to hardware
- Mock Device Kit available for DAT

---

## Distribution & Testing Limits (Developer Preview)

- **Device Access Toolkit**: Up to 100 testers via release channels
- **Web Apps**: Unlimited testers via password-protected URLs

---

## Current Status

The Meta Display SDK is in **Developer Preview** (as of May 2026). This means:
- All APIs and features are subject to change
- Beta versions available for integration
- Community feedback actively sought
- Regular updates expected

---

## Next Steps for Building Features

1. **Decide on approach**: Native mobile extension (DAT) or standalone web app
2. **Clone the appropriate starter repo** (GitHub links above)
3. **Review the API reference** for your platform
4. **Set up local development** using mock device kit or browser
5. **Reference the AI-assisted development docs** for your preferred tool
6. **Build and iterate** quickly with the chosen stack
7. **Test and share** with testers before wider launch

---

## Important Links Summary

| Resource | URL |
|----------|-----|
| Main Developer Hub | https://wearables.developer.meta.com/docs/develop/ |
| Device Access Toolkit Docs | https://wearables.developer.meta.com/docs/develop/dat/ |
| Web Apps Docs | https://wearables.developer.meta.com/docs/develop/webapps/ |
| Android DAT GitHub | https://github.com/facebook/meta-wearables-dat-android |
| iOS DAT GitHub | https://github.com/facebook/meta-wearables-dat-ios |
| Web Apps Starter Kit | https://github.com/facebookincubator/meta-wearables-webapp |
| API Reference | https://wearables.developer.meta.com/docs/reference/ |
| Support & Feedback | https://wearables.developer.meta.com/docs/support/ |

---

## Feature Ideas for Meta Display

Now that display is available, consider building:

1. **Real-time video streaming UI** - Use DAT to stream camera feed and overlay data
2. **Voice command interfaces** - Combine audio input with display feedback
3. **Navigation overlays** - Location-aware directions in the wearer's view
4. **Data dashboards** - Lists and real-time metrics for professional use
9. **AR-style annotations** - Using camera and display together
10. **Gesture-controlled menus** - Leverage Meta Neural Band for intuitive control

---

Last updated: May 30, 2026
