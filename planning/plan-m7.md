# M7 — Test Hardening & CI (the adapter carve-out's renumbered original-M4): Execution Contract

Scope: the M7 milestone tickets (GitHub milestone "M7 Test hardening & CI", 20 open / 1 closed,
verified via REST 2026-09-12) and their dependencies. Source of truth: `adapter-submodules.md`
(§renumbering: the original M4 "Test hardening & CI" phase renumbered to M7 after the adapter
submodules carved out to M4–M6), `testing.md` (§1 two layers, §2 reds-first, §5 CI gates,
§8 milestones), `architecture.md` (§1–§11 behavioral contracts), `drupal-issue-queue.md`
(tickets #62/#26/#27/#63 pairs), `plan-m4.md`/`plan-m5.md`/`plan-m6.md` §6 as-built records
(the proven patterns M7 inherits). Milestone exit criteria in §5. This document is the LIVING
execution contract for M7. Status: M7 unstarted (drafted 2026-09-12, gated on M6 closure and an
independent plan review).

---

## 1. M7 goal and boundary

M7 delivers the last pre-release hardening block: everything that makes the module
**verified against real-3.0 behavior, contract-complete, D12-ready, and CI-enforced** —
after the functional submodules (aws_s3, s3, sftp) shipped with their suites in M4–M6.

**In M7 (by ticket, grouped):**

1. **Regression-prevention coverage (Section-A, #26/#62):** every drupal.org 3.0 issue from
   `drupal-issue-queue.md` Section-A marked [relevant] — a proving leg that fails if the 4.0
   code regresses the same defect. T26 first (reds), then #26.
2. **Contract-violation determinations + status checks (#27/#63):** T27 reds first — the
   connection/status surface (the M3 review's finding: `testConnection()` has no production
   caller; `connection_status`/`connection_status_message` fields never written — these
   tickets restore the pair's consumer). #26/#27 are Core; the UI surface is the connection
   test button + the requirements table.
3. **Section-B [relevant] disposition pass (#83):** remaining v3-queue issues triaged
   "relevant"; each gets a pin or a recorded not-applicable rationale (archive of the doc).
4. **D12 test-matrix expansion (#72):** module `core_version_requirement` and CI matrix gain
   the Drupal 12 / PHP 8.5 leg (PHPUnit 11); correcting the standing posture (D11.4-only in
   CI to date). The D12-COMPAT findings pinned during M4–M6 (`RunTestsInSeparateProcesses`
   across Kernel/Functional/FunctionalJS classes, `FileExists` enum-only, no
   `@dataProvider`, `withConsecutive`-free mocks) carry to BOTH majors unchanged, so the
   matrix expansion is CI-leg and compat verification, not code churn.
5. **The split-red blocks M1–M6 / L1–L6 (pairs already filed):**
   - #195/#196 `deleteRecursive()` single file (M1/M1-T).
   - #197/#198 C9 requirements entry severity + translations (M5 pair).
   - #199/#200 stat_cache_ttl Admin-UI config leg (M6 pair) — schema + default + form.
   - #201/#202 memoized settings-sourced definitions (L2 pair) — **CONFLICT on record: the
     M4 lesson `SETTINGS_PHP_READ_LIVE_NOT_MEMOIZED` binds settings reads LIVE (the kernel
     post-boot mutation); implementation research must reconcile #202 against that lesson
     or the pair gets re-scoped with the user before it starts.**
   - #203/#204 L3 private-download exception boundary (404 on adapter failure).
   - #205/#206 L4 canonical phpunit `--display-phpunit-deprecations` (tooling).
   - Benchmarks/probes feeding M8/M9, explicitly NOT codified as legs: #277 (stat-cache tag
     invalidation benchmark) and #278 (SeaweedFS as a discriminating S3 emulator,
     H4-class-gap pre-work, license-clean alternative scan).

**No in M7:** the migration submodule (M8), release/upgrade-guide prose beyond the README
already shipped with the sftp BC section (M9), new adapter drivers, and ANY change to
M4/M5/M6 code unless a Section-A/B determination names it (those submodules are milestone-
immutable; a fix there re-opens the finding as a comment/issue, never silently).

---

## 2. Open tickets and edges (verified via REST 2026-09-12)

Milestone 12 — 20 open / 1 closed (#71, the Floci GitLab CI spike+doc, closed).

| Ticket pair | What it is | Class | Note |
|---|---|---|---|
| **#62 / #26** | T26 / Section-A regression-prevention coverage | Core | determinations first, then legs |
| **#63 / #27** | T27 / contract-violation determinations + status checks | Core | the M3 MEDIUM: connection test pair |
| **#83** | Section-B [relevant] disposition pass | Core | after #62/#63 (their output feeds it) |
| **#72** | D12 test-matrix expansion | CI | pipeline + core_version_requirement |
| **#195 / #196** | TM1 / M1 `deleteRecursive` single file | Core | red first |
| **#197 / #198** | TM5 / M5 C9 requirements severity+translations | Core | likely verify-and-close (M4 #257/#260 landed) |
| **#199 / #200** | TM6 / M6 `stat_cache_ttl` config leg | Core | red first (schema+default+form) |
| **#201 / #202** | TL2 / L2 memoized settings-sourced definitions | Core | **re-scope check per the settings-live lesson** |
| **#203 / #204** | TL3 / L3 private download 404 boundary | Core | red first |
| **#205 / #206** | TL4 / L4 phpunit deprecations display | tooling | dev-facing, no runtime leg |
| **#277, #278** | stat-cache bench; SeaweedFS probe | research | no codified legs; informal probe tickets |

Board columns for these neighbors move as the gate opens (M6 closure + reconciliation):
T-reds (#62/#63/#195+#197+#199/#203/#205 T-parts) → Ready; the M-side implementations wait
behind their pair edges; nothing in M7 is In progress before M6's integration pass clears.

---

## 3. Work order (deepest unstarted blocker first; each step needs the user's explicit go)

**M6 closure first** (milestone integration pass + §5 check; nothing in M7 moves before the
M6 column reads 0 open AND the integration pass legs exist). Then, red-first, pair by pair:

1. **#62 (T26 reds)** — Section-A determinations consumed by #26's implementation;
   `drupal-issue-queue.md` gets the per-pin disposition notes.
2. **#63 (T27 reds)** — the contract-violation + status-check seam map (entity fields +
   connection-test + requirements).
3. **#27** (implementation, gates on #63 approved + #62 approval state).
4. **#26** (implementation, gates on #62 approved + #63 approval state).
5. **#83** (Section-B pass, consumes #62/#63 evidence).
6. **#196** + **#198** legs (verify-or-red calls; #198 expected verify-and-close — record it
   as the M4-inherited pin), then **#200** (stat_cache_ttl red → green), then **#204** (L3 red →
   implement), then **#206** (tooling), then **#201** after the #202 re-scope ruling.
7. **#72** (D12 matrix) LAST among code-facing tickets: it touches the pipeline config and
   benefits from every pin landing first (the matrix then runs the FULL green suite on D12).
   The #277/#278 probes run when their M8/M9 consumers need them (not on the critical path).

**Ruling discipline inherited:** board queries milestone-scoped (M7 filter) and batched;
one pull per work phase; every red ships with per-leg discrimination; declared keys name
their consuming leg or stay undeclared; docs are the spec source; NO code forward from v3
(verification reads of `flysystem-3.0-ref` only, as the BC sweep used it 2026-09-12).

## 4. Test plan summary (M7's proving legs)

- **Section-A:** one pin per dispositioned drupal.org issue — pinned at the seam where the
  defect lived (wrapper, factory, URL generation, stat layer); every pin names its issue and
  the 4.0-must-not line.
- **Connection/status contract (#27):** the button's HTTP shape, the entity fields written
  (status/message), watchdog severity, and the requirements-entry shape — under a working and
  a failing scheme; CI runs it against the emulator network paths, never real endpoints.
- **stat_cache_ttl:** schema entry + Admin-UI write + the cache-respect leg (M5's stat-cache
  + invalidation pins get a TTL consumer noted where it lands).
- **private-download boundary:** adapter failure during serving → 404 to the caller, never
  a 500 (exception strategy seams, architecture.md §7).
- **D12 matrix:** CI gains the `phpunit (next major)` job: core ^12 + PHP 8.5; the pipeline
  runs BOTH PHP majors; `composer.json` opts in per `drupal-ci.yml` conventions (the
  compatibility skill's accept/reject matrix applies to any Upgrade-Status finding).
- Every slice: red → green → review; `#[RunTestsInSeparateProcesses]` on Kernel/Functional,
  never Unit; canonical QA configs (phpcs/phpstan/phpunit) per rule 8; per-class and per-leg
  unique service paths (Floci + SFTP service sharing, M5 §3 binding since the 2026-09-10
  stale-object false-green).

## 5. Milestone exit criterion

1. Every Section-A/B disposition in `drupal-issue-queue.md` carries its pin or not-applicable
   rationale with evidence.
2. The connection test has a production caller and writes its entity fields (the M3 MEDIUM
   finding closed with a red-first pair).
3. The D12 matrix runs green in the pipeline on BOTH majors (core ^11.4 || ^12).
4. Every milestone-12 ticket closes with review; the milestone integration pass (per pair-set,
   same rule as M4/M5/M6) lists every config key and seam touching more than one pair WITH a
   combination leg named — the pass may return zero entries or close them before closure.
5. No suite grows an unearned leg (the runtime budget rule) and the pipeline stays green at
   the exit checkpoint. M7 is Done when milestone 12's issues read 0 open on the board with
   review; then it is never revisited.

## 6. Standing constraints (inherited, binding)

Everything in `plan-m6.md` §3 carries: `declare(strict_types=1)`; full type hints; constructor
DI; cache metadata on render arrays; English strings in `$this->t()`; `FileExists` enum;
`#[RunTestsInSeparateProcesses]` on Kernel/Functional classes; PHPStan level 8 via the
canonical relative-path + fresh-cache discipline; phpcs per the canonical config; canonical
phpunit scoping (changed files + affected suites); QA-law evidence pasted, never asserted;
explicit test methods (no data providers); ONE ticket delivered at a time; efficient tracker
queries (milestone-scoped, batched, no full-board pulls); TDD reds-first with per-leg
discrimination; pins disclosed; the user's review gate per pair, no auto-advance; milestone
integration pass before close; the planning-doc doctrine — the planning folder is the
sole spec source (v3-ref reads are verification only).
