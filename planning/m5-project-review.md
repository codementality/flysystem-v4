# M5 (flysystem_asyncaws / s3 driver) — Independent Project Review

Status: Review, 2026-09-10. Scope: GitHub milestone #16 ("M5 flysystem_asyncaws"), all 45 closed issues
in `codementality/flysystem-v4`, their `blockedBy` edges, the M4 corrective pairs that landed inside this
milestone, and the parked threads, judged against `planning/plan-m5.md` (§1 boundary, §2 execution status,
§3 standing constraints, §4 test plan, §5 exit criterion) and `AGENTS.md` rule 12. Companion:
`planning/m5-code-review.md` (the code axis). Findings prefixed `P`; code findings referenced by their own
IDs (C1, C2, H1…).

## Executive summary

**M5's ticket record is the cleanest in the project so far — 45 of 45 closed, zero tickets closed with an
open blocker, and for the first time every single feature ticket carries a T# partner — and the two gaps
that remain are of a genuinely new kind: not missing tickets, but missing checks *between* tickets.** M4's
failure mode was a plan sentence a declaration could satisfy. That did not recur; the anti-#102-hole guard
in `plan-m5.md` §1 worked, and all three claimed contract halves are actually pinned. What M5 has instead
is two tickets that each did exactly what they said and are mutually incompatible (code C2), and a probe
finding that was recorded in a test docblock rather than escalated to the ticket record (code H4). Both are
consequences of running 21 pairs through one milestone with a dependency graph that models start order but
not agreement.

| Check | Result |
|---|---|
| Milestone #16 open / closed | **0 open / 45 closed** — matches `plan-m5.md` §2's claim |
| Tickets closed with an open `blocked_by` | **0 of 45** |
| Feature tickets with a T# partner (rule 12) | **21 of 21** — every zero-edge ticket is a T# |
| Plan §1 "three halves" pinned before #104 closed | **3 of 3** — the anti-#102-hole guard held |
| M4 review dispositions tracked | **All** — 14 pairs worked here; H4 → M9 (#253/#254); M7 items → #277/#278 |
| Plan §1 scope items with an owning ticket | **All** — one capability shipped with no plan entry (P5) |

## Findings — by severity

- **HIGH — P1.** No ticket owned the *interaction* between #248/#250 (credential model) and #270 (IAM
  probe); both closed green while being mutually incompatible.
- **HIGH — P2.** #216's presigned probe produced a real finding that was recorded in a test docblock and
  never escalated to the ticket record, so the milestone closed with a known open question.
- **MEDIUM — P3.** `plan-m5.md` §3's own new "named consumer + proving leg" rule was applied to the driver's
  key list but not to the new components that consume config in the same milestone.
- **MEDIUM — P4.** #280 scoped warning *frequency* and never considered warning *audience* — the omission
  that produced an unauthenticated disclosure.
- **MEDIUM — P5.** `presigned_expiry` is absent from plan §1's `s3` key list while the capability ships and
  works from one configuration seam.
- **LOW — P6.** Milestone #18 (M5R) is prepared but empty; the retrospective-review landing place has no
  entry criteria recorded.

---

## Findings detail

### P1. No ticket owned the interaction between the credential model and the IAM probe; both closed green while incompatible — HIGH *(verified)*

**What:** #248 (C1, resolve `secret_key_id`) and #250 (C3, strip persisted secrets) together made the Key-module
reference the canonical credential path and removed the literal secret from stored config. #270 (IAM probe) was
built in the same milestone and reads *only* the literal `credentials.key`/`secret`. Each ticket delivered its
own contract correctly. Their combination means bucket-IAM detection authenticates as nobody on every site
configured the canonical way — see code **C2**.

**Evidence:** All four tickets closed, all blockers closed. The dependency graph carries no edge between them:

```
$ # blockedBy for #270
#270 blocked_by #269 [CLOSED]   (its own T#)
```

`#270`'s only edge is its T# partner. Nothing ties it to #248 or #250, and nothing had to: `blocked_by` models
"X must start before Y", which was satisfied, not "X and Y must agree", which was not checked. The probe's T#
(#269) uses `MockHandler`-canned payloads through an overridden factory
(`BucketIamConflictDetectionTest.php:353`), so its legs are structurally incapable of exercising real credential
construction — correctly scoped for verdict logic, and blind to this by design.

**Impact:** This is the new failure class, and it is worth stating plainly because it is not the M4 class.
M4's defects were *intra*-ticket: a ticket claimed something its own code did not do. M5's is *inter*-ticket: two
tickets each did what they claimed and the seam between them was nobody's scope. Twenty-one pairs landed in one
milestone, fourteen of them corrective pairs touching the same credential and config surfaces, with no step that
asked "does this pair still hold given the other thirteen?" A per-ticket gate cannot catch this, and M5's
per-ticket gates were working.

**Fix:**
- File the C2+M2 corrective pair (code review §Disposition item 1) before M6 starts.
- Add a milestone-exit step, not a per-ticket one: for every milestone shipping more than a handful of pairs,
  an explicit integration pass that lists the config keys and seams multiple pairs touched, and one leg per
  shared seam exercising them together. For M5 that list would have been short — `credentials.*` was touched by
  #248, #250, #270, #275/#276 — and it would have caught C2.
- Record on #270 that its legs mock the factory and therefore do not cover credential construction (rule 11:
  the limitation belongs on the record, not only here).

### P2. #216's presigned probe produced a real finding that never left the test docblock — HIGH *(verified)*

**What:** The probe leg added under #216's amendment measured that the AsyncAws adapter implements
`TemporaryUrlGenerator` and signs without any presigned config key — while the `s3` driver declares no
`presigned_expiry` key, its schema does not allow one, and its form does not offer one. That is a genuine
three-seam inconsistency (code **H4**). It was written down in the test's docblock and nowhere else.

**Evidence:** `modules/flysystem_asyncaws/tests/src/Kernel/AsyncAwsSettingsPhpConfigTest.php:222-240`:

```php
 * Amendment probe question: the s3 contract declares no presigned key,
 * yet the league adapter implements TemporaryUrlGenerator. Measured
```

No M5 ticket records this finding, no M5R issue exists for it, and `plan-m5.md` §4 mentions the probe
("per #216's probe question — measure whether the adapter signs without a config key") without recording
its answer or a disposition.

**Impact:** The probe-first protocol worked — it asked the right question and got a real answer. The
gap protocol then did not run. `AGENTS.md` rule 12's GAP PROTOCOL requires a finding to be "called out on
the persistent record → discussed → ticket scoped → worked only on approval"; a test docblock is not the
persistent record, and the sequence stopped at step zero. The milestone closed with a shipped capability
unreachable from the supported configuration path and a documented-but-unowned question about it.

**Fix:**
- Post the probe's finding and its consequence as a comment on #216 and #215, then file the H4 pair in M5R.
- Tighten the protocol: a probe that returns an unexpected answer is a gap by definition and goes on the
  ticket record in the same session, before the leg is committed. The probe's value is in what it discovers;
  discovery recorded only in a docblock is discovery discarded.

### P3. §3's own "named consumer + proving leg" rule was scoped to the driver's key list, not to new config consumers — MEDIUM *(verified)*

**What:** `plan-m5.md` §3 carries the rule this project adopted after M4: "Every config-key line names its
consuming code path and its proving leg, not just the key name." It was applied to the `s3` driver's key list —
correctly, and it is why the `s3` driver has no unconsumed keys. It was not applied to the *new code that reads
config* in the same milestone: `BucketIamProbeFactory` consumes `credentials.key`, `credentials.secret`,
`endpoint`, `path_style_endpoint` and `region`, and no ticket checked that consumption against the key contract
those keys belong to.

**Evidence:** `modules/flysystem_aws/src/Iam/BucketIamProbeFactory.php:31-49` reads five config keys. The rule as
written in §3 governs "config-key line[s]" — i.e. plan-document key lists — and says nothing about components.
#270's record names its probe order and its excluded verdict (`PublicAccessBlock`) but not its credential inputs.

**Impact:** The rule was written to prevent a declared key from having no consumer. The inverse case — a consumer
reading keys it does not fully understand — was not covered, and that inverse is exactly code C2 and M2. A rule
aimed at one direction of the same relationship left the other direction open.

**Fix:** Restate the rule bidirectionally in `plan-m6.md` §3: every config key names its consumers **and** every
new component that reads config names the keys it reads and the contract it reads them under. When two components
read the same key, one of them owns the resolution and the other calls it — never two readers of the same raw
config (which is code M2's fix, generalized).

### P4. #280 scoped warning frequency and never considered audience — MEDIUM *(verified)*

**What:** #280 ("misconfigured-scheme operation failures warn onscreen once per request") scopes *how often* the
warning appears. Nothing in the ticket, its T# (#279), or the implementation considers *who* sees it. The
messenger call carries no permission check, so anonymous visitors on any public page rendering a file from a
misconfigured scheme are shown the scheme name and the missing config keys — see code **H2**.

**Evidence:** Both tickets closed with all blockers closed. The ticket title and the delivered code agree on
frequency (a per-instance `$reported` flag, correct) and are silent on audience. `MisconfiguredFilesystemAdapter::fail()`
calls `$this->messenger->addWarning(...)` unconditionally.

**Impact:** An unauthenticated information disclosure introduced by a ticket that did what it said. Worth
noting honestly: this ticket originated in my own M4 handoff draft (`planning/m4-corrections-handoff.md` §2.11),
which specified "aggregating one message across all rows" and never said "and gate it by permission." The
review that proposed the work carries part of this gap, not just the implementation.

**Fix:** File the H2 pair in M5R. Add to the M6 pre-flight: any ticket that adds a user-visible message states
its intended audience and the permission gating it, the same way tickets already state their proving leg.

### P5. `presigned_expiry` is absent from plan §1's `s3` key list while the capability ships — MEDIUM *(verified)*

**What:** `plan-m5.md` §1 enumerates the `s3` config-key set (`bucket`, `region`, `prefix`, `visibility`/
`default_visibility`, `endpoint`, `path_style_endpoint`, `send_chunked_body`, `credentials.*`, `use_acl`).
`presigned_expiry` is not there — deliberately, since §4 states "no CloudFront and no presigned scope" for `s3`.
But the capability exists in the adapter, the stream wrapper honors the key generically from settings.php, and
#216's probe proved it works.

**Evidence:** §1's key list; §4's "CloudFront: NO preserved key exists for `s3` — no CloudFront scope" (which
addresses CloudFront and is silent on presigned); `S3AdapterDriver::getConfigKeys()` with no presigned entry; and
the probe leg proving the adapter signs.

**Impact:** "Out of scope" and "reachable from one seam but not the other" are different states, and the plan
records the first while the code is in the second. That is the M4 P6 hazard (`visibility` vs `default_visibility`)
recurring in a new key: a value settings.php accepts and the config schema rejects is an M8 migration failure
waiting to be found.

**Fix:** Decide presigned for `s3` explicitly (code H4's `**Fix:**` gives the two coherent options) and record the
decision in `plan-m6.md` rather than amending the frozen M5 plan. If it stays out of scope, the settings.php path
must reject it loudly, not honor it silently.

### P6. Milestone #18 (M5R) is prepared but has no entry criteria recorded — LOW *(verified)*

**What:** `plan-m5.md` §1 records "milestone 18 (M5R Retrospective review issues) sits between M5 and M6 — review
issues from the independent code and plan review land there before M6 starts." The milestone exists and is empty
(0 open / 0 closed). Nothing records what qualifies for M5R versus M6 versus M9.

**Evidence:** Milestone API: `18|M5R Retrospective review issues|open=0|closed=0`. M4's equivalent findings were
distributed by severity judgment across M5 (14 pairs), M9 (#253/#254, #243) and M7 (#277/#278) with the rationale
living in the handoff document rather than in a milestone description.

**Impact:** Low — the mechanism worked for M4 without written criteria. It matters now because M5R is the first
milestone whose entire content is review output, and "before M6 starts" is a gate whose satisfaction needs a
definition. Without one, a CRITICAL and a LOW both look like M5R candidates.

**Fix:** Write two lines into the milestone description: CRITICAL and HIGH findings that M6 would inherit go to
M5R and block M6; MEDIUM and LOW go to M6 or later by judgment; anything needing an absent capability goes to M9.
This review's disposition already sorts that way — recording the rule makes it repeatable.

## What this review got right

Bounding the findings. The ticket record improved measurably against M4 on every axis I checked:

- **21 of 21 feature tickets carry a T# partner.** The zero-edge audit across all 45 issues returns eighteen
  tickets and **every one of them is a T#** — no feature ticket sits unpaired or unblocked. M4's single exception
  (#244, the README ticket) did not recur, and the response to that finding was to apply the rule rather than to
  carve out a docs exception.
- **Zero tickets closed with an open blocker, for the second milestone running.** Audited exhaustively across all
  45. This check has now held twice under delivery pressure with 45 and 59 tickets respectively.
- **The anti-#102-hole guard in plan §1 worked as designed.** It required the three claimed contract halves to be
  proven before #104 could close, and all three are pinned by real legs
  (`testUseAclSwitchResolvesAdapterClass()`, `testWrittenObjectsCarryDrupalMime()`, `testChecksumEqualsEtag()`).
  M4's pattern — claiming a half and proving it elsewhere or nowhere — was closed by a plan-level guard, which is
  the right altitude for that fix.
- **Every M4 review disposition is tracked, including the ones that were deferred rather than done.** Fourteen
  corrective pairs worked in-milestone; H4 parked in M9 as #253/#254 with the testability reason recorded; the
  benchmark item filed as #277; and #278 (evaluate SeaweedFS as a discriminating emulator) is a thoughtful
  addition nobody asked for — it attacks the root cause of the H4-class deferrals rather than the symptom.
- **The M4 retrospective's lessons were converted into gates, not just recorded.** `plan-m5.md` §3 carries the
  named-consumer rule, the per-seam-leg rule, the tests-never-provision rule, the explicit-test-methods rule, and
  the new Floci per-class key-prefix rule — each traceable to a specific prior failure. This is the exact
  correction `NOTES.md` said M4 had missed ("the corrective was recorded as a lesson rather than converted into a
  gate"), and it was made.
- **The Floci stale-object diagnosis is first-rate.** Two test classes sharing a bucket key prefix read each
  other's objects, passing locally against M4-written data and failing in CI. Finding that, and converting it into
  a mandatory per-class prefix constraint with the reasoning attached, prevents an entire category of false-green
  that would otherwise have recurred every milestone.
- **The testability policy in §3 is the right answer to a hard problem.** "Addressable now stays; unaddressable-or-
  unmockable defers to M9 with the reason recorded… A mocked leg must name its unmocked counterpart layer, or it is
  rejected at review." That last clause is what would have caught C2 had it been applied to #270's legs — the policy
  is correct and its application was incomplete, which is a much better position than not having it.

## Verification

```bash
# Milestone counts
gh api repos/codementality/flysystem-v4/milestones --paginate \
  -q '.[] | select(.number>=12) | "\(.number)|\(.title)|open=\(.open_issues)|closed=\(.closed_issues)"'
# → 16|M5 flysystem_asyncaws|open=0|closed=45 ; 18|M5R Retrospective review issues|open=0|closed=0

# The 45 issues
gh issue list -R codementality/flysystem-v4 --milestone "M5 flysystem_asyncaws" \
  --state all --limit 100 --json number,title,state -q '.[] | "\(.number)|\(.state)|\(.title)"' \
  | sort -t'|' -k1 -n
# → 45 rows, all CLOSED

# Closed-with-open-blocker audit (all 45, GraphQL blockedBy)
# → no output: every blocker of every M5 ticket is closed

# Zero-edge audit (all 45, blockedBy.totalCount == 0)
# → 18 tickets, every one a T#. No unpaired feature ticket.

# Parked / deferred threads
gh issue list -R codementality/flysystem-v4 --state all --limit 300 \
  --json number,title,state,milestone \
  -q '.[] | select(.number==243 or .number==253 or .number==254 or .number==277 or .number==278)
      | "#\(.number)|\(.state)|\(.milestone.title)|\(.title)"'
# → #253/#254 M9 Release (H4); #243 M9 Release; #277/#278 M7 Test hardening & CI

# P2 — the probe finding lives only in a docblock
grep -rn "presigned" modules/flysystem_asyncaws/tests/src/Kernel/AsyncAwsSettingsPhpConfigTest.php
# → :222-240, the probe leg and its recorded question

# P1 — #270 has no edge to the credential tickets
# blockedBy(#270) → #269 only (its own T#)
```

P1, P3, P4 and P5 are cross-verified in `planning/m5-code-review.md` (C2/M2, M2, H2 and H4 respectively).

## Disposition

**1(a) — Do the tickets worked cover all of the plan-m5 planning?** Yes, more completely than M4. Every §1 and §4
scope item has an owning ticket; the three contract halves were gated before #104 could close; every feature ticket
has a T# partner. One capability ships with no plan entry and no disposition (**P5**, presigned for `s3`), and one
probe finding was recorded outside the ticket record (**P2**).

**1(b) — Are there identifiable gaps in the work completed?** Yes, and they are a different kind than M4's. The
significant gap is **inter-ticket**: nothing checked whether pairs landing in the same milestone remained compatible
(**P1** / code C2), and the plan rule that would have covered it was scoped to one direction of the relationship
(**P3** / code M2). Two smaller gaps: a ticket that scoped frequency and not audience (**P4** / code H2), and a
recorded-but-unowned question (**P2** / code H4).

**Actions, by priority.** All ticket work targets milestone **18 (M5R)** or M6; `plan-m5.md` is frozen on close.

1. **P1** — file the C2+M2 corrective pair, and post on #270 that its legs mock the factory and do not cover
   credential construction. This is the one finding where the shipped state is worse than not having the feature.
2. **P2** — post the probe finding on #216/#215; file the H4 pair.
3. **P4** — file the H2 pair (permission-gate the onscreen warning).
4. **P3, P5** — record both as `plan-m6.md` amendments before M6's tickets are written: the bidirectional
   consumer rule, and the presigned-for-`s3` decision.
5. **P6** — two lines of entry criteria on milestone #18's description.

**One process amendment for `plan-m6.md`, and it is the only one that matters.** M5 proved that per-ticket
discipline works: 45 tickets, every pair gated, every blocker honored, every claimed half proven. The remaining
defects are all in the spaces *between* tickets, which no per-ticket gate can see. So:

> **Milestone integration pass (new, before a milestone may close).** List every config key, service, and seam
> that more than one pair in this milestone touched. For each, name one leg that exercises the combination — not
> the pairs separately. A milestone with more than a handful of pairs closes only when that list is empty or every
> entry has its leg. For M5 the list would have been one line long (`credentials.*`, touched by #248, #250, #270,
> #276) and it would have caught the milestone's only CRITICAL.
