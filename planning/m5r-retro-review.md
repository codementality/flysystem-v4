# M5R (Milestone 18) — Code Retro Review

Status: Review, 2026-09-10. Scope: milestone 18 ("M5R Retrospective review issues"), all 16 tickets
(#281–#298), the module-repo commits `cc89059..1b70b28` (branch `4.0.x`), judged against the tickets'
own bodies/comments, `planning/plan-m5.md` (frozen), `planning/architecture.md` §4, `planning/m5-code-review.md`,
`planning/m5-project-review.md`, and `AGENTS.md` rule 12.

**Reviewer note (conflict of interest):** the agent writing this review also authored the implementation
under review. It is therefore a self-review, not an independent approval gate (rule 2). Findings were
reproduced against the committed code, not against comment claims. An independent pass is still required;
treat this document as input, not sign-off.

## Executive summary

M5R delivered its seven pairs and closed M5's review backlog, but **one residual of the milestone's own
CRITICAL class remains (the IAM probe still reports clean when a read is denied), and #296's s3 presigned
surface is inverted and unproven, so the capability it was filed to expose is still unreachable through
the admin form.** The downstream-boundary fixes (#290), the entity-layer credential gating (#291), the
audience gate (#292), the caching/bounding (#293), and the directory pins (#297/#298) verified out.

| Gate | Result |
|---|---|
| GitLab pipeline (canonical) | **GREEN** at 2026-09-10 (user-reported, full suite) |
| `phpcs` (canonical, `--no-cache`) | clean per ticket records (`[OK]`/exit 0 pasted on each pair) |
| `phpstan` (canonical, level 8) | `[OK] No errors` per ticket records |
| This review's gates | **NOT RE-RUN** — an active local run was in progress; re-running phpunit would clobber it. Static gates not re-run either. Finding C1 was reproduced with a standalone script (no DB). |

## Findings — by severity

- **CRITICAL — C1.** The IAM probe's `determined` flag is TRUE whenever no throw escapes, so denied/ unreadable sub-reads still report "clean" — the exact manufactured-safety class M5R was built to close.
- **HIGH — H1.** #296's s3 presigned form/validator is inverted against the wrapper and README: offered for private schemes (ignored), stripped for public schemes (where it works); the capability is still unreachable via the admin path.
- **HIGH — H2.** #295's entity-seam and settings-seam proving legs were not delivered; only field/schema/validator legs exist, so H1 shipped green.
- **MEDIUM — M1.** #290's new build-failure watchdog entry logs the raw exception message, bypassing `ExceptionMessageScrub` used by every sibling call site.
- **MEDIUM — M2.** `determined => FALSE` verdicts are cached for six hours; transient probe failures become sticky and suppress re-probing.
- **LOW — L1.** Dead branch in `clientCredentials()` (both drivers).
- **LOW — L2.** Stale test docblock still says "no presigned scope for s3".
- **LOW — L3.** #297's mandated Floci probe step was superseded by precedent (accepted, recorded).
- **LOW — L4.** An IAM pin is coupled to network behavior (asserts the undetermined entry for an unreachable bucket).

## Findings detail

### C1. `determined` does not reflect unreadable sub-reads; the probe still reports clean — CRITICAL *(verified)*

**What:** `AwsSdkBucketIamProbe::detectConflicts()` returns `determined => TRUE` whenever no exception escapes the outer `try`, but `isOwnershipEnforced()` and `aclIsPublic()` swallow their failures into `NULL` ("unreadable"). A denied `s3:GetBucketOwnershipControls` (or `s3:GetBucketAcl`) therefore yields an empty conflict list with `determined => TRUE` — "clean" — and the undetermined informational entry added by #281/#289 never fires. `AwsS3V3AdapterDriver::getIamConflicts()` has the same false-clean when `probeFactory === NULL` (the probe cannot run at all): it returns `determined => TRUE`.
**Evidence:** Reproduced with a standalone script against the committed class (`AwsSdkBucketIamProbe` + `Aws\MockHandler`): policy readable-not-public, `GetBucketOwnershipControls` answering `AccessDenied` → output `['conflicts' => [], 'determined' => true]`. Code: `AwsSdkBucketIamProbe.php:59-61` (catch), `:70` (unconditional TRUE), `:104-106` and `:138-140` (helpers suppress into NULL); `AwsS3V3AdapterDriver.php:201-205`.
**Impact:** The security-posture check built to replace M4's H1 still manufactures safety in a realistic least-privilege setup — the class the source review graded CRITICAL and the reason M5R's A.1 exists. An operator missing the probe's read permission sees a clean status report and no "could not run" signal.
**Fix:** Derive `determined` from read success, not from the absence of a throw. Give the three read helpers a tri-state that preserves FALSE vs NULL, and set `determined => FALSE` whenever a read contributing to the verdict is NULL (policy NULL, or ownership controls NULL, or the ACL consulted and NULL). Return `determined => FALSE` when `probeFactory === NULL`. Add reds: denied ownership read → undetermined; denied ACL read on a private scheme → undetermined (never clean).

### H1. The s3 presigned form surface is inverted against its own consumer — HIGH *(reviewed)*

**What:** #296 adds `presigned_expiry` to the s3 form/validator "matching aws_s3 including #252's public-scheme gating." The field's `#states` makes it visible only when `default_visibility = private`, the description says it applies "only to a private bucket", and `validatePresignedExpiry()` unsets it for non-private schemes. The stream wrapper does the opposite: `getExternalUrl()` returns the access-checked private-download route for private schemes (`FlysystemStreamWrapper.php:532-538`) and only reaches the presigned branch at `:560` for public schemes. The README agrees with the wrapper (`README.md:105` "opts a public scheme in", `:125`, `:135` "public schemes only"). Net effect after #296: the capability is allowed only where it is ignored, and stripped where it would work — still unreachable through the admin form.
**Evidence:** `S3AdapterDriver.php:362-368` (`#states default_visibility = private`; description "apply only to a private bucket"); `:394-402` (validator unsets when visibility !== 'private'); wrapper `:532-538` vs `:560`; `README.md:105,125,135`. The aws_s3 original is identical (`AwsS3V3AdapterDriver.php:358-373`, `:499-505`) — M4-frozen, but #296 reproduces it in a new driver. The delivered test `S3PresignedSurfaceTest.php:107` (`testPresignedExpiryUnsetForNonPrivateSchemes`) pins the inverted direction.
**Impact:** The ticket's goal — expose the proven capability through the supported configuration path — is unmet. Only settings.php on a public scheme reaches it; a public entity scheme carrying the key is stripped on save. Operators following the UI cannot enable presigned.
**Fix:** Align the surface with the consumer, in both drivers: show the field only for public schemes and make the validator unset it for private schemes (or, if the intent is truly private-only, move the wrapper's presigned branch above the private short-circuit — but that contradicts the README and Drupal's access-checked private route, so the surface is the correct thing to fix). Then rewrite the leg to assert the corrected direction. `aws_s3`'s copy is a prior-milestone deficiency → M5R per the placement ruling.

### H2. #295's entity- and settings-seam proving legs were not delivered — HIGH *(verified)*

**What:** Ticket #295 specified four legs: (1) config-entity seam validates, persists, and `getExternalUrl()` emits a real signed URL; (2) settings.php seam emits a signed URL (green pin); (3) schema allows the key; (4) public-scheme gating. The delivered `S3PresignedSurfaceTest.php` has three tests — form-field existence, schema entry, and validator-unset — none of which is leg (1) or (2). Settings.php parity is cited to `AsyncAwsSettingsPhpConfigTest.php:222-240`, which drives the adapter's `temporaryUrl()` directly, not the wrapper and not the entity seam.
**Evidence:** `grep -n "public function test" S3PresignedSurfaceTest.php` → 3 methods (lines 66, 86, 107). `grep -rln "getExternalUrl|temporaryUrl|X-Amz" modules/flysystem_asyncaws/tests/` → only `AsyncAwsSettingsPhpConfigTest`. No s3 test asserts a signed URL from a config entity.
**Impact:** This is the exact "declared-but-unconsumed" class the milestone exists to catch, and the reason H1 shipped green. Per the project's own standard, the new key is not covered until a test proves something downstream of reading it.
**Fix:** Add the missing legs: an s3 config entity, public scheme, `presigned_expiry` set → `getExternalUrl()` returns a SigV4-signed URL; private scheme → the key is rejected/stripped; and prove the settings.php seam through the wrapper, not only the adapter.

### M1. New build-failure log bypasses `ExceptionMessageScrub` — MEDIUM *(verified)*

**What:** #290's `getAdapter()` catch logs `$e->getMessage()` verbatim, while the two sibling connection-test sites scrub with `ExceptionMessageScrub::scrub()`. The scrub's contract ("a single shared filter, so no call site can drift back to verbatim logging") is violated by the new call site.
**Evidence:** `FilesystemFactory.php:388-392` (`'@message' => $e->getMessage()`); `:536` and `:640` use `ExceptionMessageScrub::scrub($e->getMessage())`. `ExceptionMessageScrub` is XML-element-only (source review M1; #294 closed with no code).
**Impact:** Any credential material in a build-time exception — or a future SDK message quoting a signed URI — reaches watchdog unscrubbed. #294's no-code close assumed log sites keep using the shared filter.
**Fix:** `ExceptionMessageScrub::scrub($e->getMessage())` at `FilesystemFactory.php:388`. This is also the moment to decide the allowlist-vs-denylist question #294 deferred, if the filter is to be extended.

### M2. Undetermined verdicts are cached for six hours — MEDIUM *(reviewed)*

**What:** `getIamConflictsForDriver()` caches every verdict, including `determined => FALSE`, for 6h. A transient probe failure (network blip, IAM propagation, deploy) is sticky: after the cause clears, the status report keeps showing "could not run" until the TTL expires or the scheme entity is saved. Settings.php schemes have no entity save to invalidate it.
**Evidence:** `FilesystemFactory.php:730-736` — `catch → ['conflicts' => [], 'determined' => FALSE]` then an unconditional `cacheBackend->set($cid, $verdict, time() + 21600, ['flysystem_iam_verdicts'])`.
**Impact:** Stale results for up to 6h, undercutting the prompt signal the probe was just given; a rotated/edited settings.php config changes the hash and re-probes, but a transient failure on unchanged config does not.
**Fix:** Do not persist `determined === FALSE` (re-probe next request; the per-request memo prevents a single page probing twice), or give failures a separate short TTL (5–15 min) while keeping hours-scale for successful verdicts.

### L1. Dead branch in `clientCredentials()` (both drivers) — LOW

`!empty($config['use_provider_key_management'])` returns early for any truthy value, so the later `if ($hasFlag && $useProvider) { return NULL; }` is unreachable. Evidence: `AwsS3V3AdapterDriver.php:540-542` vs `:571-573`; `S3AdapterDriver.php:433-435` vs `:464-466`. Fix: delete the dead branch (the explicit-FALSE throw it precedes stays reachable and needed).

### L2. Stale test docblock — LOW

`modules/flysystem_asyncaws/tests/src/FunctionalJavascript/S3ConfigFormRenderTest.php:20` still says "no presigned scope for s3". #296 corrected the driver docblock but not this one. Fix: update the comment.

### L3. DIRV mandate step 1 superseded by precedent — LOW *(reviewed, accepted)*

#297's mandate required probing Floci for an observable; the record cites the #241/#246 precedent and pins at the mocked adapter-request seam instead. The corrected premise (placeholders follow scheme visibility, not forced-private) is evidenced and sound; only the literal step was not executed. No change required; recorded for the reviewer's awareness.

### L4. Environment-coupled IAM pin — LOW *(reviewed)*

`BucketIamConflictDetectionTest::testMatchingConfigurationWarnsNothing` now asserts the undetermined informational entry, which depends on the real probe failing (no endpoint). It passes because bucket `private` is unreachable, but a unit pin should not depend on network state. Fix: drive the undetermined branch through the refused/mocked endpoint as the other IAM legs do.

## What this review got right

Bounds the findings: the milestone's hard parts verified out.

- **#290's downstream boundaries**: the two follow-on fixes (mount failures → `InvalidStreamWrapperException`; write-mode `stream_open()` reporting) are correct and covered by `SilentCatchReportingTest` and `ExceptionStrategyTest`.
- **#291's entity-layer gating** is stronger than the form-layer pattern it mirrored (covers programmatic/import saves), and the flag-first ordering preserves the legacy absent-flag path.
- **#292's audience gate** matches the ruling exactly, the uid-1 superuser trap was found and pinned, and watchdog stays unconditional.
- **#293's cache-service correction** (backend vs tags invalidator) is right, and the bounded probe transport is applied at the single resolution point without touching operational clients.
- **#297/#298 corrected a false premise** (forced-private does not reach S3 placeholders) with on-the-wire evidence rather than shipping the assumed pin.

## Verification

```bash
# Reviewed commits (module repo, branch 4.0.x)
git -C web/modules/custom/flysystem diff --stat 3416fc9..HEAD
git -C web/modules/custom/flysystem diff 3416fc9..HEAD -- src/ modules/*/src/

# M2 — the cache keeps failures
grep -n "cacheBackend->set" src/Flysystem/FilesystemFactory.php
# → :736  set($cid, $verdict, time()+21600, ...) after the catch at :731

# M1 — new log site does not scrub; siblings do
grep -n "failed to build its\|ExceptionMessageScrub::scrub" src/Flysystem/FilesystemFactory.php
# → :388 raw; :536, :640 scrubbed

# H1 — form gates private; wrapper consumes public
grep -n "presigned" modules/flysystem_asyncaws/src/Plugin/Flysystem/Adapter/S3AdapterDriver.php
sed -n '532,560p' src/StreamWrapper/FlysystemStreamWrapper.php

# H2 — only three presigned tests, none entity-seam
grep -n "public function test" modules/flysystem_asyncaws/tests/src/Kernel/S3PresignedSurfaceTest.php

# C1 — reproduced standalone (no DB; output pasted below)
ssh web "php /var/www/html/.scratchpad/m5r/verify-m3.php"
# Case A (ownership denied, private scheme): ['conflicts' => [], 'determined' => true]
```

`*(verified)*` findings are backed by the outputs above; `*(reviewed)*` findings are reads of the committed
code (exact `file:line`). No phpunit/phpcs/phpstan run was made in this review (active local run); the
canonical pipeline is green as reported by the user.

## Disposition — action items

All items are M5R (prior-milestone deficiencies), per the milestone-18 placement ruling; M6 is sftp-only.
None of these were closed by the current ticket set; they need their own TDD pairs or explicit closures.

- [ ] **C1** — fix the probe's `determined` semantics (tri-state reads; FALSE on any required read NULL; FALSE when `probeFactory` NULL) and add the two reds. **Filed as #303 (T#) → #307 (impl).** Treat as blocking for M6 (A.1/DIRV feeds #106). *Detail: C1.*
- [ ] **H1** — align the presigned form/validator with the wrapper/README in **both** drivers (public-only, unset for private), and rewrite the inverted leg. **Filed as #304 (T#) → #308 (impl).** *Detail: H1.*
- [ ] **H2** — add the missing entity-seam and settings-through-wrapper legs for the s3 presigned key. **Rides with #304/#308.** *Detail: H2.*
- [ ] **M1** — wrap `FilesystemFactory.php:388-392` with `ExceptionMessageScrub::scrub()`; record the allowlist-vs-denylist decision #294 deferred. **Filed as #305 (T#) → #309 (impl).** *Detail: M1.*
- [ ] **M2** — stop caching `determined => FALSE` (or short TTL for failures); add/adjust the cache pin. **Filed as #306 (T#) → #310 (impl).** *Detail: M2.*
- [ ] **L1** — remove the dead `$hasFlag && $useProvider` branch in both drivers. **Folded into #308.** *Detail: L1.*
- [ ] **L2** — fix the stale `S3ConfigFormRenderTest.php:20` docblock. **Folded into #308.** *Detail: L2.*
- [ ] **L3** — no action; accepted as recorded. *Detail: L3.*
- [ ] **L4** — make the IAM "warns nothing" pin deterministic (refused/mocked endpoint). **Folded into #303.** *Detail: L4.*
- [ ] **Independent pass** — commission the independent retro review; this document is a self-review and is not an approval gate. *Detail: reviewer note at top.*
