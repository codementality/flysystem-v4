# M3 — Adapter Hardening & Integrations: Implementation Contract

Scope: the M3 GitHub issues in the "M3 Adapter hardening" milestone. Source of truth:
`planning/architecture.md` (§4–§7), `planning/testing.md` (§2, §5, §8), `planning/config-and-upgrade.md`
(§3), `planning/adapter-submodules.md` (the Core-two + optional-submodule carve-out), and
`planning/feature-evaluation-log.md`. Milestone exit criterion (`testing.md` §8): **GD and ImageMagick
staging work with a remote scheme; Floci integration tests pass for visibility/ACL/URLs in the
submodules.** This document is the living execution contract for M3 and is kept current for the
independent project review.

**Document status (2026-08-31):** live contract — drafted at M2 completion, ahead of M3 execution.

---

## 1. M3 goal and boundary

M3 hardens the adapter surface and integrations. The Core module ships **one** adapter driver
(`local` — the adapter that ships with League\Flysystem by default); the three SDK adapters (`aws_s3`,
`s3`, `sftp`) are optional submodules (M4–M6, per `adapter-submodules.md` §1), and `in_memory` is a
dev-only test fixture (`league/flysystem-memory` lives in `require-dev`), not a Core-shipped driver.
M3's scope is the driver-agnostic hardening plus the one Core driver and the integrations that depend
on it.

**In M3:** Core adapter driver `local` (#78), Core visibility strategy (#17 — scheme-
derived visibility + `directory_visibility` private), read-only enforcement (#18 — existing `writable`
flag), mime-on-write (#19 — Core passes Drupal's guessed mime), GD staging (#20), ImageMagick staging
(#21), image-style routes (#22), checksum API (#23 — streaming MD5), AJAX driver-swap on the add form
(#76), plugin-derived secret validation (#100), the M2 @todo-triage wrapper gaps (#119 directory
listing, #120 `stream_truncate`), and the functional replacement tests (#108/#109/#110).

**Not in M3 (submodule/M-later scope):** S3 `use_acl` + subclassed adapters, S3 stored-Content-Type
test, S3 ETag checksum test, Floci ACL-disabled scenario (#84 — folded into the S3 submodules per
`adapter-submodules.md` §5.1), the submodules themselves (M4–M6), Floci CI spike (#71, M7), migration
(M8), release (M9).

---

## 2. Execution status (2026-08-31)

All M3 tickets are **Backlog / Ready** on the board; nothing has been started. The M3 gate is **#78
(Core adapter drivers)** — most M3 slices chain behind it.

### 2.1 Done

*(none — M3 not yet started.)*

### 2.2 In flight

*(none.)*

### 2.3 Open, not started

| Feature | T# (red) | Blocked by | Notes |
|---|---|---|---|
| #78 Core adapter driver (`local`) | #89 T78 | T78 | The M3 gate. New `local` driver in Core `src/`; Core schema fragment + config form. (`in_memory` stays a dev-only test fixture.) |
| #17 Visibility (Core) | #54 T17 | #78 | Scheme-derived visibility + `directory_visibility` private; S3 `use_acl` portion → submodules |
| #18 Read-only enforcement | #55 T18 | — | Uses the existing `writable` flag (ReadOnlyFilesystemAdapter wrapper) — **startable before #78** |
| #19 Mime-on-write | #56 T19 | #78 | Core passes Drupal's guessed mime as adapter write config |
| #20 GD staging | #57 T20 | #78 | Staging through `temporary://` + wrapper move for a remote scheme |
| #21 ImageMagick staging | #58 T21 | #78 | realpath FALSE probe → stage to `temporary://`, shell out, move back |
| #22 Image-style routes | #59 T22 | — | No double-slash, normalizer, derivative scheme — **startable before #78** |
| #23 Checksum API | #60 T23 | — | Per-scheme streaming MD5 in Core — **startable before #78** |
| #76 AJAX driver-swap | #91 T76 | #78 | Driver config sub-form swap on the add form (observable via the two Core drivers) |
| #100 Plugin-derived secret validation | #101 | T# | Delete `SECRET_XOR_PAIRS`; derive XOR pairs from driver `getConfigKeys()` `secret` markers |
| #119 Directory listing (dir_*) | — | — | M2 @todo-triage (dir_opendir/readdir/rewinddir/closedir over listContents) |
| #120 stream_truncate | — | — | M2 @todo-triage (resize the buffered write stream, mark dirty for flush) |
| #108 private:// replacement | — | #78, #81✓ | Functional test over the `local` driver (same-directory replacement) |
| #109 public:// replacement | — | #78, #10✓ | Functional test over the `local` driver |
| #110 assets:// replacement | — | #78, #15✓, #10✓ | Functional test over the `local` driver (#3611227 guard) |

---

## 3. Dependency graph (M3-relevant)

Edges verified 2026-08-31 via GraphQL `blockedBy`:

- **#78** `blocked_by` #89 (T78, its own red-test ticket) + closed M1/M2 — the M3 gate.
- **#17/#19/#20/#21** `blocked_by` #78 (+ their T#s) — wait for #78's green.
- **#18/#22/#23** `blocked_by` only their T#s + closed M1/M2 — **startable before #78**.
- **#76** `blocked_by` #78 + #91 (T76).
- **#100** `blocked_by` #101 (its T#).
- **#119/#120** — no open blockers (M2 done).
- **#108/#109/#110** `blocked_by` #78 (+ #81/#15/#10 closed).
- **#84** re-scoped: folded into the S3 submodules (M4–M6), not Core M3 work.

The two-ticket dance per `docs/agents/board.md`: each feature starts once its T# is red
("Tests complete, failing" satisfies the blocking edge for starting); both move to Done together
when the tests turn green and are approved.

**CORRECTED 2026-08-31 (user directive — NON-NEGOTIABLE): there is NO "coverage-only" exception.**
TDD applies to EVERY feature ticket: a T# red-test ticket is authored first, reviewed by the user,
then the implementation makes it green. #108, #119 and #120 must each get a T# ticket retroactively —
the earlier text that said "coverage-only tickets like #119/#120/#108–#110 go straight to Done when
green" was WRONG and is revoked. A green T# at authoring time is still authored (as a regression pin)
and gated through the T# review; it never bypasses the gate.

---

## 4. Vertical slices (TDD — red test first, then minimal green)

Per `testing.md` §2 (vertical slices, one seam at a time). The seam is the boundary named in
`testing.md` §2; the red test is authored first; only enough code to pass is written.

### Slice 1 — #78 Core adapter driver (`local`) — **THE M3 GATE**
New `local` driver in Core `src/Plugin/Flysystem/Adapter/` (`league/flysystem-local`, TYPE_LOCAL,
`root` config key required, supportsVisibility TRUE), Core schema fragment
(`flysystem.adapter_config.local`), config form. The `in_memory` driver stays a dev-only test fixture
in `flysystem_inmemory_test` (`league/flysystem-memory`, in `require-dev`); it is NOT moved into Core.
Red: #89 (T78). Most of M3 chains behind this slice.

### Slice 2 — #17 Visibility (Core)
Scheme-derived visibility (`public://`-type → Visibility::PUBLIC, private → PRIVATE) passed as write
config; `directory_visibility` forced private. S3 `use_acl`/subclassed-adapter portion → submodules.
Red: #54. Blocked by #78.

### Slice 3 — #18 Read-only enforcement
The existing `writable` flag drives it: FALSE wraps the built adapter in ReadOnlyFilesystemAdapter
before `new Filesystem()` (already verified in `FilesystemFactory::buildAdapter()`); write-mode
`stream_open` rejected, `unlink` → TRUE. Red: #55. Startable before #78.

### Slice 4 — #19 Mime-on-write
Write path passes Drupal's guessed `filemime` as adapter write config so stored Content-Type matches.
Red: #56. Blocked by #78.

### Slice 5 — #20 GD staging
`GDToolkit::save` with a remote scheme: stage through `temporary://`, `file_system->move()` to the
destination. Red: #57. Blocked by #78.

### Slice 6 — #21 ImageMagick staging
Probe `realpath` (FALSE for remote) → stage to `temporary://`, shell out to `magick`, `move()` back
through the wrapper. Red: #58. Blocked by #78.

### Slice 7 — #22 Image-style routes
No double-slash, URL normalizer, derivative scheme routing for remote schemes. Red: #59. Startable
before #78.

### Slice 8 — #23 Checksum API
Per-scheme integrity API with streaming MD5 in Core; S3 ETag verification → submodules. Red: #60.
Startable before #78.

### Slice 9 — #76 AJAX driver-swap on the add form
Driver config sub-form swaps via AJAX when the driver select changes (observable through the two Core
drivers). Red: #91. Blocked by #78.

### Slice 10 — #100 Plugin-derived secret validation
Delete `SECRET_XOR_PAIRS`; `FlysystemFilesystem::validate()` derives the XOR pairs from the selected
driver's `getConfigKeys()` `secret` markers (a driver with none yields no pairs). Red: #101.

### Slice 11 — #119 Directory listing
`dir_opendir`/`dir_readdir`/`dir_rewinddir`/`dir_closedir` over the adapter's `listContents()`
(path-prefixed); `\\.`/`..` handling; never throws (§5). From the M2 @todo triage.

### Slice 12 — #120 stream_truncate
Resize the buffered write stream (php://temp) to `$new_size`, mark dirty so `stream_flush()` uploads
the truncated content (single PUT, §4.4). From the M2 @todo triage.

### Slice 13 — #108/#109/#110 Functional replacement tests
BrowserTestBase tests proving a flysystem scheme over the `local` driver (rooted at the SAME
directory) transparently replaces core `private://` / `public://` / `assets://`: same files accessible
without migration, URLs unchanged, new uploads work, fallback on removal. #110 is the #3611227
regression guard. Blocked by #78.

**Slice order note:** the board's `blocked_by` edges, not this list, are authoritative for
sequencing. This list documents *why* each slice is where it is.

---

## 5. Constraints

- `declare(strict_types=1)` everywhere; full type hints; constructor DI in service classes (the
  wrapper itself stays container-independent per `architecture.md` §3.1).
- Cache metadata on all render arrays; English user-facing strings in `$this->t()`.
- No debug code. PHPStan level 8 clean for new code; PHPCS Drupal standard clean (canonical
  `.ddev/commands/web/phpcs.xml.dist`).
- Never use APIs flagged for removal in 11.4+; `FileExists` enum everywhere (no ints).
- **No code forward from v3** (`plan-m1.md` §1a binding for M3 as well); planning docs are the sole
  spec source.
- **No driver knowledge in Core beyond the two shipped drivers** (`adapter-submodules.md` §2.1): the
  S3/SFTP specifics live in the submodules (M4–M6), not here.
- Do NOT implement submodule scope in M3 (S3 `use_acl`, S3 mime/ETag tests, Floci ACL-disabled #84).

---

## 6. Test plan summary

- Kernel tests against the `in_memory` fixture for contract slices; the `local` driver (#78) adds a
  real-disk leg where LOCAL-type behavior matters (realpath, tempnam, directory ops).
- Functional tests for the replacement scenarios (#108/#109/#110) and the admin form (#76).
- Every slice: red → green → (review); no refactoring inside the loop.
- `#[RunTestsInSeparateProcesses]` on Kernel/Functional classes; never on Unit.
- No test asserts implementation details — behavior through seams only.
- S3-specific assertions (ACL, Content-Type, ETag) are submodule scope (M4–M6).

---

## 7. Verification commands (canonical `.ddev/commands/web/*`)

```bash
ssh web .ddev/commands/web/phpunit
ssh web .ddev/commands/web/phpstan
ssh web .ddev/commands/web/phpcs
# Coverage (on demand, host): ddev test-coverage — requires Xdebug; report at codecov/
```

Note: `floci-check` is submodule-testing-only (Core knows nothing of Floci — decision 2026-08-30);
its local FAIL does not gate Core M3. `phpunit-ostests` (MinIO) is likewise object-store scope.

---

## 8. Milestone exit criterion (rechecked)

`testing.md` §8 M3: **GD and ImageMagick staging work with a remote scheme; Floci integration tests
pass for visibility/ACL/URLs in the submodules.** M3 Core is Done when all M3 milestone tickets are
closed on the board with review (#78/#89, #17/#54, #18/#55, #19/#56, #20/#57, #21/#58, #22/#59,
#23/#60, #76/#91, #100/#101, #119, #120, #108/#109/#110); the submodule Floci leg of the exit
criterion lands with M4–M6. Per the milestone-immutability rule (user, 2026-08-30): once M3 is
complete (all tickets worked, approved, Done), it is never revisited or changed.