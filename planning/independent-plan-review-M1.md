# Flysystem v4 — Independent Plan Review (board vs. planning docs)

Status: **Review**, 2026-08-29. Companions: `architecture.md`, `testing.md`, `migration.md`, `config-and-upgrade.md`, `feature-evaluation-log.md`, `drupal-issue-queue.md`, `plan-m1.md`, `docs/agents/board.md`.

## Remediation status (2026-08-29, applied by agent at user direction)

All findings remediated. Summary of the board changes:

- **A1–A4, A6**: gap tickets + T# pairs filed — #79/#85 (wrapper skeleton), #80/#86 (decorated `file_system`), #81/#87 (private download route), #82/#88 (`flysystem:reconcile`), #89 (T78 drivers), #90/#91/#92 (T73/T76/T77).
- **A5**: #83 (Section-B `[relevant]` disposition pass). **A6 decision**: no T#-dance exemptions (user directive 2026-08-29).
- **F1**: #36 (release) now gated on every open feature ticket — `blocked_by` edges added for the M3/M4/M5 exits and follow-ups; transitive closure recomputed and verified to cover all open tickets.
- **C1/F3**: #78 now blocks 10 consumers (#17/#19/#20/#21/#24/#76/#82/#72/#84/#36); body↔edge drift synced for #74/#73/#42/#78.
- **C2/C3**: #70 split — reachability stays M0 (unblocked → Ready); ACL-disabled scenario split to #84 (M3).
- **C4**: #72 (D12 matrix) moved before #36 (release now blocked by #72); milestone → M4; `architecture.md` §12 + `testing.md` §8 reconciled.
- **C5**: #75/#77 → Ready; #72 `dependency-blocked`; `seam:*` propagated to all T# tickets.
- **B**: #2 title/body corrected (Form CORE, PHP >=8.4), #25 title fixed, #3 checkboxes ticked.

## Context

The @codementality Flysystem 4.0 board (Projects v2 #11, repo `codementality/flysystem-v4`) holds 78 items: 11 Done, 2 Ready, 64 Backlog, 1 Needs triage. The backlog was seeded from six planning documents in [planning/](planning/) at design freeze (2026-08-28), then amended during M1 execution when two unowned deliverables surfaced (#74 config entity, #78 shipped drivers).

The request: compare the board against the planning documents and identify gaps that would prevent the work from completing successfully.

The review found **six unowned deliverables** (work the docs require that no ticket covers, section A), **four consistency defects** (tickets that contradict the docs or themselves, section B), and **five dependency/board-hygiene errors** (section C). Sections **E** and **F** were added after two follow-up sweeps: all 78 issues' comment threads, and a full census of all 78 issues' dependency edges.

The two most consequential findings:

1. **#36 (4.0 release) is not gated on the work that defines it** — 50 issues sit outside the transitive closure of its blockers, including the four production adapter drivers, the Floci integration layer, the Section-A regression suite, and the entire migration submodule (F1).
2. **`FlysystemStreamWrapper`, the single most load-bearing class in the design, has no ticket** (A1).

**Coverage of this review**: docs → tickets is complete (every numbered section of all six planning docs plus `plan-m1.md`, checked against all 78 bodies). Tickets → graph is now complete (all 78 edge lists, section F). Comments are now complete (all 78 threads, section E). Not audited: whether any ticket specifies work the docs do *not* call for, and the internal consistency of all 78 milestone assignments.

---

## A. Unowned deliverables

These are the same failure mode that produced #74 and #78: the docs require it, the milestone exit criteria assume it, no ticket owns it.

### A1. `FlysystemStreamWrapper` — the wrapper class itself (CRITICAL)

`architecture.md` §3.1 calls the contract-faithful wrapper "load-bearing": a single generic class implementing the full `StreamWrapperInterface` + `PhpStreamWrapperInterface`, **self-sufficient outside the container** (static bootstrap from the URI alone, because PHP instantiates wrappers directly for `move_uploaded_file()` / `is_dir()` / `fopen()` — the root cause of #3616485).

No ticket creates this class.

- #7 (M1 exit) decorates `stream_wrapper_manager` so it "returns the flysystem wrapper" — a class that does not exist and that #7 does not scope.
- #8–#16 each *harden a facet* of the wrapper (stat, getType, URL, write, read, cache, temp, local-path, exceptions). None owns the class, its constructor/bootstrap, or the stream methods no facet ticket names: `stream_open`/`close`/`eof`/`tell`/`stat`/`truncate`/`lock`/`set_option`, `dir_opendir`/`dir_readdir`/`dir_rewinddir`/`dir_closedir`, `mkdir`/`rmdir`/`unlink`/`stream_rename`.
- `plan-m1.md` §4 says "the wrapper can be a thin stub resolving the scheme; M2 hardens it" — an instruction with no ticket behind it.
- The static self-bootstrap (§3.1, the #3616485 fix) appears only as a *regression test* in #26 (M4). Nothing implements it.

**Fix:** new M1 ticket + its T# — "M1: `FlysystemStreamWrapper` skeleton + static self-bootstrap + directory operations", blocking #7 and every M2 facet ticket.

### A2. The decorated `file_system` service

`testing.md` §2 names it as **seam 3** (`copy`/`move`/`saveData`/`delete`/`getDestinationFilename`, `FileException` mapping, `deleteRecursive` correctness). `architecture.md` §4.8 and §5 boundary 2 both depend on it. #15 and #16 carry the `seam:file-system` label and *assume* the decorator exists ("the decorated `file_system` routes around them"), but neither scopes creating the service, and no ticket covers the `copy`/`move`/`saveData`/`getDestinationFilename` surface that seam 3 names.

**Fix:** new M2 ticket + T# — "M2: Decorated `file_system` service (`FileSystemInterface` seam)", blocking #15 and #16.

### A3. The private-scheme download route

`architecture.md` §4.3 routes private content "via the `file_download` route (streams adapter → PHP → browser)". `feature-evaluation-log.md` Item 9 goes further: *"Harden the private streaming route instead (Range/206 support, correct headers, cache metadata)."* Issue #3618271 (private `getExternalUrl` → unregistered route) is the 3.0 defect this closes.

#10 only *generates* the private URL. #26 only *regression-tests* #3618271. Nothing registers the route, writes the controller, streams from the adapter, implements Range/206, or wires `hook_file_download` access checks. A remote `private://` scheme cannot serve a file without this.

**Fix:** new M2 (or M3) ticket + T# — "Private file-download route + controller (streaming, Range/206, access checks)".

### A4. The `flysystem:reconcile` capability

`migration.md` §5: *"v4 carries reconcile forward as its own capability."* `feature-evaluation-log.md` Item 3 lists the reconcile command as a checksum-API consumer; `architecture.md` §14 lists it as a `listContents` consumer; `drupal-issue-queue.md` records it as shipped 3.0 feature #3610035.

No ticket. M5 covers migration only (#28–#33), which the docs explicitly call *a different concern*.

**Fix:** new M5 ticket + T# — "M5: `flysystem:reconcile` drush command (File/Media entities from unmanaged remote files)". Alternatively record an explicit deferral decision; silently dropping a shipped 3.0 capability is a regression.

### A5. Section-B issue-queue disposition

#26 covers `drupal-issue-queue.md` **Section A** only. Section B carries ~15 items tagged `[relevant]` — explicitly "Drupal-side, still relevant to 4.0" — with no ticket and no recorded disposition. Several are behavioral and land squarely inside scoped work:

- `getExternalUrl` prefixes language to file URL when multilingual — *"must carry into 4.0's hardened URL path"* (synthesis §3), yet absent from #10's body.
- #3513799 image-style generation for non-local drivers; #3457193 `required_derivative_scheme` (#22 covers the latter only).
- #3379832 `swapDumper` / `file_additional_public_schemes`; #3497516 / #3415603 CollectionOptimizer removal — the design assumes core `assets://` supersedes these, but that assumption is never recorded as a decision.
- #3109940 requirements check on install; #3498194/#3498720 route requirement boolean-as-string; #2661588 local image styles until remote upload completes.

**Fix:** one triage ticket — "Section-B `[relevant]` disposition pass" — routing each item to *covered by #N* / *new ticket* / *explicitly out of scope*. Then fold the multilingual case into #10 and #47.

### A6. `#78` has no red-test ticket

Every feature ticket #4–#33 has a paired T# per the two-ticket dance in [docs/agents/board.md](docs/agents/board.md). #78 — the four production adapter drivers, the module's entire reason for existing — has none. #73, #76, #77 likewise, though those are smaller.

**Fix:** create T78, and decide explicitly whether the small M1 follow-ups (#73/#76/#77) are exempt from the dance.

---

## B. Consistency defects in existing tickets

| # | Defect |
|---|---|
| **#2** (Done) | Title and body say **"Project-root phpunit.xml (Form ROOT)"**. `plan-m1.md` §1 and `testing.md` §6 mandate **Form CORE — no project-root phpunit.xml**. The docs were corrected (commit 3e7a59f, "Fixing broken test commands"); the closed ticket still records the wrong contract and will mislead anyone reading the M1 history. |
| **#2** (Done) | Body says **"PHP >=8.5"**. `plan-m1.md` §1 pins `>=8.4` (a `^11.4` module must install on 8.4) and #72 tracks the raise to 8.5. Same stale-record problem; also contradicts `architecture.md` §12, which still says `>=8.5` without the 8.4 carve-out. Worth reconciling the doc, not just the ticket. |
| **#25** (Done) | Title still reads **"D11.4 + D12, PHP 8.5, PHPUnit 11"**; the body was rewritten to D11.4/PHP 8.4 only, with D12 split to #72. Title/body contradict each other on a closed ticket. |
| **#3** (Done) | Closed with all three scope checkboxes unchecked (`[ ]`). Either they were done and not ticked, or closed prematurely — unverifiable from the record. |

---

## C. Sequencing and dependency errors

### C1. #78's blocking edges are almost entirely missing (highest-impact board error)

#78's body names six consumers: #17, #19, #20, #21, #24, #76. The native dependency graph records **`blocking: 1`** (only #76). So #17/#19/#20/#21/#24 will present as startable the moment their listed blockers close — while the four adapters they need do not exist. The board will hand out work that cannot be done.

**Fix:** add `blocked_by` edges from #17, #19, #20, #21, #24 → #78.

### C2. #78 is stranded in Needs triage

It carries `planning gap identified` and no `seam:*` label. Per [docs/agents/board.md](docs/agents/board.md), `planning gap identified` items "wait in Needs triage for routing into a milestone/owner". It is nominally M3, but blocks #70 (an **M0** ticket) and #76 (an **M1** ticket) — so its milestone is wrong, and it is on the critical path of three milestones while formally untriaged.

### C3. #70 is an M0 ticket blocked by an M3 ticket

"M0: Floci local test setup" is blocked by #17 (M3 visibility/`use_acl`) and #4/#2. An M0 ticket that cannot finish until M3 is a milestone misassignment — either re-milestone #70 to M3/M4, or split the reachability check (doable now) from the ACL-disabled-bucket scenario (needs #17/#78). Its body also says *"kept In progress"* while the board shows it in **Backlog** — body/board drift.

### C4. 4.0 ships claiming D12 support without ever testing D12

`architecture.md` §12 mandates `core_version_requirement: ^11.4 || ^12`. #72 (D12 matrix expansion) is `blocked_by` **#36** — "config-and-upgrade verification + **4.0 release**". So the D12 leg runs only *after* release. `testing.md` §8 M4's exit criterion is "**CI green on both majors**", which #25's rescope silently abandoned. Either move #72 before #36 (and restore the M4 exit criterion), or amend `testing.md`/`architecture.md` to state that 4.0.0 ships D11-only and D12 support follows.

### C5. Board hygiene — three label/column errors

- **#75, #77**: `blocked_by: 0`, no `dependency-blocked` label, blocker #74 closed — but sitting in **Backlog**. Per board.md they belong in **Ready**.
- **#72**: `blocked_by: 1` (#36, open, unstarted) but **no `dependency-blocked` label**, contradicting the labelling rule.
- No T# ticket carries a `seam:*` label while every feature ticket does. Cosmetic, but it breaks seam-based filtering across exactly the tickets that define the seams.

---

## E. Comment sweep (added 2026-08-29)

The first pass read ticket bodies only. All 78 issues' comment threads were then fetched — **23 comments across 12 issues** (#1, #2, #3, #4, #25, #37, #38, #39, #40, #41, #70, #74); the other 66 issues have none.

**Effect on section A: none.** No comment on any issue records a decision, deferral, or scope note covering the six unowned deliverables. A1–A6 stand as written.

**Effect on section B: two findings soften.**

- **#2 / PHP floor — downgrade to record-keeping.** A #2 comment (2026-08-28) does capture the correction: *"`_TARGET_PHP: '8.4'` (module php >=8.4 until D12-ready)"*. The decision was made and is traceable; only the ticket body and `architecture.md` §12 still say 8.5. Reconciling the doc (step 6 below) remains worthwhile; the ticket is stale, not wrong-and-undetected.
- **#3 / unchecked boxes — downgrade to hygiene.** A closing comment states *"Both scope items complete"* and names the commit (10cd03e) and the added test. Not a premature closure; just unticked boxes.
- **#2 / "Form ROOT" phpunit.xml — unchanged.** No comment anywhere addresses this. The closed ticket still asserts a contract that `plan-m1.md` §1 and `testing.md` §6 directly contradict, and nothing in the record flags it.

**Incidental**: a #70 comment (2026-08-28) notes its remaining items are blocked on code sitting on an **`unapproved-code` branch, not merged**. Worth confirming that branch's state is tracked somewhere; it is not visible on the board.

## F. Dependency census (added 2026-08-29)

The first pass sampled 8 of 78 dependency summaries. All 78 issues' `blocked_by` and `blocking` edge lists were then pulled in full. C1 is confirmed, and the census exposed a larger structural error.

### F1. The 4.0 release is not gated on the work that defines it (CRITICAL — supersedes C1 in severity)

**#36** ("Config-and-upgrade verification + 4.0 release", the M6 exit criterion) is `blocked_by` **only #1, #34, #35** — the design-freeze ticket and the two documentation tickets. Computing the full transitive closure of #36's blockers gives:

```
{1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 17, 18, 34, 35, 37, 38,
 40, 41, 42, 43, 44, 45, 47, 48, 54, 55, 74}
```

Everything else — **50 issues** — can be open when #36 becomes startable. Excluded from the release gate, by milestone:

| Milestone | Not gating the release |
|---|---|
| M2 | #9 `getType()`, #12 read path, #13 stat cache, #14 `temporary://`, #15 local-path contract, #16 exception strategy |
| M3 | #19 mime-on-write, #20 GD staging, #21 ImageMagick staging, #22 image-style routes, #23 checksum API, **#78 the four shipped adapter drivers** |
| M4 | #24 Floci integration, #26 Section-A regression coverage, #27 contract determinations, #70/#71 Floci setup |
| M5 | #28–#33 — the entire migration submodule |

So as the graph currently stands, 4.0 can reach its release gate with **no production adapters**, no Floci integration layer, no migration submodule, and none of the Section-A regression coverage that *is* the M4 exit criterion in `testing.md` §8. This is the same class of defect as C1 (bodies assert dependencies the graph does not hold), but at the release boundary rather than a single ticket.

**Fix:** add `blocked_by` edges from #36 to each milestone's exit ticket — at minimum #24, #26, #27, #33, #78 — so the release inherits the whole tree. Then re-verify the closure covers every open feature ticket.

### F2. Nine tickets are terminal leaves that should not be

#19, #20, #21, #22, #25, #26, #27, #32, #33 have **`blocking: (none)`** — nothing depends on them. For the M4 and M5 exit tickets (#26, #27, #33) and the M3 integration work this is the F1 defect seen from the other end.

### F3. Body / graph drift — four cases

`docs/agents/issue-tracker.md` requires bodies and edges to stay in sync ("Whenever edges change, update the matching 'Depends on' line in the body so the two never drift"). Four violations:

| Issue | Body says | Graph holds |
|---|---|---|
| **#78** | six consumers (#17, #19, #20, #21, #24, #76) | `blocking: 76` only — the C1 finding, confirmed against the full census |
| **#74** | "Blocked by #4 (adapter plugin system — **closed**)" | no `blocked_by` edges at all |
| **#73** | blocked by #5, and "its own red tests (T5/#42) must be done first" | `blocked_by: 5` only |
| **#42** | "Depends on: #1, #2, #37, #3, #4" | also `blocked_by: 74` — edge added later, body never updated |

Only #78's drift is behaviourally dangerous (it hands out unworkable tickets); the other three are record-keeping.

### F4. What the census confirmed as correct

Worth stating, since it bounds the problem: the T#↔feature pairing is intact across the board (every feature ticket #4–#33 is `blocked_by` its T#, and every T# is `blocked_by` its feature's predecessors), there are **no dependency cycles**, and the #1/#2/#37 boilerplate triple is applied consistently. C5's specific label findings (#72 missing `dependency-blocked`; #75/#77 unblocked but parked in Backlog) are confirmed against the full census, and no further label/edge mismatches were found.

---

## D. Recommended execution order

*(Revised after the two sweeps — F1 now leads.)*

1. **Gate the release (F1)** — add `blocked_by` edges from #36 to #24, #26, #27, #33, #78 at minimum, then recompute the closure and confirm it covers every open feature ticket. Until this is done the board will green-light a release over an unbuilt module.
2. **Unblock the lie (C1, C2, F3)** — add the five missing `blocked_by` edges to #78, give it a `seam:adapter-plugin` label, route it out of Needs triage into a milestone; fix the #74/#73/#42 body-vs-edge drift.
3. **File A1** (wrapper class + T#) and wire it as a blocker of #7 and #8–#16. This is the one gap that stops M1/M2 outright.
4. **File A2, A3** (decorated `file_system`; private download route) into M2 with their T# pairs and edges.
5. **File A4, A5, A6** (reconcile; Section-B triage; T78) — or record explicit deferral decisions for A4/A5.
6. **Fix B and C3–C5** — ticket text corrections (#2's "Form ROOT" first; #2 PHP floor and #3 checkboxes are hygiene per section E), #70 re-milestone/split, #72 ordering decision, label/column corrections.
7. **Reconcile the docs the review exposed**: `architecture.md` §12 PHP floor (8.5 vs 8.4), and `testing.md` §8 M4's "green on both majors" exit criterion vs the #25/#72 split.

**Board mutations must follow the dry-run protocol** in [docs/agents/board.md](docs/agents/board.md): fetch fresh state immediately before operating, present the computed change-set for approval, apply, then re-read and verify.

---

## Verification

Nothing here changes code, so verification is board-state assertions:

```bash
# F1 — the transitive closure of #36's blockers must cover every open feature ticket
for n in $(seq 1 78); do
  echo "$n|$(gh api repos/codementality/flysystem-v4/issues/$n/dependencies/blocked_by \
    --jq '[.[].number]|sort|join(",")' 2>/dev/null)"
done
# then walk the closure from 36; expect #24, #26, #27, #33, #78 inside it

# C1 — #78 must block six issues, not one
gh api repos/codementality/flysystem-v4/issues/78 --jq '.issue_dependencies_summary'
# expect blocking: 6

# C5 — no open issue with blockers may lack the label, and vice versa
gh issue list -R codementality/flysystem-v4 --state open --limit 100 \
  --json number,labels --jq '.[] | {n:.number, l:[.labels[].name]}'
# cross-check each against .issue_dependencies_summary.blocked_by

# A1–A6 — every new ticket has a T# pair and correct edges
gh issue list -R codementality/flysystem-v4 --state open --search "wrapper skeleton"
```

Re-read the board (`gh project item-list 11 --owner codementality`) after any mutation and diff against the approved change-set.
