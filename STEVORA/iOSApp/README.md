# STEVORA iOS — Beta 2 development candidate

Native SwiftUI STEVORA app built independently with XcodeGen, minimum iOS 16.4.

## Implemented in source
- BG/EN branded dark UI, STEVORA monogram app icon and launch storyboard.
- Native devices, lights, climate, scenes, favorites, quick home temperature/humidity summary.
- Home Assistant REST service calls and event-driven WebSocket state changes with reconnect.
- OAuth2 authorization-code with PKCE via ASWebAuthenticationSession, access/refresh token Keychain storage and refresh on REST 401.
- Development-only long-lived token fallback, to be removed after OAuth device verification.
- Native Assist text chat via /api/conversation/process and iOS Speech microphone transcription.
- Provisional room filter based on entity names, NOT Home Assistant area registry.
- Backlight controls hidden, no backlight power state changed.

## Important limitations and release blockers
- This is a **development candidate**, not a tested or published Beta 2. Confirm GitHub Actions device and simulator builds, then test on a physical iPhone.
- OAuth redirect/client_id compatibility must be verified against the actual Home Assistant instance. Session expiration during WebSocket operation requires further work.
- Voice transcription is push-to-talk, NOT wake-word listening; Home Assistant conversation agent must be configured.
- The app icon is a generated STEVORA S monogram, not the final approved original STEVORA brand artwork. Replace with the original vector/PNG before release.
- True room/area mapping, accessibility audit, full color/light controls, security audit, app lifecycle and background reliability, tests and TestFlight distribution remain pending.
- Unsigned IPA requires AltStore/Apple signing. No app-store production signing is included.
- All network access requires valid HTTPS trust. Never disable TLS verification.

## Build
The device workflow generates a PNG icon using Swift/AppKit on the macOS runner, generates the Xcode project with XcodeGen, builds an unsigned iOS app and uploads an unsigned IPA.
