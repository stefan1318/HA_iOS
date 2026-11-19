# STEVORA iOS — product build and release gate

The product development branch is `feature/stevora-ios`. The manifest-sync
branch is an integration workstream, not an independently releasable STEVORA
application. Do not distribute upstream Home Assistant simulator artifacts as
STEVORA IPA files.

## Required checks before AltStore distribution

- [ ] Verify STEVORA app name, bundle identifier, launcher and splash assets.
- [ ] Verify native STEVORA navigation, device control, OAuth and voice behavior.
- [ ] Port and validate manifest discovery from the integration workstream.
- [ ] Compile for `iphoneos` (not `iphonesimulator`).
- [ ] Verify resulting IPA Payload/*.app, executable architectures, Info.plist
      identity and minimum iOS version.
- [ ] Confirm signing/entitlements compatibility with AltStore on Windows.
- [ ] Physical iPhone installation and regression tests.

The default-branch AltStore workflow now checks out `feature/stevora-ios`
and refuses to publish an IPA if product branding cannot be verified.
A green simulator test is not a device-installable STEVORA release.
