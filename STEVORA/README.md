# STEVORA Companion iOS — implementation track

This is the STEVORA iOS development branch of the Home Assistant Apple Platforms fork. **Not a released IPA**.

## Source of truth
- Android source: https://github.com/stefan1318/Ha_android/tree/feature/stevora-companion
- iOS upstream: https://github.com/home-assistant/iOS
- Reuse Android's approved branding, navigation structure, labels, and device behavior; reimplement in Swift/SwiftUI, do not copy Android Kotlin code.
- Preserve original STEVORA logo, never invent a replacement.
- Existing STEVORA Home **custom panel** is not a Lovelace dashboard.
- Support Bulgarian and English.
- Preserve secure Home Assistant authentication, token storage, TLS validation and upstream attribution.

## Release gates
1. Audit the **actual Android stable release commit/tag** and verify screens, menus, onboarding, navigation, and behavior. The old STEVORA_IMPLEMENTATION.md is a specification, not proof of the final Android release.
2. Extract the original approved logo and colors from the final Android release.
3. Build iOS native navigation and HA API client, including authenticated onboarding, reconnect, recovery and logout.
4. Validate real HA device controls, state subscription, climate, lights, HomePod sensors, error handling and permissions.
5. Test on iOS Simulator, then physical iPhone; audit all entitlements and privacy descriptions.
6. Set STEVORA-specific bundle identifiers and signing settings; obtain Apple signing/provisioning before distributing an installable IPA.
7. Verify release build, crash-free onboarding, BG/EN, accessibility, background behavior, app coexistence and license notices.

## CI
The upstream CI remains available. The STEVORA Swift package contains portable, independently testable core models. Its CI is **not** a substitute for compiling the entire iOS application.

## Current status
- iOS fork and feature branch established.
- Standalone native Swift domain models started.
- No production-ready app, no signed IPA, no device installation yet.
