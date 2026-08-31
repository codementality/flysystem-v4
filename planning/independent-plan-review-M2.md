# Flysystem v4 — Independent Project & Code Review, Milestone 2

Status: **Review**, 2026-08-31. Scope: the M2 milestone ("M2 Contract wrapper", GitHub milestone #10)
against `planning/plan-m2.md`, `architecture.md` §4–§7, `testing.md` §2/§5/§8, and the committed code
in `web/modules/custom/flysystem` at `45ef610`. Companion to
[independent-plan-review-M1.md](independent-plan-review-M1.md), which this review is modelled on.

Board: [codementality/projects/11](https://github.com/orgs/codementality/projects/11), repo
`codementality/flysystem-v4`.

---

## Executive summary

**The milestone's paper exit criterion is met.** All 33 issues in milestone #10 are closed and in the
board's Done column, matching `plan-m2.md` §2.1 line for line. The suite is green and the gates are
clean:

| Gate | Result |
|---|---|
| `.ddev/commands/web/phpunit` | **142 tests, 453 assertions, 0 failures** (3 Drupal deprecations, 24 PHPUnit deprecations) |
| `.ddev/commands/web/phpstan` | **[OK] No errors** (level 8) |
| `.ddev/commands/web/phpcs` | **clean** |
| Working tree | clean; all M2 work committed |
| Coverage (`codecov/`) | 72.09% lines / 51.91% methods / 43.75% classes |

**The code, however, does not meet the M2 contract.** Six defects were confirmed by execution, three
of them breaking the single most common operation Drupal performs against a file scheme. The pattern
behind all six is the same one M1's review named: *a seam was tested in isolation and never tested at
the boundary it exists to serve.* Every one of these defects sits in a green ticket.

The three findings that matter most:

1. **A managed file upload to any flysystem scheme throws.** `FlysystemFileSystem::copy()/move()`
   take the flysystem branch when *either* end is a flysystem URI, then resolve the operator from
   the **source** only. Core's `FileUploadHandler` (line 203/207) and `FileRepository::copy()/move()`
   (lines 89/127) both call `move()`/`copy()` with a **non-flysystem source** — a raw `/tmp/phpXXXX`
   path or `public://…`. Both paths raise `InvalidStreamWrapperException`. Verified (C1).
2. **`FileExists` is ignored across the whole decorated seam.** `copy()`, `move()` and `saveData()`
   accept `$fileExists` and never read it. `FileExists::Error` — the value core's upload handler
   passes precisely to *prevent* clobbering — silently overwrites the destination and reports
   success. Verified (C2).
3. **The persistent stat cache (#13) is inert.** `StatCache` is a complete, 96%-covered service that
   **nothing calls.** `url_stat()` never reads or writes it; `invalidateStatCache()` still only calls
   `clearstatcache()` and its docblock still reads *"ticket #13 … does not exist yet"*. The ticket's
   own contract — "mutations clear PHP stat cache **+ module entries**" — is unmet, and the caching
   benefit that justified the work is zero. Verified (C4).

On the board side, M1's structural finding **F1 has partially recurred**: 13 open issues sit outside
the transitive closure of #36's blockers, including **#102–#107 — all three adapter submodules** —
even though `adapter-submodules.md:243` states *"#36 | 4.0 release includes the three submodule
packages."* The release can again become startable over an unshipped adapter set (P1).

Nothing here is a reason to reopen M2's tickets — the milestone-immutability rule (user, 2026-08-30)
stands. The findings below are written to be filed as **new Backlog tickets**, which is the
disposition `plan-m2.md` §2.2 anticipates.

---

## A. Deliverables vs. milestone tickets

### A1. Ticket completion — clean

Milestone #10 holds 33 issues, **all closed**, all in Done:

| Group | Issues |
|---|---|
| Feature slices | #8, #9, #10, #11, #12, #13, #14, #15, #16, #73, #80, #81, #99 |
| Red-test pairs (T#) | #45, #46, #47, #48, #49, #50, #51, #52, #53, #86, #87, #90, #98 |
| Unit-test tickets | #111, #112, #113 |
| Follow-up coverage | #115, #116, #117, #118 |

This is an exact match for `plan-m2.md` §2.1. The two-ticket dance held throughout: the git history
shows a strict `T#: Write failing tests` → `M2: <feature>` alternation for every slice (`3a5b198` →
`24d5f0b`, `27b207f` → `c2e5522`, `8a9227f` → `70e36ba`, and so on). No slice merged a green without
a preceding red. That discipline is real and visible, and it is the reason the code that *is* covered
is solid.

Board totals: 120 items — 62 Done, 14 Ready, 44 Backlog. No item is stranded in "Needs triage"
(the M1 C2 finding is closed out).

### A2. Untracked scope leak — read-only enforcement shipped in M2 while its M3 tickets stay open

`plan-m2.md` §1 is explicit: *"**Not in M2:** … read-only enforcement (M3) …"*. §5 repeats it: *"Do
NOT implement M3 contracts in M2."*

It was implemented in M2 anyway:

- `FilesystemFactory::buildAdapter()` wraps non-writable schemes in
  `League\Flysystem\ReadOnly\ReadOnlyFilesystemAdapter` ([FilesystemFactory.php:462-464](../web/modules/custom/flysystem/src/Flysystem/FilesystemFactory.php#L462-L464)).
- `FilesystemFactory::isReadOnly()` exists as a public seam ([:333](../web/modules/custom/flysystem/src/Flysystem/FilesystemFactory.php#L333)).
- The wrapper checks it in `stream_open()`, `mkdir()`, `rmdir()` and `unlink()`.
- [ReadOnlySchemeTest.php](../web/modules/custom/flysystem/tests/src/Kernel/ReadOnlySchemeTest.php) —
  292 lines, six tests — is committed and green.

`git log -S 'ReadOnlyFilesystemAdapter'` places the implementation in **`24d5f0b` ("M2: Write path")**
and the tests in **`3a5b198` ("T11: … write path")** — i.e. inside slice 4, under ticket #11/#48.

Meanwhile **#18 ("M3: Read-only enforcement") is open in Backlog and #55 (T18) is open in Ready.**
#18's own body already concedes the state of play: *"VERIFIED: `FilesystemFactory.php:421-423` + the
form's writable checkbox."*

Two problems follow. First, #55 is a red-test ticket sitting in Ready whose tests already exist and
already pass — the dance cannot be run on it as written. Second, the work escaped the milestone's
review boundary: read-only enforcement was never reviewed *as* #18's deliverable, and #18's remaining
scope (whatever is left of it) is now undefined.

**Fix:** rewrite #18 to name only the residue (the form checkbox surface and any documentation), note
in its body which commit delivered the adapter wrap, and close #55 as satisfied by
`ReadOnlySchemeTest` rather than leaving a red-phase ticket in Ready.

### A3. Deliverables the plan claims but the code does not carry

Three §2.1 rows describe contracts that are not in the shipped code. Each is expanded in section C.

| Ticket | `plan-m2.md` §2.1 claims | Actual |
|---|---|---|
| **#13** | "cache bin + TTL + explicit invalidation (mutations clear PHP stat cache **+ module entries**)" | `StatCache` has **zero production callers**. Mutations clear only PHP's stat cache. (C4) |
| **#80** | "operator-direct `saveData`/`copy`/`move`/`delete`/`deleteRecursive`, boundary-2 exception mapping" | Delivered for **same-scheme flysystem→flysystem only**. Cross-scheme and local→flysystem throw. `$fileExists` unhandled throughout. `getDestinationFilename` — named in seam 3 by `testing.md` §2 and by the test's own docblock — is neither overridden nor tested. (C1, C2, C7) |
| **#81** | "**streams** from the adapter (Range/206, `hook_file_download`)" | Reads the whole object into a PHP string, Range requests included. `hook_file_download` headers are collected and then **discarded**. (C5, C6) |

### A4. Release gating — F1 has partially recurred (P1)

M1's F1 was remediated: #36's blocker closure now spans 91 issues, covering M3, M7 and M8 in full.
Recomputing the closure today, **13 open issues remain outside it**:

```
100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 119, 120
```

Grouped:

| Issues | What they are | Why it matters |
|---|---|---|
| **#102–#107** | The three adapter submodules (M4 `flysystem_aws`, M5 `flysystem_asyncaws`, M6 `flysystem_sftpv3`) and their T# pairs | `adapter-submodules.md:243` states the 4.0 release **includes** the three submodule packages. This is M1's F1 verbatim — the release gate does not hold the production adapters. |
| **#119, #120** | `dir_opendir`/`dir_readdir`/`dir_rewinddir`/`dir_closedir`; `stream_truncate` | These are the stubs M2 deliberately deferred. 4.0 can currently reach its release gate with `opendir()` on a flysystem scheme returning FALSE. |
| **#108–#110** | Functional tests: flysystem `private://` / `public://` / `assets://` replace the core schemes over the local driver | The headline capability of the rewrite, ungated. |
| **#100, #101** | Plugin-derived secret validation (removing the hardcoded `SECRET_XOR_PAIRS`) | A correctness/security cleanup that can ship unaddressed. |

**Fix:** add `blocked_by` edges from #36 to #102, #104, #106, #108, #109, #110, #119, #120 and #100
(their T# pairs come along transitively), then recompute the closure and confirm it is empty. If the
submodules are in fact intended to release on their own cadence, that decision has to be written into
`adapter-submodules.md` §7 — right now the doc says the opposite of what the graph says.

### A5. `plan-m2.md` contradicts itself (document hygiene)

The document is declared a *"living execution contract … kept current for the independent project
review"*, but §4 was not updated when §2 was:

- **§4 Slice 8 (#14)** — "**GREEN COMPLETE, IN REVIEW** … Uncommitted, awaiting review."
- **§4 Slice 9 (#80)** — "**GREEN COMPLETE, IN REVIEW** … Green uncommitted, awaiting user review;
  #15/#16 start once #80 is approved."

Both are listed as closed/Done in §2.1, both are committed (`757e78c`, `70e36ba`), and #15/#16 have
long since shipped. §3 likewise still describes #98→#99 and #86/#87/#90 as pending work. A reader
using §4 as the status view gets a picture two weeks stale.

Also stale: **#35** is titled "**M6**: Adapter-plugin developer README" while assigned to milestone
**M9 Release** — residue from the `adapter-submodules.md` §renumbering (M4/M5/M6 → M7/M8/M9). Same
class of defect as M1's finding B (#25).

---

## B. What M2 got right

Stated deliberately, because it bounds everything in section C.

- **The stat layer (#8/#99) is exactly the contract.** `url_stat()` and `stream_stat()` derive from
  `fileExists`/`directoryExists`/`fileSize`/`lastModified` and **never** call `visibility()` — the
  #3616487 fix. `dev`/`ino` are SHA-256-derived from the URI in both methods with identical
  derivation, so a path-stat and a handle-stat of the same object agree. The other-read bit (`0o004`)
  is preserved for private files (#3618526). This is the load-bearing piece and it is right.
- **`realpath()` returns FALSE and `getDirectoryPath()` returns FALSE**, with `dirname()` always
  returning a string so FALSE can never leak into path building. The honest-answer discipline
  `architecture.md` §4.1/§4.8 demands is held.
- **The single-PUT write path** genuinely buffers to `php://temp` and uploads exactly once at
  `stream_flush()`, idempotently. No per-`fwrite` PUT.
- **`temporary://` exclusion** is enforced at the *factory* — the single owned-scheme resolution
  point — so it protects the wrapper manager, the decorated `file_system` and the admin surface at
  once. That is the right seam for it.
- **`deleteRecursive()`** is a real fix for core #3559132: it walks `listContents($path, TRUE)`
  instead of relying on `dir_opendir()` and `realpath()`. Tested.
- **Type classification** is resolved per-scheme through the manager
  (`resolveOwnedWrapperType()`), not through the wrapper's one static value — the correct
  architecture for a single wrapper class fronting many schemes.
- **PHPStan level 8 and PHPCS clean with zero baseline suppressions**, and the `phpcs:ignore`
  annotations that do exist are confined to PHP's mandated snake_case stream-protocol method names,
  each individually annotated. That is the disciplined use of the escape hatch.

---

## C. Code defects

Severity: **CRITICAL** = breaks a primary user-facing operation; **HIGH** = contract in a green
ticket is unmet, or a security/resource exposure; **MEDIUM** = correctness or robustness gap.

All findings marked *(verified)* were reproduced by executing a throwaway kernel test against the
in-memory fixture; the probe was removed after the run and is not in the tree.

### C1. Cross-scheme `copy()`/`move()` throws — managed file uploads to a flysystem scheme fail (CRITICAL) *(verified)*

[FlysystemFileSystem.php:127-134](../web/modules/custom/flysystem/src/File/FlysystemFileSystem.php#L127-L134)
and [:173-180](../web/modules/custom/flysystem/src/File/FlysystemFileSystem.php#L173-L180):

```php
if (!$this->isFlysystemUri($source) && !$this->isFlysystemUri($destination)) {
  return parent::copy($source, $destination, $fileExists);
}
$filesystem = $this->operatorForUri($source);   // ← source only
$source_target      = $this->targetForUri($source);
$destination_target = $this->targetForUri($destination);
```

The guard says *"if neither end is ours, defer to core"*. The body then assumes **both** ends are
ours, resolving one operator from the source and applying it to the destination target as well.

For a **local source and a flysystem destination** — the overwhelmingly common case — this resolves
an operator for a scheme the factory does not own:

- `move('/tmp/phpAB12', 'schemetest://f.txt')` → `strstr()` finds no `://` → returns FALSE →
  `getFilesystem(FALSE)` → `TypeError` under `strict_types` → caught by `operatorForUri()`'s
  `catch (\Throwable)` → **`InvalidStreamWrapperException: The  stream wrapper could not be mounted.`**
  (note the empty scheme name in the message — the tell).
- `copy('public://src.txt', 'schemetest://c.txt')` →
  **`InvalidStreamWrapperException: The public stream wrapper could not be mounted.`**

Both reproduced against the in-memory fixture.

**Blast radius** — these are the paths, not edge cases:

| Caller | Line | Effect |
|---|---|---|
| `FileUploadHandler::handleFileUpload()` | `web/core/modules/file/src/Upload/FileUploadHandler.php:207` — `$this->fileSystem->move($uploadedFile->getRealPath(), $uri, FileExists::Error)` | **Every managed file upload to a flysystem scheme fails.** Source is a raw local temp path. |
| `FileRepository::copy()` | `FileRepository.php:89` | `file_copy()` from any non-flysystem scheme fails. |
| `FileRepository::move()` | `FileRepository.php:127` | `file_move()` from any non-flysystem scheme fails. Used by Media, Migrate, and every "move to permanent storage" flow. |

Note the interaction with #15: `tempnam()` deliberately routes flysystem schemes to `temporary://`
— which then cannot be moved to its flysystem destination.

**Why the tests missed it:** all six `FileSystemSeamTest` cases use `schemetest://` on *both* ends.
No test crosses the boundary the decorator exists to straddle. The `File/` directory's 52.42% line
coverage is this gap made visible.

**Fix:** resolve source and destination independently. Four combinations, each with its own path:
flysystem→flysystem (native `copy`/`move`), local→flysystem (read the local stream, `writeStream` to
the destination operator), flysystem→local (`readStream`, write locally), local→local (`parent::`).
Then pin all four with tests.

### C2. `FileExists` is ignored — silent overwrite across the whole seam (CRITICAL) *(verified)*

`saveData()`, `copy()` and `move()` all accept `$fileExists` and **never read it**. The parameter is
declared, defaulted to `FileExists::Rename`, and dropped.

Reproduced: `copy('schemetest://dir/b.txt', 'schemetest://dir/a.txt', FileExists::Error)` with
`a.txt` already present **returned `'schemetest://dir/a.txt'` and `a.txt` now contains `b.txt`'s
content**. Core's contract requires `FileExists::Error` to throw `FileExistsException` and touch
nothing.

Each enum value is broken differently:

| Value | Core contract | Actual |
|---|---|---|
| `Error` | throw `FileExistsException`, leave the destination intact | overwrites, returns success |
| `Rename` (the **default**) | pick `file_0.txt`, `file_1.txt`, … | overwrites |
| `Replace` | overwrite | correct, by accident |

`FileExists::Error` is what `FileUploadHandler` passes. `FileExists::Rename` is what every caller
that omits the argument gets. This is **silent data loss on the default path**, and it is
indistinguishable from success to the caller.

This is also where `getDestinationFilename()` belongs — the method `testing.md` §2 names as part of
seam 3, that `FileSystemSeamTest`'s own docblock lists in the contract under test, and that is
neither overridden nor tested. `Rename` cannot be implemented without it.

**Fix:** implement all three enum values in the flysystem branch, backed by an overridden
`getDestinationFilename()` that resolves candidate names through the operator rather than through
`file_exists()`. Add one test per enum value per method.

### C3. Append and update `fopen()` modes truncate the object (CRITICAL) *(verified)*

[FlysystemStreamWrapper.php:818-854](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L818-L854).
`isWriteMode()` classifies `a`, `a+`, `r+`, `c`, `c+`, `w+`, `x+` as write modes. Every one of them
takes the write branch, which opens an **empty** `php://temp` buffer and never seeds it with the
existing object. `stream_flush()` then `writeStream()`s that buffer over the object.

Reproduced: an object containing `'FIRST'`, opened `'a'`, `fwrite('-SECOND')`, `fclose()` →
**the object now contains `'-SECOND'`**. The existing content is gone.

The `+` modes are broken in the other direction too: `r+` and `a+` take the write branch, so
`$readBuffer` is never populated — `stream_read()` returns `''`, `stream_seek()` returns FALSE and
`stream_tell()` returns 0 on a handle the caller believes is readable.

`architecture.md` §4.4/§4.5 do not carve out an exception for these modes, and neither
`WritePathTest` nor `ReadPathTest` opens one.

**Fix (minimum):** seed the write buffer from the existing object for `a`/`a+`/`r+`/`c`/`c+`,
positioning the cursor at the end for append modes and at 0 for update modes; populate `$readBuffer`
(or unify on one buffer) for any mode containing `+`. **Fix (alternative, and defensible):** reject
the modes the design does not intend to support by returning FALSE from `stream_open()` with a
`reportFailure()` — an honest failure beats silent truncation. Either way, pin it with tests.

### C4. The persistent stat cache (#13) has no production callers (HIGH) *(verified)*

`grep -rn 'StatCache' src/` outside the class itself returns exactly one match — the service
definition in `flysystem.services.yml:28`. The complete call graph:

- **`url_stat()` never reads the cache.** Every stat is three live adapter round trips
  (`fileExists`, `fileSize`, `lastModified`) — plus `getDefinition()`, which is itself unmemoized.
- **`url_stat()` never writes the cache.** Verified: after `filesize('schemetest://dir/s.txt')`
  returned 5, `flysystem.stat_cache->get('schemetest://dir/s.txt')` returned **NULL**.
- **No mutation calls `StatCache::invalidate()`.** `invalidateStatCache()`
  ([:311-313](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L311-L313))
  is still the M1 body — `clearstatcache()` and nothing else — and its docblock still says, verbatim:

  > *"The module's PERSISTENT stat-cache invalidation (object + parent prefixes, a cache bin with
  > TTL) is **ticket #13 and does not exist yet**; this is the observable stretch of the contract,
  > and the persistent-cache hook is added there."*

  That comment is accurate about the code and three commits out of date about the ticket.

`WritePathTest`'s docblock at line 272 states the intent plainly: *"…invalidate the module's
persistent stat-cache entries (object + parent prefixes) and call `clearstatcache()` … those tests
become the regression guard for the invalidation."* That regression guard was never added when #13
landed; the tests exercise `StatCache` directly through the container and never through a stat.

Consequences: the cross-request read savings that justified the bin (`architecture.md` §4.6) are
**zero**; every `file_exists()`/`filesize()` on a remote scheme still pays full adapter latency; the
TTL, the settings.php override and the prefix-walking `invalidate()` are all dead code; and the
moment the cache *is* wired in, it will serve stale stats unless invalidation lands with it.

Secondary, and worth fixing in the same pass: **`stream_flush()` does not call
`invalidateStatCache()`** while `mkdir()`, `rmdir()`, `unlink()` and `rename()` all do. Writes are
the one mutation that skips it. (PHP does not appear to cache URL-wrapper stats aggressively enough
for this to be observable today — a write-then-`filesize()` reported the fresh size in testing — but
it is an inconsistency that becomes a live staleness bug the instant the persistent cache is wired.)

**Fix:** read-through in `url_stat()`, write-through on a miss, `StatCache::invalidate()` in
`invalidateStatCache()`, and an `invalidateStatCache()` call in `stream_flush()` and in every
`FlysystemFileSystem` mutation. Then add the boundary tests: stat → mutate → stat.

### C5. The private download reads the whole object into memory (HIGH)

[PrivateDownloadController.php:157-176](../web/modules/custom/flysystem/src/Controller/PrivateDownloadController.php#L157-L176):

```php
$content = $filesystem->read($target);   // entire object → PHP string
$size = strlen($content);
…
$content = substr($content, $start, $end - $start + 1);   // Range: read all, then slice
…
return new Response($content, $status);
```

`architecture.md` §4.3 specifies *"streams adapter → PHP → browser"*, and
`feature-evaluation-log.md` Item 9 asks to *"harden the private streaming route"*. This is a full
buffered read, and the operator exposes `readStream()` right next to `read()`.

Impact:

- A private 500 MB video exhausts `memory_limit` and 500s. The failure scales with the largest file
  any site stores privately, and it is **unauthenticated-adjacent**: any user permitted to download
  *one* large private file can pin a PHP worker's full memory per request.
- **Range requests defeat their own purpose.** A browser seeking to the end of a 2 GB video sends
  `Range: bytes=2000000000-2000000100` and the controller reads all 2 GB to return 100 bytes. Media
  players issue these constantly.
- The whole object is fetched from the remote store even when the client asked for a slice —
  egress cost proportional to seeks, not to bytes delivered.

Note this route is swapped in **unconditionally** by `FlysystemRouteSubscriber` for every site with
the module enabled, whether or not a flysystem scheme is configured.

**Fix:** `readStream()` + `StreamedResponse`, with the Range offset applied via `fseek()`/bounded
copy on the stream. Where the adapter supports ranged reads natively, push the range down to it.

### C6. `hook_file_download` headers are discarded on the flysystem path (HIGH)

[PrivateDownloadController.php:147-155](../web/modules/custom/flysystem/src/Controller/PrivateDownloadController.php#L147-L155):

```php
$headers = $this->moduleHandlerService->invokeAll('file_download', [$uri]);
foreach ($headers as $result) {
  if ($result === -1) { throw new AccessDeniedHttpException(); }
}
if (count($headers) === 0) { throw new AccessDeniedHttpException(); }
```

`$headers` is used as an access verdict and then thrown away. Core's `FileDownloadController` passes
it into the response: `new BinaryFileResponse($uri, 200, $headers, …)`. The controller's own
`serveCorePrivate()` gets this right for the `private://` delegation path (line 223) — only the
flysystem path drops them.

`file_file_download()` returns exactly the headers that make a private download safe:
`Content-Type` (from the **file entity's** recorded `filemime`), `Content-Length`, and
`Content-Disposition`. Other modules add `X-Content-Type-Options: nosniff` and forced-attachment
dispositions here. All of it is lost.

The controller substitutes `$filesystem->mimeType($target)` — **adapter-side detection**, typically
extension- or content-sniffed. For a user-uploaded `.html`, `.svg` or `.xhtml` file this yields
`text/html` / `image/svg+xml`, served **from the site's own origin** with no `Content-Disposition`
and no `nosniff`. That is a stored-XSS delivery path with access to the session cookie. Core's
private-file pipeline defends against exactly this through the headers being discarded here.

**Fix:** merge `$headers` into the response before returning it, exactly as core does, and let
`hook_file_download`'s `Content-Type` win over the adapter's. Keep the adapter mime type only as a
fallback when no module supplied one. Add a test asserting a hook-supplied `Content-Disposition`
survives to the response.

### C7. Private-scheme resolution: probe cost, first-match-wins, prefix mismatch (MEDIUM)

`download()` ([:106-118](../web/modules/custom/flysystem/src/Controller/PrivateDownloadController.php#L106-L118))
loops every configured scheme, calls `getDefinition()` on each, and calls `fileExists($target)` on
each private one. Three distinct problems, one of which the code already flags with an `@todo`:

1. **Cost.** Every private-file request pays one `getDefinition()` (unmemoized — see C8) plus one
   **live adapter `fileExists()` round trip per private scheme**, in declaration order, before the
   first byte is served. A site with three private S3 schemes pays up to three S3 HEADs per image.
2. **First-match-wins across schemes.** Two private schemes holding the same key means the *first
   declared* one is served, regardless of which one the URL was generated for. `hook_file_download`
   is then invoked with the wrong scheme's URI. The failure is fail-closed today (no module claims
   it → 403) but the resolution is wrong, and where both schemes hold entity-backed files the wrong
   file is served under the other's access decision.
3. **Prefix round-trip mismatch.** `getExternalUrl()` builds the URL key as `prefix + '/' + target`
   ([FlysystemStreamWrapper.php:402](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L402)),
   but `download()` probes `fileExists($target)` with that full key against an operator whose adapter
   **already applies the prefix**. On any prefixed private scheme the lookup is `prefix/prefix/key`
   and returns 404. No test configures a prefixed private scheme, so this is uncovered in both
   directions.

**Fix:** carry the scheme in the URL (the `@todo`'s own first suggestion) or resolve it from
`file_managed`, and separate the *URL key* from the *operator key* so the prefix is applied exactly
once. A prefixed-private-scheme round-trip test — `getExternalUrl()` → request → 200 — pins all
three.

### C8. Every remote scheme is registered `STREAM_IS_URL` — the module is inert when `allow_url_fopen` is off (MEDIUM) *(verified)*

[FlysystemStreamWrapperManager.php:291-296](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapperManager.php#L291-L296)
registers LOCAL schemes with flag 0 and everything else with `STREAM_IS_URL`.

Verified on this stack (PHP 8.4.22) with `allow_url_fopen=0`:

```
urlish   fopen: FAILED - Failed to open stream: no suitable wrapper could be found
localish fopen: ok
```

PHP refuses to open *any* `STREAM_IS_URL` wrapper when `allow_url_fopen` is disabled. Since every
remote flysystem scheme registers with the flag, **the entire module stops functioning** on a host
with that setting — and the error message names no wrapper, so it is close to undiagnosable.

Two mitigating facts and one aggravating one. Core's own `StreamWrapperManager::registerWrapper()`
(`web/core/lib/Drupal/Core/StreamWrapper/StreamWrapperManager.php:183`) does exactly the same thing,
so this is core parity, not a novel choice — but core ships no non-LOCAL wrapper, so core never
exercises it. Against that: **flysystem 3.0 deliberately diverged**, registering *always* without
the flag, with the reason written into the code
(`flysystem-3.0-ref/src/StreamWrapper/FlysystemStreamWrapperManager.php:232-235`). Dropping that
divergence is an undocumented behavioral regression from the version being replaced.

(The specific reason 3.0 gave — underscores in scheme names — no longer applies: PHP 8.4 rejects
underscore schemes with *or* without the flag, and the module's machine-name `replace_pattern`
(`[^a-z0-9-]+`) already forbids them. The `allow_url_fopen` consequence is separate and live.)

**Fix:** at minimum a `hook_requirements()` entry failing installation when `allow_url_fopen` is off
and a remote scheme is configured — #27 ("contract-violation determinations + status checks") is the
natural home. Better: record an explicit decision in `feature-evaluation-log.md` on whether to
follow 3.0 and register without the flag, and what is lost if you do.

### C9. `getExternalUrl()` throws, violating §5 boundary 1 (MEDIUM)

[FlysystemStreamWrapper.php:416-421](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L416-L421)
raises `\InvalidArgumentException` when a public scheme has neither `public_url_base` nor
`presigned_expiry`.

`architecture.md` §5 boundary 1 and `plan-m2.md` §4 slice 11 both state the rule without
qualification: *"the wrapper never throws"*. Slice 11's own green added `reportFailure()` — watchdog
plus `trigger_error()`, never an exception — as the sanctioned mechanism. `getExternalUrl()` predates
it (slice 3) and was never brought into line.

The consequence is worse than an inconsistency. `getExternalUrl()` is called from
`FileUrlGenerator::generateString()` during **render**, inside a template, for every image on the
page. An uncaught exception there is a **WSOD on the whole page** — not a broken `<img>`. The
docblock's stated goal ("never a broken `<img>` at render time") is achieved by replacing one broken
image with a blank site.

Note this is a genuine design tension, not an oversight: a misconfigured scheme *should* be loud.
But the loudness belongs at configuration-validation time (the entity's `validate()`, where the
scheme-name and secret-XOR constraints already live) and at status-report time, not at render time.

**Fix:** add the constraint to `FlysystemFilesystem::validate()` so the configuration cannot be
saved broken; add a `hook_requirements()` warning for schemes configured through settings.php, which
bypasses entity validation; and in `getExternalUrl()`, `reportFailure()` and return `''`.

### C10. Exception reporting is applied in one method out of eight (MEDIUM)

#16's `reportFailure()` — the watchdog `operation` / `location` / `reason` triple plus
`trigger_error()` — is called from **`stream_flush()` only**. Every other `catch (\Throwable)` in the
wrapper returns FALSE silently:

| Method | Line | On failure |
|---|---|---|
| `mkdir()` | [:556](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L556) | silent FALSE |
| `rename()` | [:612](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L612) | silent FALSE |
| `rmdir()` | [:651](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L651) | silent FALSE |
| `unlink()` | [:686](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L686) | silent FALSE |
| `stream_open()` (write) | [:845](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L845) | silent FALSE |
| `openReadStream()` | [:882](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L882) | silent FALSE |
| `url_stat()` | [:1095](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L1095) | silent FALSE (correct — absence is a valid answer) |
| `getExternalUrl()` | [:385](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L385) | silent `''` |

For an operator the difference is total: an S3 credential expiry, a bucket policy change and a
network partition all present identically as "the file just did not save", with **nothing in
watchdog**. `architecture.md` §5's promise is that the wrapper never throws *and always reports*;
M2 delivered the first half.

`url_stat()` should stay silent — a missing file is not an error. The other six should report.

### C11. `getType()`'s static scheme leaks across schemes (MEDIUM)

`private static ?string $currentScheme`
([:121](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L121)) is set by
`create()` and read by the static `getType()`. In a request touching two flysystem schemes of
different types, `FlysystemStreamWrapper::getType()` returns the classification of whichever scheme
was bootstrapped last — process-global mutable state answering a per-scheme question.

The manager does not depend on this (it resolves per-scheme through `resolveOwnedWrapperType()`), so
the exposure is limited to direct static callers. The docblock is candid about the constraint —
`StreamWrapperInterface::getType()` is static, so a single class fronting many schemes cannot answer
correctly through that signature. The fallback compounds it: with no `create()` yet, `getType()`
queries the factory and returns the sole configured scheme's type — correct for one scheme, and
`NORMAL` (remote) for any site with two, which is wrong for local schemes.

**Fix:** no clean one exists inside core's interface. Record the constraint in
`feature-evaluation-log.md`, make the fallback fail loudly rather than guessing `NORMAL`, and audit
core and contrib for static `getType()` callers before 4.0 — the answer determines whether this is
cosmetic or not. That audit is #27's scope.

### C12. Smaller items

| # | Location | Finding |
|---|---|---|
| a | [FlysystemFileSystem.php:375](../web/modules/custom/flysystem/src/File/FlysystemFileSystem.php#L375) | `ltrim((string) strstr($uri, '://'), '://')` — `ltrim`'s second argument is a **character list**, not a prefix. `s3:///deep/path` loses all leading slashes; a target legitimately starting with `:` or `/` is corrupted. Use `substr($uri, strpos($uri, '://') + 3)`, as the wrapper does. |
| b | [PrivateDownloadController.php:163-171](../web/modules/custom/flysystem/src/Controller/PrivateDownloadController.php#L163-L171) | Suffix ranges are mis-parsed: `bytes=-500` means *the last 500 bytes* (RFC 9110 §14.1.2); the regex yields `start=0, end=500` — the **first** 501 bytes, returned as `206` with a `Content-Range` that lies. An unsatisfiable range (`start >= $size`) silently degrades to `200` with the whole body instead of `416`. Multi-range requests are not detected. |
| c | [PrivateDownloadController.php:207-211](../web/modules/custom/flysystem/src/Controller/PrivateDownloadController.php#L207-L211) | `serveCorePrivate()` omits core's `$this->streamWrapperManager->isValidScheme($scheme)` guard before building `$scheme . '://' . $target`. The scheme comes from a route default, so this is defence-in-depth rather than a live hole — but it is a deliberate core check dropped without a recorded reason. |
| d | [FlysystemFileSystem.php:262-270](../web/modules/custom/flysystem/src/File/FlysystemFileSystem.php#L262-L270) | `deleteRecursive()` deletes directories as it encounters them in the deep listing, before their children are necessarily processed. Tolerated by the in-memory fixture; adapter-dependent elsewhere. Collect files and directories, delete files first, then directories deepest-first. |
| e | [FilesystemFactory.php:239-251](../web/modules/custom/flysystem/src/Flysystem/FilesystemFactory.php#L239-L251) | `getDefinition()` is **not memoized** while `getAdapter()` and `getFilesystem()` both are. It runs an entity `load()` per call, and it is called from `url_stat()`, `stream_stat()`, `getExternalUrl()`, `getDriverType()`, `isReadOnly()`, `getAdapter()` and once per scheme in the private-download probe. Config entities are cached, so this is CPU rather than I/O — but it is the odd one out in a class built around memoization. |
| f | `url_stat()` | Three adapter round trips per stat on the exists path (`fileExists`, `fileSize`, `lastModified`) where most adapters can answer from one metadata call. Compounds C4: with no cache, `file_exists()` in a loop is 3N remote calls. |
| g | [FlysystemStreamWrapper.php:877-898](../web/modules/custom/flysystem/src/StreamWrapper/FlysystemStreamWrapper.php#L877-L898) | `openReadStream()` buffers the **entire** object into `php://temp` with no size guard. This is the deliberate §4.5 design (seekability for GD/mime detection) and is correct in intent, but a `fopen()` of a 4 GB object on a remote scheme buffers 4 GB before the first `fread()`. Consider a size threshold above which the adapter's own non-seekable stream is returned, with seek attempts failing honestly. |
| h | `FlysystemFileSystem` mutations | None of `saveData()`, `copy()`, `move()`, `delete()`, `deleteRecursive()` invalidates any stat cache. Moot today (C4), a staleness bug the moment C4 is fixed. |

---

## D. Test-suite observations

The suite is real: 142 tests, 453 assertions, no skips masking gaps, `#[RunTestsInSeparateProcesses]`
correctly applied to Kernel/Functional and absent from Unit, and a genuine red-before-green history.
The gaps are specific and they line up exactly with section C.

**Coverage by directory** (`codecov/index.html`):

| Directory | Lines | Methods | Reading |
|---|---|---|---|
| `Flysystem/` (factory, definition) | 100% | 100% | — |
| `Adapter/`, `Attribute/`, `Routing/` | 100% | 100% | — |
| `Cache/` | 96.43% | 80% | **All of it direct-to-service.** Zero integration coverage — C4. |
| `EventSubscriber/` | 88.89% | 80% | — |
| `Controller/` | 87.10% | 33.33% | Line coverage flatters it; C5/C6/C7 all uncovered. |
| `Entity/` | 82.98% | 66.67% | — |
| `StreamWrapper/` | 81.67% | 38.71% | The 18% is the stubs plus the C3 mode paths. |
| **`File/`** | **52.42%** | **36.36%** | **The lowest in the module, and the site of the two CRITICAL findings.** |
| `Form/`, `Plugin/` | 0% | 0% | Artifact — exercised only by Functional tests, which this coverage run does not instrument. Worth confirming rather than assuming. |

Three structural notes:

1. **Seam tests that never cross the seam.** `StatCache` is tested through the container, never
   through a stat. `FileSystemSeamTest` uses `schemetest://` on both ends of every copy and move.
   Both tickets are green; both contracts are unmet. `testing.md` §2's "one seam at a time" is being
   read as "one *side* of the seam" — the tests need to enter through the caller the seam exists to
   serve (`filesize()`, `FileUploadHandler`), not through the service under test.
2. **No test uses a prefixed scheme.** `prefix` is handled in `getExternalUrl()` and ignored in the
   download controller (C7.3). Every test configures `'config' => []`.
3. **No test opens a non-`r`/`w` mode.** `a`, `a+`, `r+`, `c`, `c+` are all in `isWriteMode()`'s
   scope and none is exercised — which is how C3 shipped green.

---

## E. Recommended disposition

M2's tickets stay closed. The following are new Backlog tickets, ordered by what breaks if they are
not done. Each needs its T# pair per `docs/agents/board.md`.

**P0 — file operations are broken today**

1. **Cross-scheme `copy()`/`move()` in the decorated `file_system`** (C1). Four combinations, tests
   for each. Without this, uploads to a flysystem scheme do not work. *Milestone: M3.*
2. **`FileExists` handling across `saveData`/`copy`/`move`, with `getDestinationFilename()`** (C2).
   Three enum values × three methods. Silent data loss until fixed. *M3.*
3. **Append/update `fopen()` modes** (C3) — seed the buffer, or reject the modes honestly. *M3.*

**P1 — release integrity and contracts in green tickets**

4. **Gate #36 on the remaining 13 open issues** (A4) — or record the submodule release-cadence
   decision in `adapter-submodules.md`. Board-only change; do it first, it is cheap. *Now.*
5. **Wire `StatCache` into `url_stat()` and every mutation** (C4), plus `stream_flush()`'s missing
   `invalidateStatCache()` and the `FlysystemFileSystem` mutations (C12h). *M3.*
6. **Stream the private download** (C5) — `readStream()` + `StreamedResponse`, range pushed down.
   *M3.*
7. **Restore `hook_file_download` headers** (C6) — security-relevant; the smallest fix on this list.
   *M3.*

**P2 — correctness, robustness, operability**

8. Private-scheme resolution: carry the scheme in the URL, fix the prefix round trip, add a
   prefixed-scheme test (C7). *M3.*
9. `reportFailure()` in the six silent catches (C10). *M3.*
10. Move the `getExternalUrl()` configuration error to entity validation + `hook_requirements()`;
    report-and-return-`''` at render time (C9). *M3.*
11. `allow_url_fopen` requirements check, and a recorded decision on `STREAM_IS_URL` (C8). *Fold
    into #27.*
12. Range semantics: suffix ranges, 416, multi-range (C12b). *M3.*
13. `ltrim` prefix bug, `deleteRecursive` ordering, `getDefinition()` memoization,
    `isValidScheme()` guard, read-buffer size guard (C12 a, c, d, e, g). *M3, one cleanup ticket.*
14. Static `getType()` audit — enumerate core/contrib static callers, then decide (C11). *Fold into
    #27.*

**P3 — board and document hygiene**

15. Rescope **#18** to its residue and close **#55** as satisfied by `ReadOnlySchemeTest` (A2).
16. Bring `plan-m2.md` §3 and §4 into line with §2.1 (A5) — or mark §4 explicitly historical.
17. Retitle **#35** ("M6:" → "M9:") (A5).
18. Confirm whether `Form/` and `Plugin/` at 0% is a coverage-instrumentation artifact of the
    Functional tests, and if so note it in the coverage README so it is not read as a real gap (D).

---

## Verification

Reproducing this review:

```bash
# Gates (all currently pass)
ddev exec .ddev/commands/web/phpunit      # 142 tests, 453 assertions, 0 failures
ddev exec .ddev/commands/web/phpstan      # [OK] No errors
ddev exec .ddev/commands/web/phpcs        # clean

# C4 — the stat cache has no production callers
grep -rn 'StatCache' web/modules/custom/flysystem/src/ \
  | grep -v 'src/Cache/StatCache.php'
# expect exactly zero matches (the service definition lives in flysystem.services.yml)

# C1/C2/C3/C4 — reproduced with a throwaway KernelTestBase against the in_memory fixture:
#   $fs->move('/tmp/x', 'schemetest://f.txt', FileExists::Error)
#     → InvalidStreamWrapperException: The  stream wrapper could not be mounted.
#   $fs->copy('public://s.txt', 'schemetest://c.txt', FileExists::Error)
#     → InvalidStreamWrapperException: The public stream wrapper could not be mounted.
#   $fs->copy('schemetest://b.txt', 'schemetest://a.txt', FileExists::Error)
#     → returns 'schemetest://a.txt'; a.txt overwritten
#   filesize('schemetest://dir/s.txt') = 5; stat_cache->get(...) = NULL
#   fopen('schemetest://ap.txt','a'); fwrite('-SECOND') → object == '-SECOND' ('FIRST' lost)

# C8 — STREAM_IS_URL vs allow_url_fopen (verified on PHP 8.4.22)
ddev exec php -d allow_url_fopen=0 <script registering one wrapper each way>
#   STREAM_IS_URL  → "no suitable wrapper could be found"
#   flag 0         → opens

# A4 — the release gate must cover every open issue
#   walk blocked_by transitively from #36; today 13 open issues fall outside:
#   100 101 102 103 104 105 106 107 108 109 110 119 120
gh api repos/codementality/flysystem-v4/issues/36/dependencies/blocked_by --jq '[.[].number]|sort'

# A2 — read-only enforcement landed inside M2 while #18/#55 stay open
cd web/modules/custom/flysystem && git log --oneline -S 'ReadOnlyFilesystemAdapter' -- src/
# expect 24d5f0b ("M2: Write path") — slice 4, ticket #11
gh issue view 18 -R codementality/flysystem-v4 --json state   # expect "OPEN"
```

Board mutations must follow the dry-run protocol in `docs/agents/board.md`: fetch fresh state
immediately before operating, present the computed change-set for approval, apply, then re-read and
verify.
