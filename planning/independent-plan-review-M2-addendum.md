# Flysystem v4 — Independent Plan Review, M2: Addendum of Decisions & Deviations

Status: **Decisions recorded**, 2026-08-31. Companion to
[independent-plan-review-M2.md](independent-plan-review-M2.md). This document records, for the
record, every place the project diverged from the review's recommendations, and the resulting
disposition of each item. Where the reviewer (the agent) and the user disagreed, the user's decision
is final and is stated as such.

---

## B1 — C8 (`allow_url_fopen` / `STREAM_IS_URL`): fail-install vs. WARN vs. user directive

- **Review's fix:** a `hook_requirements()` entry **failing** installation when `allow_url_fopen` is
  off and a remote scheme is configured; plus a recorded decision on following 3.0's "register
  without the flag".
- **Agent proposal (rejected):** soften to a **WARN** — local schemes still work under
  `allow_url_fopen=0` (they register with flag 0), so failing install would break legitimately
  local-only setups.
- **User directive (2026-08-31):** reject the WARN. `allow_url_fopen` off is a *legitimate security
  posture* and is common on Drupal hosting; there are more secure ways to serve local files without
  enabling it. **The module must function with `allow_url_fopen` disabled.**
- **Disposition:** folded into **#27** (M7) with the directive that the resolution makes remote
  schemes operational under `allow_url_fopen=0` — revisit the `STREAM_IS_URL` registration decision
  toward 3.0 parity (register without the flag), not a warning/failure path.

## B3 — C12b folded into C5 (agent/review deviation, user-approved)

- The review lists range semantics (suffix ranges, 416, multi-range detection) as a separate
  disposition item.
- Agreed: fold **C12b** into the **C5** streaming ticket — both live in the same
  `streamFromAdapter()` code the C5 rewrite replaces. One ticket, referencing C12 in scope. The C5
  ticket is **#134**.

## B4 — C7 parked behind the code-level `@todo` (user decision)

- The review recommends ticketing private-scheme resolution (probe cost, first-match-wins, prefix
  round-trip mismatch).
- **User decision (2026-08-31):** the scheme-resolution concern stays parked behind the `@todo
  Review for performance implications` in `PrivateDownloadController::download()`, revised to
  reference **C7** in independent-plan-review-M2.md. All `@todos` are revisited at the end of the
  project (or before) for a determination. **No C7 ticket in M3.** This parks C7.2 (first-match-wins)
  and C7.3 (prefixed-scheme 404) correctness concerns as well, by user decision, on the record.

## D — Form/Plugin test coverage (0%)

- The review asks to confirm whether `Form/`/`Plugin/` at 0% is a coverage-instrumentation artifact
  and to note it in the coverage README.
- **User note (2026-08-31):** the gap is on the user's radar and expected to surface naturally from
  the adapter-specific work (M4/M5/M6 submodules). No separate ticket now; the artifact question is
  revisited when that work lands.

## A4 — Release gating: submodules ship with 4.0 (user decision)

- **User decision (2026-08-31):** the three adapter submodules (flysystem_aws, flysystem_asyncaws,
  flysystem_sftpv3) are **submodules of this module** — included with the codebase, optionally
  enabled — and ship with the 4.0 release. They are not separate contrib modules.
- **Disposition:** added `blocked_by` edges from #36 to #100, #102, #104, #106, #108, #109, #110,
  #119, #120 (T# pairs #101/#103/#105/#107 follow transitively). Verified via GraphQL:
  `issue(number: 36).blockedBy` now contains all nine plus the 26 pre-existing blockers (35 direct).
- **Closure verified:** a transitive walk of #36's `blockedBy` now covers every pre-existing open
  issue. The only open issues outside the closure are the 18 tickets created from this review
  (#121–#138); whether those C1–C12 defect tickets also gate the release is left to the user (not
  auto-added).
- **Process note:** the REST endpoint `GET /issues/36/dependencies/blocked_by` returned a stale view
  during this work; the GraphQL `blockedBy` field is authoritative. `gh issue edit --add-blocked-by`
  writes through GraphQL. Lesson recorded in `LESSONS_LEARNED.md`.

## A2 — Read-only enforcement: #18 rescoped, #55 closed

- **Finding:** read-only enforcement shipped inside M2 slice 4 (#11/#48, commits `3a5b198`/`24d5f0b`)
  while its M3 tickets #18/#55 stayed open.
- **Disposition (user-approved):** #18's body rewritten to name only the residue (configuration form
  checkbox surface + documentation), noting the delivering commit; **#55 closed as satisfied** by
  `ReadOnlySchemeTest` (the red-before-green dance was honored under T11, not #55). #18 remains
  `blocked_by` #78 (Core drivers).

## A5 — Document hygiene

- **#35 retitled** "M6: Adapter-plugin developer README" → **"M9: Adapter-plugin developer README"**
  (milestone already M9 Release). Residue of the adapter-submodules renumbering.
- **plan-m2.md §3 and §4 brought into line with §2.1:** §3 now states all M2 dependencies resolved;
  §4 slices 8 and 9 marked DONE (were "GREEN COMPLETE, IN REVIEW / uncommitted"), and §4 flagged
  explicitly historical.

---

## What this review produced

18 new M3 tickets (all milestone **M3 Adapter hardening**, all in board **Backlog**, feature
`blocked_by` its T# pair):

| T# | Feature |
|---|---|
| #121 | #130 — C1 Cross-scheme `copy()/move()` |
| #122 | #131 — C2 `FileExists` + `getDestinationFilename()` |
| #123 | #132 — C3 Append/update `fopen()` modes |
| #124 | #133 — C4 Wire `StatCache` (+C12f/h) |
| #125 | #134 — C5 Stream the private download (+C12b) |
| #126 | #135 — C6 Restore `hook_file_download` headers |
| #127 | #136 — C9 `getExternalUrl()` config error |
| #128 | #137 — C10 `reportFailure()` in silent catches |
| #129 | #138 — C12 Cleanup (a/c/d/e/g) |

Plus: #27 scope expanded (C8 + C11, M7), and the M2-completion actions above.