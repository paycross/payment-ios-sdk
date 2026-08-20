# CocoaPods publish: making payment-ios-sdk public and shipping PayCross 0.1.0

Date: 2026-08-20
Status: approved (design); implementation not started

## Why now

The Flutter plugin's podspec depends on `PayCross (= 0.1.0)`, which has never been
published — the plugin's iOS CI only works today through an interim sibling-checkout
override (paycross-flutter PR #8, teardown tracked in paycross-flutter issue #9).
CocoaPods trunk goes read-only on 2026-12-02, and trunk pod names are
first-come-first-served. Publishing requires the source repo to be publicly
clonable, because trunk stores only the podspec and every `pod install` clones the
repo at the release tag.

Two permanences drive the sequencing below: a published version can never be
cleanly recalled, and flipping the repo public exposes its entire git history.

## Decisions (settled with the owner, 2026-08-20)

| Decision | Choice |
|---|---|
| Scope | Do-it-right: everything below ships in 0.1.0, nothing deferred to "after" |
| Public history | Fresh-start squash: one clean initial commit; full history archived privately |
| Where | Same repo (`paycross/payment-ios-sdk`), `main` force-replaced at cut-over |
| License | MIT (LICENSE file + both podspecs' `s.license`) |
| First version | `0.1.0` (independent of Android's 0.3.x line) |
| Community posture | Issues enabled; SECURITY.md pointing at GitHub private vulnerability reporting until `security@pay-cross.com` exists (io.paycross issue #868) |
| Trunk ownership | Register with the owner's personal email now; `pod trunk add-owner` a team address later |

## Workstream 1 — code readiness (private repo, current history)

All items are ordinary PRs into `main` before the cut-over.

1. **3DS fixes land.** The other active session holds uncommitted 3DS work. Hard
   gate; owned outside this spec. Nothing below force-replaces history until this
   is merged and that session confirms it is done.
2. **API surface demotion.** `PayCrossCore` currently exposes wire and transport
   types (`BrowserInfo`, `SubmitCardRequest`, `PayCrossAPIClient`, …) as `public`
   solely so the `PayCross` module can use them. Demote them to `package` so the
   published API surface is only the intended one (sheet API, environment,
   results, prefill). *Spike first:* `package` access requires both modules to
   build with the same `-package-name`. This is native under SPM; under CocoaPods
   it needs `OTHER_SWIFT_FLAGS`/`pod_target_xcconfig` entries in both podspecs and
   must be proven with `pod lib lint` before the demotion PR is written. Fallback
   if CocoaPods fights it: collapse to a single `PayCross` pod with Core as a
   subspec (revisits the two-pod publish plan, not the API surface goal).
3. **ipify removal** (depends on Workstream 2 being live in the test env):
   delete `IPAddressProvider`, send `browser_info.ip_address` only when the app
   supplies one, rely on server-side derivation otherwise.
4. **Status-poll caching fix:** status GETs use
   `.reloadIgnoringLocalCacheData` so polling never reads a stale cached body
   (cache hits were observed on live polls during the 2026-08-20 test drive).
5. **`PrivacyInfo.xcprivacy`** for both pods: declares collected data types
   (payment info, contact info, IP address), `NSPrivacyTracking=false`, and any
   required-reason APIs in use. README gains a short section merchants can copy
   into their App Store privacy labels.
6. **`Package.swift`** with products `PayCross` and `PayCrossCore`, so the same
   tag serves SPM and CocoaPods. SPM is the long-term channel once trunk is
   read-only.
7. **Housekeeping:** MIT LICENSE, podspec `s.license` updates, SECURITY.md,
   README/version-string corrections, CHANGELOG entry for 0.1.0.

## Workstream 2 — backend-derived IP

Contract change: `browser_info.ip_address` becomes optional from the client. The
submit-card Lambda (`payment-submit-card`) fills it from the API Gateway request
context when absent, so the downstream Laravel validation (`required|ip` in
`CreatePaymentSessionTransaction`) is always satisfied and stays untouched.
Deployed and verified in the test environment (simulator rig end-to-end) before
Workstream 1 item 3 merges. Android keeps its own ipify call for now and drops it
in a later 0.3.x — out of scope here.

## Workstream 3 — cut-over runbook

Preconditions: Workstreams 1–2 merged, CI green, and a full end-to-end payment
(mint → sheet → approved) on the release-candidate commit using the Mac simulator
rig.

1. Freeze: other session confirms done; no further merges.
2. Archive: private fork (e.g. `paycross/payment-ios-sdk-archive`) keeps the full
   history.
3. Squash: one clean initial commit built from the release-candidate tree;
   force-replace `main`.
4. Belt and braces: gitleaks over the new single-commit tree; CI green on new
   `main`.
5. Flip public. Enable issues and GitHub private vulnerability reporting; confirm
   branch protection survived.
6. Tag `v0.1.0` on the squash commit.

The Flutter CI deploy key keeps working throughout (deploy keys survive the
visibility change); its teardown stays scheduled for after trunk publish per
paycross-flutter issue #9.

## Workstream 4 — publish and verify

1. `pod spec lint PayCrossCore.podspec` and `pod spec lint PayCross.podspec`
   against the public tag (on the Mac).
2. Owner runs `pod trunk register` (email verification; human step).
3. `pod trunk push PayCrossCore.podspec` → wait for CDN propagation →
   `pod trunk push PayCross.podspec` (PayCross depends on Core).
4. Verify like a merchant: a scratch Xcode project with only
   `pod 'PayCross', '0.1.0'` resolves from trunk and builds.
5. Teardown per paycross-flutter #9: remove the Podfile override, workflow
   checkout step, `PAYCROSS_IOS_SDK_DEPLOY_KEY` secret, and deploy key 160788431;
   Flutter iOS CI must then pass resolving from trunk — CI validates exactly what
   merchants get.
6. Later: `pod trunk add-owner` for a team address (follows io.paycross #868).
7. Unblocked afterwards: pub.dev publishing of the Flutter plugin.

## Testing

- Existing unit suites and repo CI gate every Workstream 1 PR (Core tests run on
  Linux CI).
- The `package`-access spike is validated by `pod lib lint` before the demotion
  PR exists.
- Workstream 2 is validated in the test environment with the simulator rig
  before the SDK change merges.
- The release candidate gets a full end-to-end payment before tagging.
- Post-publish, trunk resolution is validated twice: scratch project and Flutter
  CI teardown.

## Risks

- **`package` access across two pods** — highest technical risk; spiked first,
  with the subspec fallback named above.
- **3DS gate slips** — schedule risk only; everything else can be PR-ready and
  waiting.
- **Force-replace coordination** — mitigated by the freeze step and the archive
  fork; anyone with a clone re-clones.
- **Trunk deadline 2026-12-02** — comfortable unless the 3DS gate drags by
  months.

## Out of scope

Android ipify removal, wallet features for iOS, pub.dev publishing itself, the
backend's silent-validation-tombstone observability gap (noted in io.paycross
PR #867), and any SPM-only distribution work beyond shipping `Package.swift`.
