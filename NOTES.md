# M4 Assessment — Reviewer's Grade and Reasoning

Written 2026-09-08 at the user's request, for their own review and process improvement. This is a
reviewer's judgment, not a project artifact: it grades the M4 milestone's work as delivered, and it is
deliberately blunt because a flattering grade would be useless for the purpose it was asked for.

Basis: `planning/m4-code-review.md` (14 code findings) and `planning/m4-project-review.md` (7 ticket
findings), plus the M4 milestone's 59 closed issues, `M4_RETROSPECTIVE.md`, and `planning/plan-m4.md`.

---

## Grade: B−

With a wide split between two axes, which is the actually useful part of the answer.

### Process discipline: A−

- **29 of 30 feature tickets went through the T# dance.** Rule 12 was applied consistently, including to
  all ten Core corrections (#171–#194), each of which has its own T# partner. The single exception is a
  documentation ticket — the most defensible place to slip, and it still cost two CRITICAL findings.
- **Zero tickets closed with an open `blocked_by`, across all 59.** This is the check most likely to
  buckle under delivery pressure, and the retrospective records it failing once already (#61, "green
  confused with complete"). It held for the rest of the milestone. Audited exhaustively, not sampled.
- **The Floci harness is honest test infrastructure.** It fails rather than skips when the emulator is
  absent, and asserts bucket existence rather than provisioning it — so a leg cannot pass over a broken
  environment. This is rarer than it should be; most projects write tests that quietly pass when their
  dependencies are missing.
- **Both static gates clean, with no new exclusions.** PHPStan level 8 and the canonical Drupal PHPCS
  ruleset, verified by running them.
- **The inline documentation explains *why*, not *what*.** The `NoAclAwsS3Adapter` docblock explaining
  why every private parent field is re-held in the subclass will save a future reader an hour. The
  `resolveLocalPath()` docblock naming which core semantics were adapted and which guards were added is
  the right shape, even where one of those guards turned out to be weaker than claimed (M4).
- **The retrospective is more honest than most postmortems.** Naming "motion over correctness",
  "theater tests", and "inference treated as authorization" against one's own work is not the norm.

### Verification of delivered behavior: C

- **The milestone was declared complete, with its exit criterion asserted as met, while the two
  configurations the shipped README instructs operators to use do not work.** Key-module credentials
  (C1) and a public bucket behind CloudFront configured through the UI (C2). Neither is an edge case;
  together they are the module's primary deployment shape.
- **A plaintext AWS secret access key reaches config sync (C3)**, while the driver's own docblock and
  the README both state it never does.
- **A closed ticket asserts a capability that does not exist (H1/P4).** #234's title claims IAM-conflict
  detection; nothing in the codebase reads bucket policy, ACL, or ownership state.
- **A shipped, documented, test-exercised config key does nothing (H3).** `send_chunked_body` is absent
  from the entire vendor tree, and its `FALSE` value is unrepresentable in the code that reads it. Two
  test files set it to `FALSE` and pass regardless — which is what makes it invisible.

---

## What actually pulls the grade down

Not the defect count. Fourteen findings across ~10,900 lines of new code is unremarkable, and most are
MEDIUM or below with concrete one-commit fixes.

Two things:

**1. All three CRITICALs are a single failure mode.** A config key declared in the driver's
`getConfigKeys()`, typed in the config schema, rendered in the form, round-tripped through save,
documented in the README — and consumed by nothing. Three keys, three CRITICALs, one root cause. That
is a systemic gap in what "done" means, not three independent mistakes. It means the definition of
covered was *declared and round-trips*, when it needed to be *consumed and proven*.

**2. The lesson had already been written down, in this same milestone, and was not applied.**
`M4_RETROSPECTIVE.md` §2.1 records exactly this failure about CloudFront:

> **Plan words posed as coverage (CloudFront).** The plan listed CloudFront URLs; no ticket owned the
> runtime wiring and no test pinned it. Words are not coverage: every plan scope item must name its
> owning ticket AND its proving leg, or it does not exist.

That diagnosis is correct and precisely stated. It was then not applied to `credentials.secret_key_id`,
to `send_chunked_body`, to `use_provider_key_management`, or to the entity-seam half of CloudFront
itself. **Recurrence after accurate diagnosis is worse than the original miss** — it means the
corrective was recorded as a lesson rather than converted into a gate.

---

## Caveats on this grade

Stated so the assessment can be weighed properly rather than taken at face value:

- **I ran only the static gates, not the test suite.** My read of runtime behavior is inference from
  source in several places. Four findings are marked `*(reviewed)*` rather than `*(verified)*` for that
  reason — including C2, one of the three CRITICALs. Each carries a "Refuted if" check in
  `planning/m4-corrections-handoff.md`, and C2's in particular may not survive it. If it does not, the
  execution axis moves up.
- **I have seen M4 only**, not M1–M3. This grade describes one milestone, not the project. The Core
  code M4 touched looked well-built, which is weak evidence that the earlier milestones are stronger
  than this one — but it is only weak evidence.
- **I am grading the work, not the constraints it was done under.** I have no visibility into what was
  traded away against time or budget.

---

## The one change that would move this to an A

**None of the fourteen findings is catchable by the gates currently in the pipeline.** PHPCS, PHPStan
level 8, and the full PHPUnit suite all pass with every one of them present. That is the whole problem
in one sentence, and it means the fix is not "be more careful" — it is a missing gate.

The missing gate: **for every shipped config key, one leg that executes the documented configuration end
to end and asserts the behavior the documentation promises.** Not that the key round-trips through save
— that it is read, and that what it claims to control changes. Concretely, for M4 that would have been:

- Execute the README's own settings.php snippet and round-trip a file → catches C1 (and would have
  blocked #244 from shipping false documentation).
- Save a public scheme through the form with CloudFront and assert the emitted URL → catches C2.
- Assert the saved entity contains no value at any `secret: TRUE` path → catches C3.
- Assert the built `S3Client`'s resolved configuration for both states of the chunked-body flag →
  catches H3.

Four legs. Three CRITICALs and a HIGH. The rule generalizes as: **a config key is not covered until a
test proves something downstream of reading it.** Two amendments in
`planning/m4-corrections-handoff.md` §4 propose exactly this for `plan-m5.md`, which is worth applying
before M5's #105/#216 are worked — the `s3` driver inherits the same credential and chunked-body
surfaces, so the same three defects will port forward otherwise.

A secondary, cheaper gate, from the retrospective's own §2.7 (root/non-root divergence): **any config
key settable from both settings.php and the admin form needs a leg per seam.** The two paths diverge
because the form materializes `#default_value`s that settings.php never supplies. That divergence is
where C2 lives, and it is why 59 closed tickets did not find it.
