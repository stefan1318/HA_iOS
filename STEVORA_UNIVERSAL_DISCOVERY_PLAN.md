# [STE-03] STEVORA iOS — Universal Home Discovery dependency
Status: planned; shared specification approved for sequencing, not implemented in this commit.

The shared contract is maintained in `stefan1318/stevora-memory-sync/UNIVERSAL_HOME_DISCOVERY_V1.md` ([STE-00]).

Implementation order:
1. Consume authenticated Home Assistant areas, devices, entities and live states; map controls by supported capabilities rather than creator-home IDs.
2. Support optional versioned STEVORA Home Panel metadata. Fallback to standard Home Assistant when missing/incompatible.
3. Scope local mapping overrides, cached readings and preferences by HA server and account; preserve OAuth/2FA and HTTPS.
4. Use dynamic rooms and available domains; missing lights/climate/voice must not break UI.
5. Test distinct homes, account switching, offline states and BG/EN before marking implemented/tested.

Do not infer that existing iOS onboarding discovery already implements STEVORA universal UI discovery.
