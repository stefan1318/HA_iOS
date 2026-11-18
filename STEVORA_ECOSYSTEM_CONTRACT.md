# STEVORA Ecosystem — iOS integration contract

Status: adopted from the Android contract on 2026-11-18. Product stream: [STE-03] iOS. Shared architecture: [STE-00]. Evidence and releases: [STE-06].

## Product boundaries
Home Panel, Android Companion, iOS Companion and Hey Stevora are separate products sharing STEVORA branding and secure Home Assistant interoperability. Do not assume undocumented endpoints. Cross-product schema/API changes require specification and compatibility testing.

## Required behavior
1. **Update continuity:** preserve iOS bundle identifier, secure credentials, Home Hub URL, language, favorites and permission choices across updates. Do not require uninstall or reset. AltStore re-signing and device upgrade need manual verification.
2. **Security and consent:** use Home Assistant OAuth/2FA and HTTPS certificate validation; never embed or log credentials; honor account roles and permissions; explicitly confirm destructive or security-sensitive AI actions.
3. **Reliable state:** authoritative live Home Assistant states; indicate disconnection; do not fabricate readings. When disconnected, only show last-known values as offline/read-only and block device commands.
4. **Device scope:** expose supported and authorized entities. Never operate or expose lamp backlight controls; they must remain ON. Do not assume the developer's device IDs or rooms.
5. **Climate and lighting:** 1°C temperature steps for configured climate devices, RGB/brightness only when supported.
6. **Presentation:** approved STEVORA logo, premium dark theme, BG/EN localization, accessible controls and navigation.
7. **Voice/AI:** Hey Stevora wake word is planned, not released. Explicit microphone/speech consent; transparent recording state; role-verified Assist pipeline, no privilege escalation.
8. **Distribution:** CI success is not device acceptance or Stable release. Record commit, run, artifact, signing, on-device upgrade and test outcomes.

## Evidence
Use planned / implemented / tested / released distinctly. Static gate checks source invariants only; manual security, OAuth, offline, permission and device acceptance are required.

## Upstream contribution policy
The repository also carries the Open Home Foundation AI_POLICY.md. Human review and understanding are required for upstream contributions; do not autonomously submit upstream PRs/issues or unreviewed messages.
