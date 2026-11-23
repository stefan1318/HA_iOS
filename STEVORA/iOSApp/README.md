# STEVORA iOS for OS Dev4

The native SwiftUI target lives in this folder. XcodeGen builds `com.stevora.companion.ios` for iOS 16.4 and later. The device workflow packages an unsigned IPA for development signing.

## Home and settings

Sign in to the selected home using OAuth and MFA. HTTPS uses normal certificate validation. Local HTTP requires explicit consent and a private IPv4 address. Rooms, device names, available controls, account role and assistant selection come from the authenticated home. Device details and climate history use the permitted entities. A device profile can restrict its controls further, including to an empty list.

The app reads the Dev4 profile language on connection. Changing the language in Settings saves BG or EN to the current OS profile. Open STEVORA OS from Settings for the full system and account catalog.

## iPhone presence

In Settings, enable **Share location** and grant the iOS location permission. This registers the iPhone with the selected home's Mobile App integration on the current user's account. The registration credential is kept in Keychain. Background updates have a separate switch and require **Always** access in iOS. Updates rely on network reachability and the location delivery iOS permits. Turning off sharing stops collection and further uploads. Switch accounts or homes to manage consent for each independently.

## Device acceptance

Verify an upgrade on a signed iPhone, OAuth and MFA, local HTTP and trusted HTTPS, allowed and read-only accounts, translated names after a live profile edit, offline/reconnect, foreground and background location reports, permission withdrawal and two independent homes. A successful unsigned build does not establish these results.
