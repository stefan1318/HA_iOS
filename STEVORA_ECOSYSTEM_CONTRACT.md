# STEVORA Ecosystem — iOS integration contract

Status: adopted from the Android contract on 2026-11-18. Product stream: [STE-03] iOS. Shared architecture: [STE-00]. Evidence and releases: [STE-06].

## Superseding product boundaries — approved 2026-11-20

**STEVORA Ecosystem = STEVORA OS + STEVORA App for Android + STEVORA App for iOS.**

STEVORA iOS is a **native client of STEVORA OS**, not a separate Home
Assistant system. The OS is the single source of truth for signed-in users,
homes, rooms, entities, capabilities, shared names, BG/EN localization,
permissions, profiles, assistant availability, package entitlements and
manifest revisions. iOS displays and controls those data through a versioned
authenticated STEVORA OS API and keeps only platform-specific settings locally.

Stevora Core, Stevora Universal Integration, Stevora Home Panel 7.1.1
Premium, Stevora Home Hub, Stevora Frontend, Stevora People & Presence and
Stevora Manifest are **integrated components of STEVORA OS**. They are not
separate user products or separately installed client-side dependencies.
Every new common feature and shared UI specification is part of STEVORA OS.
iOS uses native Apple design and platform permissions to expose the
compatible system features; it must not invent its own device model.

**Hey Stevora is a built-in OS/Android/iOS feature**, not a separate
customer-installable assistant product. It uses the actual configured
and installed STEVORA OS voice and/or AI assistants, subject to customer
choice and purchased package entitlement. OS permissions and consent
cannot be bypassed by paid features. A missing provider or unsupported
background/wake word mode is shown as unavailable, never as active.

**STEVORA Memory & Sync** is a **private optional STEVORA OS extension
for the owner's homes only**. It is not bundled into public iOS or OS
distribution, is disabled by default, and does not create public sync
or private cross-home access for normal customers.

Existing direct HA WebSocket/OAuth transport remains a **temporary legacy
compatibility path only** until native OS APIs are built, migrated and
tested. Preserve app upgrade continuity, OAuth/HTTPS, valid permissions
and reliable offline behavior; do not claim OS API integration shipped
on the strength of this document alone.

OS API changes require a versioned specification and Android/iOS
compatibility tests. No silent breaking changes.

## Required behavior
1. **Update continuity:** preserve iOS bundle identifier, secure credentials, Home Hub URL, language, favorites and permission choices across updates. Do not require uninstall or reset. AltStore re-signing and device upgrade need manual verification.
2. **Security and consent:** use Home Assistant OAuth/2FA and HTTPS certificate validation; never embed or log credentials; honor account roles and permissions; explicitly confirm destructive or security-sensitive AI actions.
3. **Reliable state:** authoritative live Home Assistant states; indicate disconnection; do not fabricate readings. When disconnected, only show last-known values as offline/read-only and block device commands.
4. **Device scope:** expose supported and authorized entities. Never operate or expose lamp backlight controls; they must remain ON. Do not assume the developer's device IDs or rooms.
5. **Climate and lighting:** 1°C temperature steps for configured climate devices, RGB/brightness only when supported.
6. **Presentation:** approved STEVORA logo, premium dark theme, BG/EN localization, accessible controls and navigation.
7. **Voice/AI:** Hey Stevora is the approved built-in target across STEVORA OS, iOS and Android, using installed OS assistant pipelines and customer entitlements. Native voice/wake word implementation is not yet released. Explicit microphone/speech consent; transparent recording state; role-verified Assist pipeline, no privilege escalation.
8. **Distribution:** CI success is not device acceptance or Stable release. Record commit, run, artifact, signing, on-device upgrade and test outcomes.

## STEVORA OS client release gate

- The selected STEVORA OS server provides user-scoped rooms/entities/controls, display categories, labels, assistant pipelines, permissions and package capabilities.
- iOS is a client of the OS; phone-specific settings remain platform-local without replacing server-side source of truth.
- Android/iOS parity checks cover shared OS settings, device discovery, assigned rooms and real-time permissions across at least two different installations.
- Hey Stevora UI and actions are available only for actually installed voice/AI providers and the user's allowed plan; native platform audio behavior remains consent- and OS-gated.
- Never ship owner-only Memory & Sync as a public iOS capability.
- Existing signed/bundle in-place updates and manual security, OAuth, offline and native device checks remain required.

## Evidence
Use planned / implemented / tested / released distinctly. Static gate checks source invariants only; manual security, OAuth, offline, permission and device acceptance are required.

## Upstream contribution policy
The repository also carries the Open Home Foundation AI_POLICY.md. Human review and understanding are required for upstream contributions; do not autonomously submit upstream PRs/issues or unreviewed messages.
