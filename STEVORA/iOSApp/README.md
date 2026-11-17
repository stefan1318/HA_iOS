# STEVORA iOS native prototype

This is an **independently buildable SwiftUI prototype inside the Home Assistant iOS fork**. It is not yet wired into the upstream HomeAssistant.xcodeproj app targets.

## Build
Run the GitHub workflow `STEVORA native iOS simulator build` on `feature/stevora-ios`. It installs XcodeGen, generates `StevoraCompanion.xcodeproj`, and runs an unsigned simulator build. A successful artifact is for **iOS Simulator only**, not installation on a physical iPhone.

## Implemented
- Dark STEVORA-inspired navigation with Home, Devices, Climate, Lights, Settings
- BG/EN UI, HTTPS server address, development-only long-lived access token in iOS Keychain
- Live REST states refresh and service calls for light/switch/fan/climate
- Temperature/humidity sensor visibility when Home Assistant exposes the entities
- Logout, network errors, manual refresh

## Not production ready
- This implementation is not a port of the complete Android stable UI; final Android assets/screens must be audited and matched.
- Authentication currently uses a **manual long-lived token** for development. Before public release integrate Home Assistant OAuth2 authorization code + PKCE, safe redirect handling and token refresh using upstream Companion authentication.
- No original STEVORA icon asset has been imported. No fabricated logo should be shipped.
- No WebSocket live state subscription, native Assist, notifications, widgets, Siri, biometric unlock, location or background service.
- No signed device IPA, TestFlight build, Apple entitlement audit or completed end-to-end testing.
- Existing upstream iOS app continues to exist unchanged on main.

## Security
HTTPS required, no arbitrary HTTP transport exception; no credentials in Git. Only use development tokens on trusted servers and revoke test tokens after testing.

## Next release gate
Successful CI compile and simulator smoke test, then full integration with upstream iOS Companion OAuth and lifecycle, Android parity audit, Apple signing and real-device validation.
