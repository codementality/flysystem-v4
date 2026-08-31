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

## 2. Execution status (2026-08-31 — M2 work complete; awaiting independent review)

### 2.1 Completed and closed (green, reviewed, on board Done)

| Ticket | Contract |
|---|---|
| #8 / T8 (#45) | Stat layer (`url_stat`) — fabricated consistent stats, private other-read bit, never calls `visibility()`, `realpath()` FALSE |
| #9 / T9 (#46) | `getType()` — per-scheme, adapter-driven LOCAL/REMOTE classification |
| #10 / T10 (#47) | URL policy (`getExternalUrl`) — `public_url_base`, presigned, encoding, no double-slash |
| #11 / T11 (#48) | Write path — single PUT on flush, native same-adapter move, stat-cache invalidation |
| #12 / T12 (#49) | Read path — seekable semantics, `stream_cast` consistency, buffered remote reads |
| #13 / T13 (#50) | Persistent stat cache — cache bin + TTL + explicit invalidation (mutations clear PHP stat cache + module entries) |
| #98 / T12a# | `stream_stat()`/`fstat` — buffer-aware fabricated stat consistent with `url_stat` §4.1 |
| #80 / T80 (#86) | Decorated `file_system` service — operator-direct `saveData`/`copy`/`move`/`delete`/`deleteRecursive`, boundary-2 exception mapping, `#3559132` fix |
| #14 / T14 (#51) | `temporary://` stays local — reserved-scheme exclusion in `FilesystemFactory` |
| #15 / T15 (#52) | Local-path contract — wrapper `getDirectoryPath()` (FALSE for remote), `dirname()` string, decorated `file_system->tempnam()` routes remote to `temporary://` |
| #16 / T16 (#53) | Exception strategy — wrapper `reportFailure()` (watchdog operation/location/reason + `trigger_error()`, never throws); mount failures → `InvalidStreamWrapperException` |
| #73 / T73 (#90) | Full-scheme in-memory test path — native `scheme://` ops through the registered wrapper (settings.php + config entity + precedence); **no additional work** — delivered by earlier slices (#3/#5/#6/#7/#74/#79/#11/#12/#8); tests added as green coverage (board.md step 5) |
| #81 / T81 (#87) | Private file-download route — `FlysystemRouteSubscriber` swaps the `system.files` controller; `PrivateDownloadController` probes private flysystem schemes, streams from the adapter (Range/206, `hook_file_download`), delegates to core `private://`. No URL change |
| #111 | Unit tests — `AdapterDefinition` value object (`tests/src/Unit/Flysystem/`) incl. `getVisibility()` derivation |
| #112 | Unit tests — `FlysystemFilesystemConstraintViolationList` (`hasField()` property-path matching) |
| #113 | Unit tests — `FlysystemAdapter` plugin attribute |
| #115 | PrivateDownloadRouteTest — core `private://` delegation regression guard |
| #116 | PrivateDownloadRouteTest — `hook_file_download` deny → 403 |
| #117 | PrivateDownloadRouteTest — missing object → 404 |
| #118 | PrivateDownloadRouteTest — public scheme excluded from the private route |

### 2.2 In flight

| Ticket | Status | Notes |
|---|---|---|
| *(none)* | — | All M2 tickets are approved and on the board Done (green phases #8–#16/#80/#81, unit tests #111–#113, follow-ups #115–#118). M2 exit criterion met (all §8 tickets Done). **M2 not yet FINALIZED:** awaiting the user's final review + an independent project & code review (user, 2026-08-31); resulting tickets filed to Backlog before M2 is called complete. Coverage tooling (#114, M0) and the @todo triage (#119/#120, M3) are also done/flagged. |

### 2.3 Open

*(none — all M2 tickets Done; the @todo triage surfaced #119/#120, now M3/Backlog.)*

---

## 3. Dependency graph (M2-relevant)

All M2 dependencies are resolved: every M2 ticket (#8–#16, #73, #80, #81, #98/#99, and the T#s
#45–#53/#86/#87/#90) is closed and in the board's Done column, matching §2.1. The two-ticket dance
per `docs/agents/board.md` held throughout — a strict T# red → feature green alternation. Per the
milestone-immutability rule (user, 2026-08-30), M2 tickets stay closed; the independent review's
boundary defects were filed as new M3 tickets (#130–#138).

---

## 4. Vertical slices (TDD — red test first, then minimal green)

Per `testing.md` §2 (vertical slices, one seam at a time). The seam is the boundary named in
`testing.md` §2; the red test is authored first; only enough code to pass is written.

> **Historical (2026-08-31):** all slices are complete and closed. §4 is kept for the record; the
> board's `blocked_by` edges are authoritative for current sequencing.

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

### Slice 6 — #98/#99 `stream_stat()`/`fstat` — **DONE**
Handle-based stat (the `fstat()` counterpart of `url_stat`). Red tests in
`tests/src/Kernel/StreamStatTest.php` (5 tests, approved). Green implemented and closed. This slice
closed the gap identified on #12 (no test pinned `stream_stat`).

### Slice 7 — #13 Persistent stat cache — **DONE**
Seam 5. Cache bin + TTL + explicit invalidation (mutations clear PHP stat cache + module entries).
Architecture: `architecture.md` §4.6; TTL/`bin` decision recorded in `feature-evaluation-log.md`
Item 2. Red: #50. Closed.

### Slice 8 — #14 `temporary://` stays local — **DONE**
Seam 1. `temporary://` never remaps to a remote adapter; aligned with core
`FileSystem.php:647` / `PhpStorageFactory.php:49`. Red: #51. Green: reserved-scheme exclusion in
`FilesystemFactory`. Closed.

### Slice 9 — #80 Decorated `file_system` service — **DONE**
Seam 3. Decorates `file_system` (`FileSystemInterface`): `copy`/`move`/`saveData`/`delete`/
`getDestinationFilename`; flysystem→Drupal `FileException` mapping; `deleteRecursive` correctness
(core #3559132 fix). Red: #86. Green committed; #15/#16 shipped after approval. Closed.

### Slice 10 — #15 Local-path contract — **DONE**
Seam 3. `getDirectoryPath`, `tempnam`, `deleteRecursive` for remote schemes, routed around core's
local-only assumptions (#3600726, #3611227, #3540678). Red: #52. Green: wrapper `getDirectoryPath()`
(FALSE for remote), `dirname()` string, decorated `file_system->tempnam()` routes remote to
`temporary://`. Closed. `deleteRecursive` already green via #80's FileSystemSeamTest.

### Slice 11 — #16 Exception strategy — **DONE**
Seam 3 + `architecture.md` §5 (three boundaries: wrapper never throws; decorated `file_system`
translates to the 8 core `FileException` subclasses with `$previous`; CLI/admin one clean line).
Red: #53. Green: wrapper `reportFailure()` (watchdog operation/location/reason +
`trigger_error()`, never throws) in `stream_flush()`'s catch; `operatorForUri()` maps mount
failures to `InvalidStreamWrapperException`. Closed.

### Slice 12 — #81 Private file-download route — **DONE**
Seam 4. Streaming route + controller (Range/206, correct headers, cache metadata),
`hook_file_download` access checks (#3618271). Red: #87. Green: `FlysystemRouteSubscriber` swaps
the `system.files` controller; `PrivateDownloadController` probes private flysystem schemes, streams
from the adapter, delegates to core `private://`. No URL change. Closed. Follow-up test coverage:
#115–#118.

### Slice 13 — #73 Full-scheme in-memory test path — **DONE (no additional work)**
Seam 1+2. A configured scheme backed by the `in_memory` adapter through the `FilesystemFactory`
(settings.php + config entity), exercised via the wrapper. Red: #90. **No green-phase work** — the
full native path was delivered by #3/#5/#6/#7/#74/#79/#11/#12/#8; T73's tests pass green on
arrival (board.md step 5) and add the missing end-to-end native coverage. Closed.

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