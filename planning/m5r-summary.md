# M5R — Work Summary (for independent retrospective review)

Date: 2026-09-10. Milestone 18 ("M5R Retrospective review issues"): 14 tickets closed across 7 pairs; 1 pair in review (#287/#292). Source reviews: `planning/m5-code-review.md`, `planning/m5-project-review.md`. Execution contract: `planning/m5r-m6-handoff.md` (frozen references; deviations below are user-ruled and recorded on tickets).

## Closed pairs (all TDD: reds → approval → implementation → joint close)

1. **#281 → #289 (A.1, CRITICAL, blocks M6)** — IAM probe resolves credentials through the driver. `AwsS3V3AdapterDriver::buildClient()` is the single resolution point for `buildAdapter()` and `BucketIamProbeFactory` (fixes M2); `detectConflicts()` returns conflicts + determined (fixes M3, bundled into A1 per review disposition with user sign-off); undetermined renders an informational (not warning) requirements entry. Connection test fails only on determined conflicts (recorded decision).
2. **#282 → #290 (A.2, CRITICAL, blocks M6)** — guard the adapter-build path. `getAdapter()` catches build throws → logs → `MisconfiguredFilesystemAdapter` carrying a reason string; `getExternalUrl()` presigned branch guarded. Follow-up fixes the review caught: `operatorForUri()` maps mount failures to InvalidStreamWrapperException (boundary 2) and write-mode `stream_open()` reports (C10) — both depended on the throw the catch now swallows.
3. **#284 → #294 (A.7, MEDIUM)** — closed with NO code, per the ticket's own close condition. The mandated refute ran first against live local Floci: SDK failure messages quote only header-signed URIs (no credentials); presigned URIs carry credentials but nothing in the module logs a message quoting one. Evidence on #284, #294 references it.
4. **#295 → #296 (A.6, HIGH)** — `presigned_expiry` declared on the `s3` driver (key + schema + form + `#252`-mirrored server-side gating for non-private schemes). Filed as support, not a scope decision: presigned was ruled agreed, expressed functionality (architecture §4, M5 exit criterion; the "deliberately out of scope" premise misquoted §4). Settings.php parity cited from the existing probe leg, not duplicated. `plan-m6.md` §1 scope note recorded.
5. **#286 → #291 (A.3, HIGH, blocks M6)** — provider key management read first in both drivers; credentials sub-tree unset on entity save (scoped to flag-declaring drivers). One pipeline failure post-implementation: Leg 1 asserted chain-throw behavior that CI's ambient AWS credentials defeat — rewritten to assert the referenced statics never surface (fails on unfixed code in any environment).
6. **#297 → #298 (B.2 guard, M5R per placement ruling)** — NOT in the handoff; added on user direction to pin `aws_s3`/`s3` directory behavior before M6 B.2 refactors it. Probe corrected the premise: forced-private never reaches S3 placeholders (league `withDefaults()` over the set scheme visibility is a no-op) — pins assert scheme-visibility-following per driver (2 legs each, mock transport only; Floci cannot discriminate ACLs, precedent #241/#246). Verify-and-close, no implementation code.
7. **#288 → #293 (A.5, HIGH)** — verdict cache (request memo + 6h persistent cache, both cleared on entity save via the extended invalidation subscriber) and bounded probe transport (timeout 5, retries 0 as named constants through `buildClient()` overrides; operational clients untouched). Probe stays on the requirements path (recorded decision).

## In review

- **#287 → #292 (A.4, HIGH, blocks M6)** — permission-gate the onscreen warning. Audience ruled: authenticated + `administer flysystem filesystems`, nobody else (watchdog stays unconditional; log viewing is already permission-gated). `current_user` wired through the factory (AccountProxy mutates in place — no stale references). The #280 frequency test runs as a permitted user under the new contract.

## Decisions kept, not filed

- **A.8 (L1)**: both `send_chunked_body` defaults stay TRUE; endpoint rule documented in README subsection + both drivers' form descriptions (DigitalOcean Spaces verified unsupported — added to the list).
- **A.9**: milestone 18 description carries the user-ruled placement (M6 = sftp submodule + its gaps; everything else prior-deficiency → M5R; M5R closes before M6 starts).
- **A.10 + P3**: `plan-m6.md` §3 carries the integration pass and bidirectional consumer rule. P4's pre-flight rule was redirected into the TA4/A4 audience work instead.
- **B.1–B.6**: `plan-m6.md` §1/§2.2/§4 amended (per-key consumers + legs from vendored league source; both B.2 and B.5 refutes FAILED at source — defects stand; fingerprint warning policy; timeout budget; `public_url_base` sentence). **B.4 wired**: A.1–A.4 impls block #106; #212 to Ready.
- **T-B1/B1 (#299/#301), T-B2/B2 (#300/#302)**: filed to milestone 17.

## Incidents during the work (all fixed, all on ticket records)

- **Wrong cache service**: `invalidateTags()` called on `CacheBackendInterface` — absent on the Functional stack's `DatabaseBackend` (Kernel's memory backend has it, masking it locally). 41 errors + 10 failures, one defect. Fixed with `@cache_tags.invalidator`; proven by the previously-failing form-save test.
- **Silent import drops**: single-line `use` additions via file edit repeatedly reported success without applying (twice: `AccountProxyInterface`, `Aws\Result`), producing silent `instanceof` failures and a fatal respectively. Every import now gets a same-pass grep verification; multi-line edits appear unaffected.
- **uid-1 superuser subjects**: first user in a fresh test DB bypasses all permission checks, silently vacuuming audience assertions. Both audience test files pin non-root subjects.
- **SDK-opaque seams**: AWS SDK consumes `http`/`retries` opaquely (verified `getConfig()` returns NULL) — TA5 Leg 3 rewritten to pin the bound constants, with delivery covered by review + the refused-endpoint behavioral leg.

## QA posture

Every ticket carries pasted canonical output (phpunit scoped to changed files, `SIMPLETEST_DB=mysql://db:db@db/test`; phpcs uncached clean; phpstan clean). Full suite runs in the GitLab pipeline, green at last report. Two pipeline failures occurred during the work (remap-download content mismatch — non-deterministic, green on retry with zero code change, noted for revisit if it recurs; TA3 Leg 1 CI-ambient-creds — fixed as above).
