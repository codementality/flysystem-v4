# M2 — The Contract-Faithful Wrapper: Implementation Contract

Scope: the M2 GitHub issues in the "M2 Contract wrapper" milestone (milestone #10). Source of truth:
`planning/architecture.md` (§4–§7), `planning/testing.md` (§2, §5, §8), `planning/config-and-upgrade.md`
(§3). Milestone exit criterion (`testing.md` §8): **the pain-map contract tests pass against the
in-memory fixture** — i.e. every behavioral contract in `architecture.md` §4–§7 encoded as a passing
kernel test. This document is the living execution contract for M2 and is kept current for the
independent project review.

**Document status (2026-08-30):** live contract — updated as M2 executes.

---

## 1. M2 goal and boundary

M2 hardens the `FlysystemStreamWrapper` skeleton (shipped in M1, #79) from a thin stub into the
**contract-faithful wrapper** — the center of gravity of the design. Every method PHP can call on a
stream is a tested contract. M2's scope is the *driver-agnostic wrapper layer*; the concrete
adapters are M3/submodule scope (see `adapter-submodules.md`).

**In M2:** stat layer (`url_stat`), `realpath()` FALSE, `getType()`, URL policy, single-PUT write
path + stat-cache invalidation, seekable read path, `stream_stat()`/`fstat`, persistent stat cache,
`temporary://` stays local, local-path contract (`getDirectoryPath`, `tempnam`,
`deleteRecursive`), exception strategy, full-scheme in-memory test path, the decorated `file_system`
service, and the private file-download route.

**Not in M2:** visibility/`use_acl` (M3 + S3 submodules), read-only enforcement (M3), mime-on-write
(M3), GD/ImageMagick staging (M3), image-style routes (M3), checksum API (M3), Floci integration
(M7), migration (M8), release (M9). The adapter carve-out (`adapter-submodules.md`) moved the
S3/SFTP adapters to submodules (M4–M6) and kept the Core driver set at `in_memory` + `local`.

---

## 2. Execution status (2026-08-30)

### 2.1 Completed and closed (green, reviewed, on board Done)

| Ticket | Contract |
|---|---|
| #8 / T8 (#45) | Stat layer (`url_stat`) — fabricated consistent stats, private other-read bit, never calls `visibility()`, `realpath()` FALSE |
| #9 / T9 (#46) | `getType()` — per-scheme, adapter-driven LOCAL/REMOTE classification |
| #10 / T10 (#47) | URL policy (`getExternalUrl`) — `public_url_base`, presigned, encoding, no double-slash |
| #11 / T11 (#48) | Write path — single PUT on flush, native same-adapter move, stat-cache invalidation |
| #12 / T12 (#49) | Read path — seekable semantics, `stream_cast` consistency, buffered remote reads |

### 2.2 In flight (not yet approved)

| Ticket | Status | Notes |
|---|---|---|
| #98 / T12a# | **Tests complete, failing** | Red phase for `stream_stat()`/`fstat` — 5 tests, all red, approved by user 2026-08-30. |
| #99 | **In progress** | Green phase: `stream_stat()` implemented (buffer-aware fabricated stat consistent with `url_stat` §4.1). **Code is UNCOMMITTED in the workspace; NOT accepted by the user yet.** QA (canonical `.ddev/commands/web/*`): phpunit OK (90 tests), phpcs 0, phpstan OK. `floci-check` FAIL — but Floci is submodule-testing-only (Core knows nothing of it, decision 2026-08-30), so it does not gate Core work. |

### 2.3 Open, not started

| Feature | T# (red) | Board | Notes |
|---|---|---|---|
| #13 Persistent stat cache | #50 T13 | Backlog / Ready | T13 unblocked (0 open blockers) |
| #14 `temporary://` stays local | #51 T14 | Backlog / Ready | T14 unblocked |
| #15 Local-path contract | #52 T15 | Backlog / Ready | T15 unblocked |
| #16 Exception strategy | #53 T16 | Backlog / Ready | T16 unblocked |
| #73 Full-scheme in-memory test path | #90 T73 | Backlog / Ready | T73 unblocked |
| #80 Decorated `file_system` service | #86 T80 | Backlog / Ready | T80 unblocked |
| #81 Private file-download route | #87 T81 | Backlog / Ready | T81 unblocked |

---

## 3. Dependency graph (M2-relevant)

Edges verified 2026-08-30 via `issue_dependencies_summary`:

- **#13/#14/#73** `blocked_by` closed M1 foundation (#1/#2/#37 + fixture/entity) — startable now.
- **#15/#16** `blocked_by` #80 (decorated `file_system`) + closed M1 — must wait for #80's green.
- **#80** `blocked_by` closed M1 only — startable now.
- **#81** `blocked_by` #10 (URL policy, closed) + closed M1 — startable now.
- **#98 → #99** (red → green chain, both M2). #99 `blocked_by` #98.
- **#86/#87/#90** (T#s) unblocked (0 open blockers) → Ready.

The two-ticket dance per `docs/agents/board.md`: each feature starts once its T# is red
("Tests complete, failing" satisfies the blocking edge for starting); both move to Done together
when the tests turn green and are approved.

---

## 4. Vertical slices (TDD — red test first, then minimal green)

Per `testing.md` §2 (vertical slices, one seam at a time). The seam is the boundary named in
`testing.md` §2; the red test is authored first; only enough code to pass is written.

### Slice 1 — #8 Stat layer (`url_stat`) — **DONE**
Seam 1 (stream wrapper). Fabricated stats, `realpath()` FALSE, private other-read bit, no
`visibility()` round trip. Verified green, approved, closed.

### Slice 2 — #9 `getType()` — **DONE**
Per-scheme LOCAL/REMOTE from the adapter. GD staging decision depends on it. Closed.

### Slice 3 — #10 URL policy — **DONE**
`public_url_base`, explicit presigned, loud error when neither, per-segment encoding, no
double-slash, prefix inclusion, private route. Closed.

### Slice 4 — #11 Write path — **DONE**
Single PUT on `stream_flush` (never per-`fwrite`); native same-adapter move; stat-cache
invalidation on every mutation. Closed.

### Slice 5 — #12 Read path — **DONE**
Seekable buffered reads (§4.5), `stream_cast` consistency, honest eof/tell. Closed.

### Slice 6 — #98/#99 `stream_stat()`/`fstat` — **IN FLIGHT**
Handle-based stat (the `fstat()` counterpart of `url_stat`). Red tests in
`tests/src/Kernel/StreamStatTest.php` (5 tests, approved). Green implemented but **uncommitted /
unapproved**. This slice closes the gap identified on #12 (no test pinned `stream_stat`).

### Slice 7 — #13 Persistent stat cache
Seam 5. Cache bin + TTL + explicit invalidation (mutations clear PHP stat cache + module entries).
Architecture: `architecture.md` §4.6; TTL/`bin` decision recorded in `feature-evaluation-log.md`
Item 2. Red: #50. Startable.

### Slice 8 — #14 `temporary://` stays local
Seam 1. `temporary://` never remaps to a remote adapter; aligned with core
`FileSystem.php:647` / `PhpStorageFactory.php:49`. Red: #51. Startable.

### Slice 9 — #80 Decorated `file_system` service — **gate for #15/#16**
Seam 3. Decorates `file_system` (`FileSystemInterface`): `copy`/`move`/`saveData`/`delete`/
`getDestinationFilename`; flysystem→Drupal `FileException` mapping; `deleteRecursive` correctness
(core #3559132 fix). Red: #86. Startable.

### Slice 10 — #15 Local-path contract
Seam 3. `getDirectoryPath`, `tempnam`, `deleteRecursive` for remote schemes, routed around core's
local-only assumptions (#3600726, #3611227, #3540678). Red: #52. Blocked by #80.

### Slice 11 — #16 Exception strategy
Seam 3 + `architecture.md` §5 (three boundaries: wrapper never throws; decorated `file_system`
translates to the 8 core `FileException` subclasses with `$previous`; CLI/admin one clean line).
Red: #53. Blocked by #80.

### Slice 12 — #81 Private file-download route
Seam 4. Streaming route + controller (Range/206, correct headers, cache metadata),
`hook_file_download` access checks (#3618271). Red: #87. Startable.

### Slice 13 — #73 Full-scheme in-memory test path
Seam 1+2. A configured scheme backed by the `in_memory` adapter through the `FilesystemFactory`
(settings.php + config entity), exercised via the wrapper. Red: #90. Startable.

**Slice order note:** the board's `blocked_by` edges, not this list, are authoritative for
sequencing (`docs/agents/board.md`). This list documents *why* each slice is where it is.

---

## 5. Constraints

- `declare(strict_types=1)` everywhere; full type hints; constructor DI in service classes (the
  wrapper itself stays container-independent per `architecture.md` §3.1 — static bootstrap, the
  #3616485 fix).
- Cache metadata on all render arrays; English user-facing strings in `$this->t()`.
- No debug code. PHPStan level 8 clean for new code; PHPCS Drupal standard clean (canonical
  `.ddev/commands/web/phpcs.xml.dist`).
- Never use APIs flagged for removal in 11.4+; `FileExists` enum everywhere (no ints).
- **No code forward from v3** (`plan-m1.md` §1a is binding for M2 as well).
- Do NOT implement M3 contracts in M2 (visibility/use_acl, read-only, mime, checksum, GD/ImageMagick).

---

## 6. Test plan summary

- Kernel tests against the `in_memory` fixture (REMOTE-type; contract layer, no network).
- S3-specific assertions (ACL, Content-Type, ETag) are **submodule** scope — M4–M6.
- Every slice: red → green → (review); no refactoring inside the loop.
- `#[RunTestsInSeparateProcesses]` on Kernel/Functional classes; never on Unit.
- No test asserts implementation details — behavior through seams only.

---

## 7. Verification commands (canonical `.ddev/commands/web/*`)

```bash
# phpunit — Drupal core's phpunit.xml.dist (Form CORE), inline env vars; the canonical wrapper:
ssh web .ddev/commands/web/phpunit
# phpstan — module config in .ddev/commands/web
ssh web .ddev/commands/web/phpstan
# phpcs / phpcsfix — GitLab-pipeline-equivalent config in .ddev/commands/web
ssh web .ddev/commands/web/phpcs
ssh web .ddev/commands/web/phpcsfix
```

Note: `floci-check` is submodule-testing-only (Core knows nothing of Floci — decision 2026-08-30);
its current local FAIL does not gate M2. `phpunit-ostests` (MinIO) is likewise object-store scope.

---

## 8. Milestone exit criterion (rechecked)

`testing.md` §8 M2: **the pain-map contract tests pass against the in-memory fixture.** M2 is Done
when all of the following are closed on the board with review: #13, #14, #15, #16, #73, #80, #81,
#98, #99 (and their T#s). Per the milestone-immutability rule (user, 2026-08-30): once M2 is
complete (all tickets worked, approved, Done), it is never revisited or changed.