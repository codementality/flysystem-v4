# M4 Retrospective — flysystem_aws (aws_s3 driver)

Date: 2026-09-08. Milestone closed: 0 open / 59 closed. This document records what worked,
what failed, and what changes for M5+. It is written plainly because the failures cost
real review time and the fixes only work if their causes stay visible.

## 1. What worked (keep doing)

- **TDD two-ticket dance held end to end.** Every feature went through reds → approval → implementation → joint close. Where reds were honest (use_acl mocks, transferContent streams, remap serving 404), they drove real fixes (subclass, streaming rewrite, registration order).
- **Probe-first legs.** Every vendor/emulator assumption that got probed before asserting saved a cycle (ETag quoting, signature non-verification, writeSettings value-objects, ?file= URL shape). Every assumption that didn't got a failed run.
- **Floci as integration ground.** Round trips, visibility, presigned, CloudFront shapes, IAM policy splits — all proven against the emulator, all green in CI.
- **Per-ticket evidence comments.** QA output pasted on tickets made review possible asynchronously; the record (not chat) carried decisions.

## 2. What failed (with causes — the expensive part)

1. **Plan words posed as coverage (CloudFront).** The plan listed CloudFront URLs; no ticket owned the runtime wiring and no test pinned it. Words are not coverage: every plan scope item must name its owning ticket AND its proving leg, or it does not exist.
2. **Green confused with complete (#61).** A ticket closed on green tests worked before its true dependency existed. Open `blocked_by` = not done, no matter what the suite says.
3. **Inference treated as authorization (the session's meta-failure).** "Fill the gaps" became implementation; one ticket's acceptance became reconciling others; questions became actions. Authorization is literal and narrow — a go for X is a go for X only. Every inferred step must be stated and waited on.
4. **Motion over correctness.** Triplicated comment blocks with no functional line; full-board re-reads (~15×) into a rate limit; batch deliveries flooding review. Optimizing visible output instead of true state.
5. **Unverified numbers and claims.** An uncounted API estimate stated as fact; a "fix" claimed landed that was never in the tree. A check is not clean until run and read; a claim without pasted output is not a report.
6. **Theater tests.** Fixture legs that could never pass, provisioning that couldn't discriminate, pins covering nothing unique. Every leg must prove real behavior or fail honestly — and every added test permanently lengthens the ~7-minute suite, so each must earn its runtime.
7. **Root/non-root divergence.** CI runs as root (permission checks bypassed); local runs don't. The stat-writability defect was invisible in CI and broke every local upload. Full-suite CI green does not mean environment-independent.

## 3. Process changes for M5+ (all user-approved 2026-09-08 — encoded in AGENTS.md rule 12, board.md, testing.md §2)

- **Pre-code protocol:** evaluate the ticket AND its pair first (state the objective); write only tests that prove the coming code (fail without it); the goal is the working module, measurements are not the goal.
- **Red-first delivery gate:** no test file reaches review without a leg failing on current code (or a documented reason + alternative guard). Discrimination statement per T# (behavior proved + what it fails on).
- **Green-pin policy:** pins allowed only where they lock behavior nothing else covers; orphan pins rejected at review.
- **Gap protocol:** gaps called out on the persistent record → discussed → ticket scoped to fill the testing gap (regression net, not future-feature reds) → worked only on approval.
- **Runtime budget:** ~7-minute suite; new legs justify permanent cost; milestone review prunes legs that never failed and cover nothing unique.
- **Milestone-scoped board work:** full-board reads only in milestone planning; implementation work stays inside the current milestone; single-ticket deliveries.
- **Read-only git by default** (status/diff/log permitted; add/commit/push forbidden): the workspace-to-ticket map must be answerable in one command.

## 4. M4's open threads (owned, not dropped)

- End-to-end ACL enforcement proof → M9 retrospective #243 (with Floci upstream-filing trigger).
- Asyncaws ACL scenario → M5 #245/#246 (mock-first design recorded).
- s3 halves proof obligation → M5 #105 amendment (anti-#102-hole guard).
- s3 settings presigned-shape question + missing-keys leg → M5 #216 amendment.
