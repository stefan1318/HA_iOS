# STEVORA iOS release acceptance

This checklist is **not** automatically satisfied by an unsigned IPA or a simulator build.
Record a tester, STEVORA OS version, iOS version, date, and evidence for each item.

## Automated gates
- [ ] CI lint and iOS unit tests pass on the release commit
- [ ] STEVORA identity: bundle ID, app name, icon, launch screen and entitlements reviewed
- [ ] BG/EN resources and localized room/device custom names validated
- [ ] Release IPA artifact includes SHA-256 checksum and source commit SHA
- [ ] Version and release notes correspond to the exact tested commit

## STEVORA OS compatibility
- [ ] Login and logout against independent STEVORA OS server
- [ ] HTTP connection works when explicitly configured; HTTPS connection works when enabled
- [ ] Manifest is discovered and parsed without losing rooms/devices
- [ ] Room renames and device custom names synchronize in BG/EN
- [ ] Device permissions and user role restrictions are respected
- [ ] Token/session restoration works after force quit and restart
- [ ] Server unavailable, offline recovery, and re-authentication tested

## Real-device acceptance
- [ ] Signed IPA provisioned with **STEVORA-owned** Apple team/certificates
- [ ] Install and launch on physical iPhone
- [ ] Fresh onboarding and existing session restore verified
- [ ] Device control and background/resume behavior verified
- [ ] Crash logs reviewed and release approved by tester

## Rollback
1. Keep the previous tested IPA and its checksum available.
2. Do not merge or release if any mandatory check is incomplete.
3. On regression, restore the prior known-good tagged release and verify login, room/device sync, and session restore.
4. Record affected STEVORA OS and iOS versions before re-enabling distribution.
