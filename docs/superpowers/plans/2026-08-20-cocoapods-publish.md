# CocoaPods Publish (PayCross 0.1.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `paycross/payment-ios-sdk` publicly publishable and ship `PayCrossCore` + `PayCross` 0.1.0 to CocoaPods trunk, per the approved spec `docs/superpowers/specs/2026-08-20-cocoapods-publish-design.md`.

**Architecture:** Four sequenced workstreams: (1) code readiness in the iOS repo, gated by a `package`-access spike; (2) a backend contract change making `browser_info.ip_address` server-derived; (3) a history-squash cut-over that flips the repo public; (4) trunk publish + merchant-style verification. Tasks 2 and 3 run in different repos and are independently gated.

**Tech Stack:** Swift 6 (SPM package `PayCross`, two CocoaPods), Go (payment-submit-card Lambda), GitHub Actions (Linux `swift test` for Core, macOS `pod lib lint` via `.github/workflows/podspec.yml`), remote Mac over SSH for fast local iteration.

---

## Ground rules for every worker

- **NEVER touch `/home/silvo/projects/payments/paycross-ios-sdk`** — another agent session owns that working tree. The WSL clone `/tmp/claude-1000/-home-silvo/ee22b658-fa12-436d-bfbe-3890362167b2/scratchpad/fix-ios-sdk` is the single git authority: all edits, branches, commits, and pushes happen there. The Mac has NO GitHub credentials; `~/work/publish-prep/payment-ios-sdk` is a build mirror, refreshed by piping a tar of the WSL worktree over SSH:

```bash
cd /tmp/claude-1000/-home-silvo/ee22b658-fa12-436d-bfbe-3890362167b2/scratchpad/fix-ios-sdk \
  && git ls-files -z | tar -czf - --null -T - | ssh mac 'rm -rf ~/work/publish-prep/payment-ios-sdk && mkdir -p ~/work/publish-prep/payment-ios-sdk && tar -xzf - -C ~/work/publish-prep/payment-ios-sdk'
```

(`git ls-files` ships tracked files including uncommitted edits, so the edit → sync → remote-build loop works mid-task. Re-run the sync after every edit batch, before every remote build.)
- Mac SSH host is `mac`. Every non-interactive shell there needs `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PATH=/opt/homebrew/bin:$PATH`.
- No Swift toolchain exists in WSL. Compile/test on the Mac; CI is the authority.
- One PR per task, base `main`. Do not merge PRs; do not push tags; the repo owner does both. Steps marked **[HUMAN]** are the owner's.
- Secrets and tokens are never printed. Session mint credentials come from `~/projects/payments/payment_testing_go/.env.staging` via subshell sourcing only.
- Commit messages and code comments follow the repo idiom: comments state constraints, rationale lives in PR bodies.

---

### Task 1: Mac build harness baseline

**Files:** none (environment only)

- [ ] **Step 1: Mirror the WSL clone to the Mac** (the Mac cannot clone — no GitHub auth there; see ground rules)

```bash
cd /tmp/claude-1000/-home-silvo/ee22b658-fa12-436d-bfbe-3890362167b2/scratchpad/fix-ios-sdk && git fetch -q origin && git checkout -q main && git pull -q
git ls-files -z | tar -czf - --null -T - | ssh mac 'rm -rf ~/work/publish-prep/payment-ios-sdk && mkdir -p ~/work/publish-prep/payment-ios-sdk && tar -xzf - -C ~/work/publish-prep/payment-ios-sdk'
```

- [ ] **Step 2: Baseline swift test**

```bash
ssh mac 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; cd ~/work/publish-prep/payment-ios-sdk && swift test 2>&1 | tail -5'
```
Expected: `Test Suite ... passed` (all PayCrossCoreTests green).

- [ ] **Step 3: Baseline pod lib lint**

```bash
ssh mac 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PATH=/opt/homebrew/bin:$PATH; cd ~/work/publish-prep/payment-ios-sdk && pod lib lint PayCrossCore.podspec --silent && echo CORE-OK && pod lib lint PayCross.podspec --include-podspecs=PayCrossCore.podspec --silent && echo PAYCROSS-OK'
```
Expected: `CORE-OK` and `PAYCROSS-OK`. If baseline lint fails, STOP and report — later tasks assume a linting baseline.

---

### Task 2: Spike — `package` access across the two pods (GATE)

**Files (spike branch `spike/package-access`, may be discarded):**
- Modify: `PayCross.podspec`, `PayCrossCore.podspec`
- Modify: `Sources/PayCrossCore/Wire/SubmitCardRequest.swift` (one symbol only)

- [ ] **Step 1: Branch on the Mac clone**

```bash
cd /tmp/claude-1000/-home-silvo/ee22b658-fa12-436d-bfbe-3890362167b2/scratchpad/fix-ios-sdk && git checkout -b spike/package-access
# edits happen here in WSL; after each edit batch re-run the mirror sync from the ground rules
```

- [ ] **Step 2: Add the package name to both podspecs**

In BOTH podspec files, inside the `Pod::Spec.new do |s|` block, add:

```ruby
  # Both pods must compile as one Swift package so `package`-access symbols in
  # Core stay invisible to merchants but usable by PayCross.
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-package-name PayCross' }
```

If a `pod_target_xcconfig` already exists, merge the key into it instead of adding a second one.

- [ ] **Step 3: Demote one cross-module symbol**

In `Sources/PayCrossCore/Wire/SubmitCardRequest.swift` change `public struct BrowserInfo` to `package struct BrowserInfo` and every `public` member of that struct (init, properties, statics) to `package`. This type is used by `PayCross/PaymentSheet.swift`, so it exercises exactly the cross-pod boundary.

- [ ] **Step 4: Prove it under SPM**

```bash
ssh mac 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer; cd ~/work/publish-prep/payment-ios-sdk && swift build && swift test 2>&1 | tail -3'
```
Expected: builds and tests pass (SPM targets share the package name automatically).

- [ ] **Step 5: Prove it under CocoaPods**

```bash
ssh mac 'export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer PATH=/opt/homebrew/bin:$PATH; cd ~/work/publish-prep/payment-ios-sdk && pod lib lint PayCross.podspec --include-podspecs=PayCrossCore.podspec --silent && echo SPIKE-PASS || echo SPIKE-FAIL'
```

- [ ] **Step 6: Record the gate decision**

`SPIKE-PASS` → Tasks 5 and later proceed as written; keep the branch for Task 5 to build on.
`SPIKE-FAIL` → STOP. Report the lint error verbatim to the owner and present the spec's named fallback (single `PayCross` pod with Core as a subspec). Do not improvise a third option; Tasks 5, 7, 8, 9 and 11 change shape and the plan must be revised.

---

### Task 3: Backend — submit-card derives `ip_address` (separate repo, own gate)

**Files (repo `paycross/payment-submit-card`, fresh WSL clone `/tmp/claude-1000/-home-silvo/ee22b658-fa12-436d-bfbe-3890362167b2/scratchpad/fix-submit-card`):**
- Modify: `internal/handler/validation.go` (or wherever `browser_info.ip_address` is required — locate first)
- Modify: `internal/handler/handler.go` (request-context plumbing if not already available)
- Test: matching `*_test.go` beside the modified files

- [ ] **Step 1: Clone and locate the validation**

```bash
git clone https://github.com/paycross/payment-submit-card /tmp/claude-1000/-home-silvo/ee22b658-fa12-436d-bfbe-3890362167b2/scratchpad/fix-submit-card
grep -rn "ip_address" /tmp/claude-1000/-home-silvo/ee22b658-fa12-436d-bfbe-3890362167b2/scratchpad/fix-submit-card/internal
```
Read the hits. The known behavior: a blank `browser_info.ip_address` is rejected with "missing browser_info.ip_address".

- [ ] **Step 2: Write the failing tests**

Follow the existing table-driven test style in the package. Two cases:

```go
// 1. body omits browser_info.ip_address, API Gateway source IP is "203.0.113.9"
//    -> request accepted, forwarded payload carries ip_address "203.0.113.9"
// 2. body carries ip_address "198.51.100.7"
//    -> forwarded payload keeps "198.51.100.7" (client value wins)
```

The Lambda receives `events.APIGatewayProxyRequest`; the caller IP is `req.RequestContext.Identity.SourceIP` (or the HTTP-API equivalent this handler actually uses — copy from how the handler already reads the request, do not guess).

- [ ] **Step 3: Run tests, verify the new ones fail**

```bash
cd /tmp/claude-1000/-home-silvo/ee22b658-fa12-436d-bfbe-3890362167b2/scratchpad/fix-submit-card && go test ./internal/... 2>&1 | tail -5
```
Expected: FAIL on exactly the two new cases.

- [ ] **Step 4: Implement the fill-before-validate**

Where browser_info is validated, before the blank check: if `ip_address` is empty, set it from the request's source IP. Keep the blank-rejection as the backstop (a Lambda invoked without a source IP should still fail loudly). Comment states the constraint: downstream Laravel validation requires `ip` and must always receive one.

- [ ] **Step 5: Tests green, commit, PR**

```bash
go test ./internal/... 2>&1 | tail -3
git checkout -b feat/server-derived-ip && git add -A && git commit -m "Fill browser_info.ip_address from the request when the client omits it"
git push -u origin feat/server-derived-ip
gh pr create --title "Fill browser_info.ip_address from the request when the client omits it" --body "<explain: SDKs currently fetch their own public IP via api.ipify.org solely to satisfy this required field; with this change clients may omit it and the Lambda fills it from the API Gateway request context. Client-supplied values still win. Prerequisite for removing ipify from the iOS SDK (spec in payment-ios-sdk docs/superpowers/specs/2026-08-20-cocoapods-publish-design.md).>"
```

- [ ] **Step 6 [HUMAN]: merge; deploy-to-test workflow runs**

- [ ] **Step 7: Verify in the test environment (gate for Task 6)**

Mint a session (source `~/projects/payments/payment_testing_go/.env.staging` in a subshell; POST `$TOKEN_URL` with basic auth `$CLIENT_PAYX_SANDBOX_ID:$CLIENT_PAYX_SANDBOX_SECRET`, grant_type=client_credentials; then POST https://api.test-pay-cross.com/payment-sessions with the bearer token, header `PayCross-Version: 2026-06-16`, and the session payload from `payment_testing_go/templates/paycross/approved.json` step 1 — capture `session_token` from the response). Then submit WITHOUT `ip_address` and poll. `body-without-ip.json`:

```json
{"session":"<session_token>","payment_method":"card",
 "card":{"cardholder_name":"TEST DRIVE","cvv":"123","expire_month":"12","expire_year":"2030","pan":"4111111111170000"},
 "browser_info":{"accept_header":"text/html","color_depth":24,"java_enabled":false,"javascript_enabled":true,
  "language":"en-US","screen_height":852,"screen_width":393,"timezone_offset":-180,"user_agent":"Mozilla/5.0"},
 "field_groups":{}}
```


```bash
# mint per ground rules, then:
curl -s -X POST https://checkout.test-pay-cross.com/api/submit-card -H "Content-Type: application/json" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" -H "Idempotency-Key: $(cat /proc/sys/kernel/random/uuid)" -d @body-without-ip.json
# ~5s later: GET https://checkout.test-pay-cross.com/api/status/<txn> -> {"status":"success"}
```
Expected: `success` (PAN 4111111111170000). A `failed`/`retry` tombstone means the fill did not happen — stop and debug the Lambda, not the SDK.

---

### Task 4: Status polls bypass URLCache

**Files (branch `fix/uncached-status-polls` off `main` in the iOS clones):**
- Modify: `Sources/PayCrossCore/Networking/APIClient.swift` (`makeRequest` / `status`)
- Test: `Tests/PayCrossCoreTests/` (new or existing APIClient test file — follow existing naming)

- [ ] **Step 1: Write the failing test** — build a `PayCrossAPIClient` with a stub `HTTPTransport` that captures the `URLRequest`; call `status(transactionID:)`; assert `captured.cachePolicy == .reloadIgnoringLocalCacheData`.
- [ ] **Step 2: Run on the Mac, verify FAIL** (`swift test --filter <TestName>`).
- [ ] **Step 3: Implement** — in `makeRequest`, set `request.cachePolicy = .reloadIgnoringLocalCacheData` for the status path (or all API calls — none of this client's requests should ever be cache-served; prefer all, with a comment: live 2026-08-20 polls were observed served from URLCache).
- [ ] **Step 4: Full `swift test` green.**
- [ ] **Step 5: Commit, push, PR** titled "Status polls must never be served from URLCache". **[HUMAN]** merges.

---

### Task 5: Full API surface demotion (after Task 2 passes)

**Files (branch `fix/package-api-surface`, rebasing the spike):**
- Modify: `PayCross.podspec`, `PayCrossCore.podspec` (the xcconfig from Task 2)
- Modify: every `Sources/PayCrossCore/**/*.swift` holding a demotable `public`
- Test: existing suites (they live in the same package; `package` symbols stay visible to them)

- [ ] **Step 1: Generate the inventory**

```bash
ssh mac 'cd ~/work/publish-prep/payment-ios-sdk && grep -rn "^public \|^ *public " Sources/PayCrossCore --include="*.swift"' > /tmp/core-public-inventory.txt
```

- [ ] **Step 2: Classify.** Keep `public` only what a merchant legitimately touches: `PayCrossEnvironment`, result/recovery types surfaced by the sheet API, error types shown to integrators, and anything `Sources/PayCross`'s own public API returns or accepts. Everything transport/wire/flow (`BrowserInfo`, `SubmitCardRequest`, `SubmitCardResponse`, `StatusResponse`, `SessionResponse`, `PayCrossAPIClient`, `HTTPTransport`, `PaymentFlowRunner`, `PaymentFlowReducer`, `IPAddressProvider` if it still exists, …) becomes `package`. List the keep-public set in the PR body with one-line justifications.
- [ ] **Step 3: Demote mechanically** — type by type, `swift build` on the Mac after each file to catch missed members early.
- [ ] **Step 4: Verify DemoHarness and UI targets still build:** `swift build --target DemoHarnessUI && swift test`.
- [ ] **Step 5: CocoaPods proof:** `pod lib lint PayCross.podspec --include-podspecs=PayCrossCore.podspec`.
- [ ] **Step 6: Commit, push, PR** titled "Restrict PayCrossCore's public surface to the merchant API" — body carries the keep-list and the Android 0.2.0 ABI-leak precedent. CI (`swift test` on Linux + podspec lint) must be green. **[HUMAN]** merges.

---

### Task 6: Remove ipify (after Task 3 step 7 verified)

**Files (branch `fix/remove-ipify`):**
- Delete: `Sources/PayCrossCore/Util/IPAddressProvider.swift`
- Modify: `Sources/PayCrossCore/Wire/SubmitCardRequest.swift` (`BrowserInfo.ipAddress` → optional, omitted from JSON when nil)
- Modify: `Sources/PayCross/PaymentSheet.swift` (drop the warm-up + provider wiring)
- Test: update `Tests/PayCrossCoreTests` encoding/validation tests

- [ ] **Step 1: Write/adjust failing tests** — `BrowserInfo` with nil `ipAddress` encodes WITHOUT an `ip_address` key (backend fills it); with a value, encodes it.
- [ ] **Step 2: Verify FAIL on the Mac.**
- [ ] **Step 3: Implement** — make the property `String?`, custom `encode` omits nil, delete the provider file and its call sites (grep for `IPAddressProvider` and `ipify` until zero hits).
- [ ] **Step 4: `swift test` green; `pod lib lint` green.**
- [ ] **Step 5: End-to-end proof** — build the Flutter example on the Mac against this branch (Podfile `:path` override, rig from 2026-08-20), run mint → sheet → pay → `success`.
- [ ] **Step 6: Commit, push, PR** titled "Stop fetching the device's public IP from api.ipify.org". **[HUMAN]** merges.

---

### Task 7: Privacy manifests

**Files (branch `feat/privacy-manifests`):**
- Create: `Sources/PayCross/Resources/PrivacyInfo.xcprivacy`
- Create: `Sources/PayCrossCore/Resources/PrivacyInfo.xcprivacy`
- Modify: `Package.swift` (add `resources: [.process("Resources")]` to both targets)
- Modify: both podspecs (`s.resource_bundles = { '<PodName>Privacy' => ['Sources/<Target>/Resources/PrivacyInfo.xcprivacy'] }`)

- [ ] **Step 1: Author the manifests.** Declare: `NSPrivacyTracking` = false; no tracking domains; collected data types = payment info + name + email + phone (linked to user, not tracking, app-functionality purpose); required-reason APIs = whatever grep finds (`grep -rn "UserDefaults\|Date(\|fileModification" Sources/` — map hits to the Apple reason codes; if zero hits, an empty `NSPrivacyAccessedAPITypes` array). Post-Task-6 the SDK no longer collects IP client-side; note in the PR body that server-side derivation is a merchant-disclosure question, flagged for owner review.
- [ ] **Step 2: `swift build` green (resources process cleanly).**
- [ ] **Step 3: `pod lib lint` both specs green** (proves the bundles wire up).
- [ ] **Step 4: README section** "App Store privacy labels" summarizing the declarations for merchants.
- [ ] **Step 5: Commit, push, PR.** Body explicitly asks the owner to sanity-check the declared data types. **[HUMAN]** merges.

---

### Task 8: Housekeeping — license, security policy, docs

**Files (branch `chore/public-repo-housekeeping`):**
- Create: `LICENSE` (MIT, copyright "PayCross")
- Modify: both podspecs — `s.license = { :type => 'MIT', :file => 'LICENSE' }`
- Create: `SECURITY.md`
- Modify: `README.md` (stale version strings; install instructions showing BOTH `pod 'PayCross', '~> 0.1'` and SPM URL)
- Create: `CHANGELOG.md` (0.1.0 entry: initial public release; Google-Pay-free card + 3DS flows; language clamp; server-derived IP; privacy manifests)

- [ ] **Step 1: Write all five files.** SECURITY.md: report via GitHub private vulnerability reporting (Security tab → Report a vulnerability); do not open public issues for vulnerabilities; `security@pay-cross.com` arrives later (io.paycross #868).
- [ ] **Step 2: `pod lib lint` both specs** (license change is lint-relevant).
- [ ] **Step 3: Commit, push, PR. [HUMAN]** merges.

---

### Task 9: Release-candidate end-to-end (gate for cut-over)

- [ ] **Step 1:** All Task 1–8 PRs merged, `main` CI green, other session's 3DS work merged **[HUMAN confirms both]**.
- [ ] **Step 2:** On the Mac: rebuild the Flutter example against `main` via `:path` override; sim rig: mint → sheet → prefill → pay → server-side `status: success`. Screenshot the success state.
- [ ] **Step 3:** Record the RC commit SHA as a comment on payment-ios-sdk PR #6 (the spec/plan docs PR), which serves as the cut-over tracking thread. This SHA is what gets squashed and tagged.

---

### Task 10: Cut-over runbook (mostly [HUMAN])

- [ ] **Step 1 [HUMAN]:** Freeze — other session confirms done; no merges past the RC SHA.
- [ ] **Step 2:** Archive: `gh repo fork` is wrong for this — create `paycross/payment-ios-sdk-archive` as a private repo and push all refs to it (`git push --mirror`). Verify: private, and only expected members have access.
- [ ] **Step 3:** Build the squash commit from the RC tree:

```bash
git checkout <RC_SHA>
COMMIT=$(git commit-tree "$(git rev-parse HEAD^{tree})" -m "PayCross iOS SDK 0.1.0 — initial public release")
git branch public-main "$COMMIT"
```

- [ ] **Step 4:** `gitleaks detect --source . --no-git` over the worktree (run wherever gitleaks is available; if absent in WSL: `go install github.com/gitleaks/gitleaks/v8@latest`, or `brew install gitleaks` on the Mac); expected: no leaks.
- [ ] **Step 5 [HUMAN approves]:** `git push origin +public-main:main` (force-replace). CI must go green on the new main.
- [ ] **Step 6 [HUMAN]:** Repo Settings: visibility → Public; Issues on; enable Private vulnerability reporting; re-check branch protection.
- [ ] **Step 7 [HUMAN]:** `git tag v0.1.0 <squash-commit> && git push origin v0.1.0`.

---

### Task 11: Publish and verify

- [ ] **Step 1:** On the Mac: `pod spec lint PayCrossCore.podspec` then `pod spec lint PayCross.podspec` (spec lint, not lib lint — it fetches the public tag exactly as trunk will). Both must pass.
- [ ] **Step 2 [HUMAN]:** `pod trunk register <owner-email> 'PayCross' --description='PayCross SDK publishing'` + click the verification email, on the Mac.
- [ ] **Step 3:** `pod trunk push PayCrossCore.podspec`.
- [ ] **Step 4:** Wait until `curl -sf https://cdn.cocoapods.org/all_pods_versions_5_0_a.txt | grep -i paycrosscore` (shard letter varies — compute it with the CocoaPods shard rule or just retry `pod repo update` + `pod search`) resolves; then `pod trunk push PayCross.podspec`.
- [ ] **Step 5:** Merchant-style verification on the Mac: fresh dir, `Podfile` with only `platform :ios, '16.0'` + `pod 'PayCross', '0.1.0'`, `pod install` must resolve from the CDN, project must build.
- [ ] **Step 6:** Flutter teardown per paycross-flutter issue #9: PR removing the workflow checkout step + env var + Podfile override; after it merges, delete the `PAYCROSS_IOS_SDK_DEPLOY_KEY` secret and deploy key 160788431; Flutter iOS CI green resolving from trunk closes #9.
- [ ] **Step 7:** Later **[HUMAN]**: `pod trunk add-owner` for the team address once io.paycross #868 lands.

---

## Out of scope (repeat from spec)

Android ipify removal, iOS wallets, pub.dev publish, backend tombstone observability.
