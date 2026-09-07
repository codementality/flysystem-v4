# Flysystem Core at M3 completion — Independent Code Review

Status: Review, 2026-09-04. Scope: the `flysystem` Core module at `web/modules/custom/flysystem`
(module repo `4.0.x`, HEAD `65a9ad8`), the GitHub Projects v2 board #11 and the
`codementality/flysystem-v4` issue tracker, judged against `planning/architecture.md` (§4–§7),
`planning/adapter-submodules.md` (§2.1–§2.2), `planning/testing.md` (§5, §8), `planning/plan-m3.md`,
`planning/plan-m4.md` and `planning/config-and-upgrade.md` (§2).

## Executive summary

**M3's milestone exit criterion is met and the QA gates are green, but Core carries two verified
data-correctness defects on primary user-facing paths that must be fixed before M4 builds on them.**
`file_exists()` returns TRUE for every path on a flysystem scheme (C1) and cross-scheme
`copy()`/`move()` under `FileExists::Rename` hand the caller a URI that does not hold the copied
content (C2). Both are unpinned by the suite — the 243 green tests are green around them. The board
is otherwise in excellent order: M0–M3 are 118 tickets closed with nothing stranded in an
intermediate column.

| Gate | Result |
|---|---|
| `ddev phpunit` | **OK, but there were issues!** Tests: 243, Assertions: 983, Deprecations: 3, PHPUnit Deprecations: 24 |
| `ddev phpstan` | **`[OK] No errors`** |
| `ddev phpcs` | **clean** (no output) |
| `ddev phpcsfix` | not run (not required to judge the findings below) |
| `ddev floci-check` | not run — submodule scope, M4 (`plan-m3.md` §7) |
| `ddev phpunit-ostests` | not run — object-store scope (`plan-m3.md` §7) |

All 3 runtime deprecations were enumerated individually and all 3 originate in `drupal/key`
(`KeyPluginManager` attribute discovery; the `key` and `key_config_override` `@EntityType`
annotations) — the M9/#149 deferral, not module-owned. The 24 PHPUnit deprecations are counted but
their detail is not printed by the canonical config (see L4).

## Findings — by severity

- **CRITICAL — C1** — `url_stat()` fabricates a stat for objects that do not exist, so `file_exists()` is TRUE for every path on a flysystem scheme.
- **CRITICAL — C2** — Cross-scheme `copy()`/`move()` under `FileExists::Rename` return the un-renamed destination URI while writing the content to the renamed one.
- **HIGH — H1** — No mutation through the decorated `file_system` invalidates the persistent StatCache, so a written file keeps its pre-write stat for up to the TTL.
- **HIGH — H2** — Cross-end `transferContent()` buffers the whole file into a PHP string, on exactly the GD/ImageMagick staging path M3 shipped.
- **HIGH — H3** — Core ships `s3`/`aws_s3`/`sftp` config-schema fragments that `adapter-submodules.md` §2.1 assigns to the submodules; M4 will redefine `flysystem.adapter_config.aws_s3`.
- **HIGH — H4** — Three wrapper contracts (`realpath()` for LOCAL, `stream_lock()`, `chmod`→`stream_metadata`) are unimplemented, marked `@todo` against M3 tickets that are closed, and owned by no open ticket.
- **MEDIUM — M1** — `deleteRecursive()` on a single file deletes nothing.
- **MEDIUM — M2** — The private-download route probes every private scheme by bare key: a prefixed scheme never matches, and two schemes sharing a key resolve first-match-wins.
- **MEDIUM — M3** — A public scheme configured with `presigned_expiry` and no `public_url_base` passes validation and yields a site-relative URL with a fabricated `X-Amz-Expires`.
- **MEDIUM — M4** — `LocalAdapterDriver::buildAdapter()` dereferences `$config['root']` unchecked; a settings.php scheme without `root` fatals instead of reporting a configuration error.
- **MEDIUM — M5** — `hook_runtime_requirements` emits the C9 misconfiguration entry with no `severity` and untranslated strings, so it does not render as a warning.
- **MEDIUM — M6** — `flysystem.settings:stat_cache_ttl` is read but has no config schema, no default config, and no form — the #39 "Admin UI" TTL leg does not exist.
- **MEDIUM — M7** — `FilesystemFactory::testConnection()` has no production caller and the entity's `connection_status`/`connection_status_message` fields are never written.
- **MEDIUM — M8** — `plan-m4.md` states #103 has no open blockers; the board says #103 is `blocked_by` #24, which changes M4's start order.
- **MEDIUM — M9** — M4 board hygiene: three unblocked T# tickets sit in Backlog, three feature tickets lack `dependency-blocked`, #153/#159/#160 lack a `blocked_by` edge on #102, and #24's title still reads "M3:".
- **LOW — L1** — `drush/drush ^13` sits in Core's `require` while the module ships no Drush command.
- **LOW — L2** — `FilesystemFactory::definitionFromSettingsPhp()` rebuilds an `AdapterDefinition` on every hot-path call; only the entity source is memoized.
- **LOW — L3** — `PrivateDownloadController::download()` has no `\Throwable` boundary, so an adapter or traversal error becomes a 500 rather than a 404.
- **LOW — L4** — The canonical `phpunit` command reports 24 PHPUnit deprecations without printing them.

---

## Findings detail

### C1. `url_stat()` reports every path as existing — CRITICAL *(verified)*

**What:** `url_stat()` returns a fabricated stat array unconditionally; when the object is neither a
file nor a prefix it still returns an array (with the file-type bits left at `0`) instead of `FALSE`,
and PHP treats any array return as "the path exists".

**Evidence:** `src/StreamWrapper/FlysystemStreamWrapper.php:1371-1470` — `$type = 0` (`:1411`) is the initial
value and neither the `fileExists()` nor the `directoryExists()` branch is required to be taken
before the array is built and returned. Verified with a probe kernel test against the `in_memory`
fixture:

```
1) ZzzReviewProbeTest::testFileExistsIsFalseForMissingObject
PROBE A: file_exists() on a missing object returned TRUE.
Failed asserting that true is false.
```

The behavior is actively pinned in the opposite direction: `tests/src/Kernel/StatLayerTest.php:74-90`
(`testUrlStatReturnsFabricatedStatArray`) asserts `url_stat()` returns an array for
`schemetest://dir/file.txt` with nothing written to it.

**Impact:** Every core caller that asks "does this file exist" gets TRUE on a flysystem scheme.
`ImageStyleDownloadController` serves a derivative it believes exists; `FileSystem::prepareDirectory`,
`file_exists()` guards in contrib, and any `is_file()` check downstream all read a lie.
`FlysystemFileSystem::getDestinationFilename()` is insulated because it asks the operator directly —
which is why the suite stays green — but nothing outside the module is. This also violates
`architecture.md` §4.1 and the `testing.md` §5 pain-map row "Correct `mode` bits so
`file_exists`/`is_file`/`is_dir` tell the truth" verbatim.

**Fix:** Return `FALSE` when neither `fileExists()` nor `directoryExists()` is true, and do not write
a negative result into the StatCache. Amend `StatLayerTest::testUrlStatReturnsFabricatedStatArray`
so its "configured scheme" premise writes the object first (the point it was defending — that a
configured scheme is not blanket-FALSE — survives), and add the missing pain-map assertions:
`file_exists()` FALSE and `is_dir()` FALSE for a missing object, TRUE once written.

### C2. Cross-scheme `copy()`/`move()` return a URI that does not hold the content — CRITICAL *(verified)*

**What:** `transferContent()` resolves the conflict policy internally and writes to the resolved
(renamed) destination, but it returns `void`; `copy()` and `move()` then return the caller's original
`$destination` string.

**Evidence:** `src/File/FlysystemFileSystem.php:195-197` (`copy()`: `$this->transferContent(...)`
then `return $destination;`) and `:260-262` (`move()`, same shape), against
`src/File/FlysystemFileSystem.php:614` where `transferContent()` computes
`$resolved = $this->resolveDestination(...)` into a local variable. Verified:

```
2) ZzzReviewProbeTest::testCrossSchemeCopyReturnsWrittenUri
PROBE B: copy() returned "schemeb://f.txt" but that object does not hold the copied content.
--- Expected  +++ Actual
-'SOURCE'
+'EXISTING-DESTINATION'
```

**Impact:** Silent data mis-reference on the default policy. `FileExists::Rename` is core's default
for `copy()`/`move()`, and `FileRepository`/`file_managed` record the returned URI — so the database
points at the pre-existing file while the copied content sits in an orphaned `f_0.txt`. Blast radius:
every cross-scheme and local↔flysystem copy/move, which is the staging path (`temporary://` →
scheme) M3 shipped for GD and ImageMagick.

**Fix:** Have `transferContent()` return the resolved destination URI (or accept `&$destination`),
and return that value from both `copy()` and `move()`. `deleteSourceAfterTransfer()` is unaffected
(it operates on the source). Add a kernel test asserting the returned URI's content equals the source
content, for all three cross cases (flysystem→flysystem across schemes, local→flysystem,
flysystem→local).

### H1. Writes through `file_system` leave a stale persistent stat — HIGH *(verified)*

**What:** The wrapper's mutations call `invalidateStatCache()`, but `FlysystemFileSystem`'s
`saveData()`/`copy()`/`move()`/`delete()`/`deleteRecursive()` write straight through the League
operator and touch neither `clearstatcache()` nor `StatCache::invalidate()`.

**Evidence:** `grep -n "StatCache\|clearstatcache\|invalidate" src/File/FlysystemFileSystem.php`
returns nothing. Verified:

```
1) ZzzReviewProbeTest::testFileSystemWriteInvalidatesStatCache
PROBE D: after saveData() the stat still reports size 0 (stale cache entry).
Failed asserting that 0 is identical to 10.
```

`architecture.md` §4.4 makes this mandatory ("every mutation … invalidates the module's persistent
stat-cache entries"), and `tests/src/Kernel/StatCacheWiringTest.php:18` names
"no `FlysystemFileSystem` mutation invalidates anything" as part of the defect C4/#133 was raised to
fix — but the class only pins `testUnlinkInvalidatesStatCache` on the wrapper.

**Impact:** A file uploaded through Drupal's primary write API (`FileRepository::writeData()` →
`file_system->saveData()`) reports its pre-write stat for up to the TTL, default 300s. Combined with
C1, the pre-write stat is a well-formed "size 0" record rather than a miss, so `filesize()` returns
0 and `is_file()` is FALSE for five minutes after every upload.

**Fix:** Route the five owned-scheme mutations through one private `invalidate(string $uri)` helper
on `FlysystemFileSystem` that calls `clearstatcache(TRUE, $uri)` plus
`StatCache::invalidate($uri)` (source and destination for copy/move). Separately, make
`StatCache::invalidate()` clear descendants as well as ancestors, so `deleteRecursive()` and
`rmdir()` do not leave child entries behind.

### H2. Cross-end transfers buffer the whole file in memory — HIGH *(reviewed)*

**What:** `transferContent()` reads the source into a PHP string (`$filesystem->read()` or
`file_get_contents()`) and writes that string, rather than piping `readStream()` into
`writeStream()`.

**Evidence:** `src/File/FlysystemFileSystem.php:622` and `:633` (read) and `:646` (write). The
equivalent buffering was already removed from the private-download path (C5/#134,
`PrivateDownloadController.php:224-246`) and from the wrapper's large-object read (C12g/#138,
`FlysystemStreamWrapper.php:1132-1145`), so the streaming pattern exists in the codebase and this
call site was missed.

**Impact:** Peak memory scales with the largest file moved. This is the staging path M3 shipped —
GD and ImageMagick write to `temporary://` and `move()` back through the wrapper — so a large video
or original-resolution image upload can exhaust `memory_limit` on exactly the flow M3 exists to
support. `architecture.md` §4.4 and the C5 precedent both call for streaming.

**Fix:** Replace the read/write pair with `readStream()`/`writeStream()` for the flysystem end and
`fopen()`/`stream_copy_to_stream()` for the local end, closing the handle in a `finally`. Keep the
existing exception mapping. Cover it with a test that asserts content equality on a file larger than
the buffer threshold rather than asserting memory directly.

### H3. Core ships submodule config-schema fragments — HIGH *(verified)*

**What:** `config/schema/flysystem.schema.yml` defines `flysystem.adapter_config.s3`,
`flysystem.adapter_config.aws_s3` and `flysystem.adapter_config.sftp` in Core.

**Evidence:** `config/schema/flysystem.schema.yml:24` (`s3`), `:64` (`aws_s3`), `:105`
(`sftp`). `planning/adapter-submodules.md` §2.1 is explicit: "**Core schema**
(`config/schema/flysystem.schema.yml`) ships only `flysystem.adapter_config.local`." §2.2 assigns
each fragment to its submodule (`config/schema/flysystem_<x>.schema.yml`), and `plan-m4.md` Slice 2
lists "Config schema fragment `flysystem.adapter_config.aws_s3` in the submodule's
`config/schema/`" as an M4 deliverable.

**Impact:** Two conflicts, one now and one at M4. Now: Core declares driver knowledge the carve-out
removed everywhere else (`SECRET_XOR_PAIRS` was deleted for exactly this reason, #100), so a site with
none of the submodules carries schema for drivers it cannot instantiate. At M4: `flysystem_aws` will
define `flysystem.adapter_config.aws_s3` a second time, and Drupal's schema merge resolves duplicate
top-level keys by load order — a silent divergence between what Core says the key set is and what the
submodule says.

**Fix:** Delete the `s3`, `aws_s3` and `sftp` fragments from Core's schema, leaving only
`flysystem.adapter_config.local`. Carry each fragment forward into its submodule as that milestone
lands (M4 already scopes the `aws_s3` one). If any existing test asserts the Core fragments, retarget
it at `local`.

### H4. Three wrapper contracts are unimplemented behind `@todo`s on closed M3 tickets — HIGH *(reviewed)*

**What:** `realpath()`, `stream_lock()` and `stream_metadata()` are unconditional `FALSE` stubs whose
docblocks defer them to M3 tickets that are now closed, and no open ticket owns them.

**Evidence:**

| Stub | File:line | `@todo` says | Ticket state |
|---|---|---|---|
| `realpath()` | `FlysystemStreamWrapper.php:573` | "Resolve a canonical local path for LOCAL-type schemes in M3 (local driver, #78)" | #78 CLOSED |
| `stream_lock()` | `FlysystemStreamWrapper.php:987` | "Advisory locking for LOCAL-type schemes is M3 (local driver, #78)" | #78 CLOSED |
| `stream_metadata()` | `FlysystemStreamWrapper.php:998` | "Stream metadata is M3: chmod → visibility (#17); utime → lastModified" | #17 CLOSED |

Ticket states confirmed via `gh issue list --milestone "M3 Adapter hardening" --state all` (57 closed,
0 open). `architecture.md` §6 names the `chmod` → `stream_metadata` mode→visibility map as a
visibility contract, and §4.1 scopes the `realpath()`-is-`FALSE` rule to *remote* schemes
specifically — Core now ships a LOCAL driver whose `realpath()` is also `FALSE`.

**Impact:** The gaps are real but bounded, which is why the suite is green:
`FlysystemFileSystem::chmod()` returns TRUE for owned URIs so `Image::save()` does not fail, and the
LOCAL driver's `getDirectoryPath()` does return the configured root. What is lost is per-object
visibility control through `chmod()` (§6) and a real local path for LOCAL schemes, which pushes local
schemes down the remote staging path unnecessarily. The governance problem is larger than the code
problem: three deferrals point at closed tickets, so they are invisible to the board (AGENTS.md
rule 11).

**Fix:** File one ticket per stub with its architecture citation (§6 for `stream_metadata`, §4.1/§4.8
for `realpath()` on LOCAL, §4.4 for `stream_lock()` on LOCAL), place them in a milestone, and update
each `@todo` to name the new ticket. If any is a deliberate non-goal, record that as a decision on
the ticket and delete the `@todo` — do not leave a closed-ticket reference standing.

### M1. `deleteRecursive()` on a single file deletes nothing — MEDIUM *(verified)*

**What:** The owned-scheme override treats its argument as a directory unconditionally: it lists
contents (empty for a file), then calls `deleteDirectory()` on the file path.

**Evidence:** `src/File/FlysystemFileSystem.php:306-336` — no `fileExists()` branch before the
listing. Core's `FileSystem::deleteRecursive()` deletes a non-directory path via `delete()`. Verified:

```
3) ZzzReviewProbeTest::testDeleteRecursiveOnAFile
PROBE C: deleteRecursive() on a single file left the object in place.
Failed asserting that true is false.
```

**Impact:** A caller that passes a file path — legitimate under core's contract, and how
`drush image-flush` style cleanup reaches individual derivatives — gets `TRUE` and an undeleted
object. Silent orphaning, and the return value gives no signal.

**Fix:** Branch at the top: if `fileExists($target)`, `delete($target)` and return TRUE; otherwise
the existing directory walk. Add the single-file case to `FileStreamCleanupTest`'s C12d coverage.

### M2. The private-download probe matches on the bare key across all private schemes — MEDIUM *(reviewed)*

**What:** `download()` iterates every configured private scheme and serves the first whose operator
reports the requested key, while `getExternalUrl()` builds that key as `prefix + target`.

**Evidence:** `src/Controller/PrivateDownloadController.php:120-133` (the probe loop, on the raw
`?file=` value) against `FlysystemStreamWrapper.php:498` (`$key = rtrim($prefix,'/') . '/' .
$target`, then the route is built from `$key`). The mismatch is already recorded as the C7 `@todo` at
`PrivateDownloadController.php:94-98`; no open ticket owns it (searched the tracker for
`prefix`/`probe`/`C7` — only the closed #93 matches).

**Impact:** Two distinct effects. (a) Any scheme configured with a `prefix` — the whole point of the
`aws_s3` config surface M4 ships — generates URLs whose key includes the prefix and then fails the
probe, so its private downloads 404. (b) With two private schemes holding the same key, the first
enumerated wins regardless of which scheme's URL was requested; the access check runs against the
scheme actually matched, so this is a wrong-file result rather than an authorization bypass, but it
is non-deterministic from the operator's point of view. Cost is also per-request: one `fileExists()`
round trip per private scheme on every download.

**Fix:** Carry the owning scheme in the URL rather than re-deriving it — the `system.files` route
already has a `{scheme}` segment, and `getExternalUrl()` can emit the flysystem scheme there instead
of relying on the default `private`. Then resolve one scheme, strip its configured `prefix` from the
key before the operator call, and drop the probe loop. This closes the prefix mismatch, the ambiguity
and the N-round-trip cost together. File it as one ticket and remove the C7 `@todo` with it.

### M3. A presigned-only public scheme validates but yields a site-relative URL — MEDIUM *(reviewed)*

**What:** `presigned_expiry` alone satisfies both the entity validator and the requirements check,
but with `public_url_base` NULL `getExternalUrl()` builds `'' . '/' . key` and appends a literal
`X-Amz-Expires` that is not part of any signature.

**Evidence:** `FlysystemStreamWrapper.php:521-533` (`$base = $publicUrlBase === NULL ? '' : …`, then
`$url .= '?X-Amz-Expires=' . (int) $presignedExpiry`), accepted by
`src/Entity/FlysystemFilesystem.php:197-208` and `src/Hook/FlysystemRequirements.php:49-54`, both of
which treat `isset($config['presigned_expiry'])` as sufficient. `UrlPolicyTest.php:236-263` only
exercises presigned *with* a base, so the no-base case is unpinned. The code comment says "concrete
S3 signing arrives with the M3 shipped drivers (#17/#78)" — both closed, no signing shipped.

**Impact:** An operator following the documented "private bucket with presigned URLs" shape from
`config-and-upgrade.md` §2 and omitting `public_url_base` saves successfully, sees no status-report
warning, and gets URLs pointing at their own Drupal site with a query parameter that resembles an AWS
signature but grants nothing.

**Fix:** Until a driver implements real signing, treat `presigned_expiry` as insufficient on its own:
require `public_url_base` for a public scheme in both the entity validator and the requirements hook,
and drop the fabricated `X-Amz-Expires` stand-in from `getExternalUrl()` in favor of a
driver-provided signing seam (`temporaryUrl()`-style) that M4's `aws_s3` driver fills. Add the no-base
presigned case to `UrlPolicyTest`.

### M4. `LocalAdapterDriver::buildAdapter()` dereferences `root` unchecked — MEDIUM *(reviewed)*

**What:** `new LocalFilesystemAdapter($config['root'])` runs with no guard, though `root` is only
enforced as `required` by the admin form — the settings.php source has no validation path at all.

**Evidence:** `src/Plugin/Flysystem/Adapter/LocalAdapterDriver.php:34`.
`FilesystemFactory::definitionFromSettingsPhp()` (`src/Flysystem/FilesystemFactory.php:471-485`)
validates only the `driver` key.

**Impact:** `$settings['flysystem']['x'] = ['driver' => 'local', 'config' => []]` produces an
undefined-array-key warning and a `TypeError` from inside `buildAdapter()`. The wrapper's `\Throwable`
catches turn that into a silent FALSE at the stream layer, but `FilesystemFactory::getFilesystem()`
called from `FlysystemFileSystem` surfaces it as `InvalidStreamWrapperException` with an unhelpful
cause. Per `architecture.md` §5 boundary 3 a configuration error should read as one.

**Fix:** Throw `\InvalidArgumentException` naming the missing key from `buildAdapter()` when `root` is
absent or not a non-empty string, and have `testConnection()`/the requirements hook report it. The
same guard belongs in every driver that declares `required` config keys — consider a shared
`assertRequiredConfig()` on `AdapterDriverPluginBase` so the M4 submodule inherits it.

### M5. The C9 requirements entry is not a warning — MEDIUM *(reviewed)*

**What:** `FlysystemRequirements::runtime()` returns entries with `title` and `description` only —
no `severity` key — and both strings are plain PHP with the scheme name interpolated rather than
`$this->t()` with placeholders.

**Evidence:** `src/Hook/FlysystemRequirements.php:50-54`.

**Impact:** Without `'severity' => RequirementSeverity::Warning`, the status report renders the entry
in the informational section, so the misconfiguration C9/#136 was raised to surface is easy to miss —
the entry exists but does not alarm. The untranslated strings also violate the `plan-m3.md` §5
translations constraint, and a scheme name from settings.php (unconstrained, unlike entity ids) is
interpolated into markup without a placeholder.

**Fix:** Add `'severity' => RequirementSeverity::Warning` (Drupal 11.4's enum, not the legacy
constant), wrap both strings in `$this->t()` with an `@scheme` placeholder, and add
`StringTranslationTrait`. Extend the existing requirements coverage to assert the severity, not just
the presence of the entry.

### M6. The stat-cache TTL config has no schema, no default, and no form — MEDIUM *(verified)*

**What:** `StatCache::getTtl()` reads `flysystem.settings:stat_cache_ttl` as the Admin UI source, but
that config object is defined nowhere in the module.

**Evidence:** `src/Cache/StatCache.php:147-154` reads it;
`grep -rn "flysystem.settings" src/ config/ tests/` returns only that read and its docblock. There is
no `config/install/flysystem.settings.yml` and no `flysystem.settings` schema in
`config/schema/flysystem.schema.yml` (`find config -type f` returns the schema file alone). The
StatCacheTest coverage exercises the settings.php override only
(`tests/src/Kernel/StatCacheTest.php:173-180`).

**Impact:** Decision #39B's user-facing half does not exist — the TTL is adjustable only by editing
settings.php. Worse, if a site or a future form ever writes `flysystem.settings`, the write fails
Drupal's config-schema validation because no schema declares the key, and kernel tests with strict
schema checking would fail with it.

**Fix:** Either implement the leg (a `flysystem.settings` schema entry with the six valid TTL values,
a `config/install` default of 300, and a small settings form under the Flysystem admin section) or
record the decision to drop it and remove the config read from `StatCache::getTtl()`. Do not leave a
read against an undeclared config object. Whichever way it goes, the choice belongs on a ticket —
#13 and #50 are both closed.

### M7. The connection test has no production caller — MEDIUM *(verified)*

**What:** `FilesystemFactory::testConnection()` is fully implemented and tested, but nothing in `src/`
calls it, and the entity's `connection_status`/`connection_status_message` fields keep their
constructor defaults forever.

**Evidence:** `grep -rn "testConnection" src/ tests/` matches only the definition
(`src/Flysystem/FilesystemFactory.php:420`) and the two kernel tests.
`grep -rn "connection_status" src/ config/` matches only the entity property declarations
(`src/Entity/FlysystemFilesystem.php:60-61, 129, 136`) and the schema. `FlysystemFilesystemForm`
contains no test-connection element and never sets either field. #93 (CLOSED) scoped the probe and
the message sanitization, not the UI wiring; no other ticket mentions "connection".

**Impact:** An operator configuring a remote scheme gets no feedback that their credentials or
endpoint work — the exact failure mode #93 was raised to fix, one layer up. The
`connection_status: 'untested'` value is exported into every scheme's config YAML, permanently
untrue. This lands squarely on M4, where the first genuinely remote driver ships and a wrong bucket
is otherwise silent until the first upload.

**Fix:** Add a "Test connection" AJAX submit to `FlysystemFilesystemForm` that calls
`testConnection()` for the currently selected driver and config, shows the sanitized result, and
persists it into `connection_status`/`connection_status_message` on save. File it with an M4
dependency edge so the aws_s3 driver lands with working feedback.

### M8. `plan-m4.md` and the board disagree on #103's blockers — MEDIUM *(verified)*

**What:** The M4 plan records #103 (T102, the submodule's red contract tests) as startable now; the
tracker has it blocked by the Floci layer.

**Evidence:** `planning/plan-m4.md` §2.3 lists #103's "Blocked by" cell as `—` and §3 states
"**#103** (T102) `blocked_by` none open". GraphQL `blockedBy` on 2026-09-04 returns for #103:
`#100(CLOSED), #24(OPEN), #23(CLOSED), #19(CLOSED), #17(CLOSED), #78(CLOSED)` — #24 is open and
unstarted. The board agrees with the tracker (#103 sits in Backlog with `dependency-blocked`).

**Impact:** The plan's §4 slice order implies Slice 1 can run in parallel with the Floci gate; the
board says the whole of M4 serializes behind #24/#61. Anyone planning from the document alone picks
the wrong first ticket, and the plan's §3 header claims "Edges verified 2026-09-05 via GraphQL
`blockedBy`" — so the discrepancy reads as verified when it is not.

**Fix:** Correct §2.3 and §3 of `plan-m4.md` to record #103 `blocked_by` #24, and re-derive the §4
slice-order note from the real edges. Also drop the stale §3 instruction to "add #102/#104/#106 edges
if not already present" on #36 — all three edges are present today.

### M9. M4 board hygiene — MEDIUM *(verified)*

**What:** Four board/tracker inconsistencies in the M4 milestone, all fixed in one pass.

**Evidence:** GraphQL board query and `gh issue list --milestone "M4 flysystem_aws"`, 2026-09-04:

| Item | Observed | `docs/agents/board.md` rule |
|---|---|---|
| #156, #165, #166 | zero `blocked_by`, sitting in **Backlog** | Ready = "unblocked and startable — every `blocked_by` ticket has started" |
| #153, #159, #160 | blocked by unstarted T#s, no `dependency-blocked` label | "sits in Backlog with the `dependency-blocked` label" |
| #153, #159, #160 | no `blocked_by` edge on #102 | consumer-chain rule — these cannot be validated before the driver exists |
| #24 | title "**M3:** Floci integration layer + aws_s3 endpoint override", milestone M4 | milestone move recorded in `plan-m4.md` §2.3 |

**Impact:** The missing #102 edges are the substantive one: once #156/#165/#166 start, their feature
tickets #153/#159/#160 become Ready with no `blocked_by` on the aws_s3 driver — precisely the
"approved but unconsumable" trap the 2026-08-31 consumer-chain correction was written after. The
other three are navigational: a reader scanning the board sees three startable tickets buried in
Backlog and a ticket labelled M3 inside M4.

**Fix:** Move #156/#165/#166 to Ready; add `dependency-blocked` to #153/#159/#160; add
`blocked_by #102` to #153, #159 and #160; retitle #24 with its M4 prefix. All four are board
mutations — dry-run first per `docs/agents/board.md`.

### L1. `drush/drush` is a hard runtime dependency with no Drush command — LOW *(verified)*

**What:** `composer.json` requires `drush/drush: ^13` in `require`, and the module ships no Drush
command, service, or `drush.services.yml`.

**Evidence:** `composer.json:13`; `grep -rni "drush" src/ *.yml` matches only two prose comments
(`FlysystemFileSystem.php:45`, `FilesystemFactory.php:358`). Note this is spec-sanctioned —
`adapter-submodules.md` §2.1 lists drush in Core's require — so it is a decision to revisit, not a
deviation.

**Impact:** Every site installing `drupal/flysystem` pulls Drush 13 into its production dependency
tree whether or not it uses Drush, and Drupal.org packaging conventions treat this as a defect. The
commands the requirement anticipates (migration verification, reconcile) live in M8's submodule.

**Fix:** Move `drush/drush` to `require-dev` (or `suggest`) in Core and declare it in `require` on
whichever package actually ships commands. Worth deciding at M9 packaging rather than now.

### L2. The settings.php definition is rebuilt on every hot-path call — LOW *(reviewed)*

**What:** `getDefinition()` memoizes only the entity-sourced branch; a settings.php scheme constructs
a fresh `AdapterDefinition` on every call.

**Evidence:** `src/Flysystem/FilesystemFactory.php:257-275` — the C12e memo (`$entityDefinitions`)
guards the entity path; the settings path returns `definitionFromSettingsPhp()` unmemoized, with the
docblock at `:114-127` explaining that tests swap the settings singleton.

**Impact:** `url_stat()` alone calls `getDefinition()` and `getFilesystem()` per stat, and
`getExternalUrl()`, `isReadOnly()` and `getDriverType()` each call it again. The work is small
(array reads plus an object construction), so this is allocation churn on a hot path, not a
round trip — measurable only under heavy listing/render loads.

**Fix:** If it is worth optimizing, memoize the settings-sourced definition keyed on the settings
array's identity so a swapped singleton still invalidates. Given the test constraint that motivated
the current shape, "leave as documented" is a legitimate resolution — record it either way.

### L3. The private-download controller has no exception boundary — LOW *(reviewed)*

**What:** `download()` calls `getDefinition()`, `getFilesystem()` and `fileExists()` with no
`try`/`catch`, so any adapter-level failure propagates as an unhandled exception.

**Evidence:** `src/Controller/PrivateDownloadController.php:114-133`.

**Impact:** A network failure, a bad credential, or a traversal-guard rejection from
`LocalFilesystemAdapter` on an attacker-supplied `?file=../../` turns a file request into a 500 with
a stack trace in the log, where a 404 is the correct and quieter answer. `architecture.md` §5
boundary 3 asks for "one clean line" from admin/CLI surfaces; the same reasoning applies here.

**Fix:** Wrap the probe loop in a `try`/`catch (\Throwable)` that logs via the flysystem channel and
continues to the next candidate (or falls through to `serveCorePrivate()`), so a single unhealthy
scheme cannot 500 a download that another scheme owns.

### L4. The canonical `phpunit` command hides its PHPUnit deprecations — LOW *(verified)*

**What:** The suite summary reports `PHPUnit Deprecations: 24` but the run prints no detail block for
them, so there is nothing to triage.

**Evidence:** `grep -n "deprecation" phpunit.log` returns exactly one line — `76 tests triggered 3
deprecations:` (the runtime ones). The final line reads `Tests: 243, Assertions: 983, Deprecations: 3,
PHPUnit Deprecations: 24.` with no corresponding section.

**Impact:** Twenty-four deprecations against PHPUnit's own API are accumulating unread. PHPUnit 12
will turn some into errors, and the project has no visibility into which test classes carry them.

**Fix:** Add `--display-phpunit-deprecations` to `.ddev/commands/web/phpunit` (it does not change what
the pipeline runs, only what the local gate prints), then triage what it lists.

---

## What this review got right

Bounding the findings above — this is a strong codebase and most of what I looked for was already
handled:

- **The exception strategy is real and consistent.** Every `stream_*` method has a `\Throwable`
  boundary that returns the PHP-protocol value, and C10/#137's "report, never a silent FALSE" is
  applied uniformly through `reportFailure()` (watchdog + `trigger_error`). The decorated
  `file_system` maps flysystem exceptions onto the eight core `FileException` subclasses with the
  original as `$previous`, exactly as §5 boundary 2 specifies.
- **The Range/206 implementation is correct**, including the two cases most implementations get
  wrong: a suffix range (`bytes=-500`) resolves to the last N bytes, and an unsatisfiable range
  returns 416 with `bytes */size` rather than degrading to 200. Multi-range is honestly refused.
- **`url_stat()` never calls `visibility()`** (#3616487), the private other-read bit is preserved
  (#3618526), and `dev`/`ino` are hash-stable — the ACL-disabled-bucket work M4 depends on is done.
- **The security gate on private local schemes rooted in the web root** is a deliberate, well-judged
  divergence from core: a prominent warning plus a required acknowledgment checkbox, enforced in both
  `form()` and `validateForm()`.
- **Secret handling.** `SECRET_XOR_PAIRS` is gone; the XOR pairs derive at runtime from the driver's
  own `getConfigKeys()` `secret` markers, including nested mappings — Core holds zero driver
  knowledge here, and `testConnection()` sanitizes failure text with the full detail going to
  watchdog only.
- **The `temporary://` reservation** is enforced at the single owned-scheme resolution point, so no
  configuration source can take it — the staging path cannot be broken by config.
- **Board discipline.** 118 tickets closed across M0–M3 with nothing stranded in In progress, In
  review, or Tests complete, failing; every M3 feature has its T# partner. The findings in M8/M9 are
  hygiene on the *next* milestone, not decay in the last one.
- **The gates are genuinely green** — PHPStan level 8 with zero errors and PHPCS clean against the
  canonical configs, not a variant.

---

## Verification

Run from the project root. All gate output quoted above is from these commands on 2026-09-04.

```bash
ddev phpstan    # → "[OK] No errors"
ddev phpcs      # → no output (clean)
ddev phpunit    # → "OK, but there were issues!  Tests: 243, Assertions: 983,
                #    Deprecations: 3, PHPUnit Deprecations: 24."
```

C1, C2, H1 and M1 were verified with a temporary kernel test
(`tests/src/Kernel/ZzzReviewProbeTest.php`, since deleted; both repos verified clean afterward)
asserting the documented contract so the failure message prints the observed value. To reproduce, add
a `KernelTestBase` with modules `flysystem, flysystem_inmemory_test, file, image, key, field, system`,
register an `in_memory` scheme via `setSetting('flysystem', …)` +
`$this->container->get('flysystem.stream_wrapper_manager')->register()`, then:

```php
// C1 → observed TRUE
file_exists('schemetest://definitely-missing.txt');

// C2 → observed "schemeb://f.txt", which still holds 'EXISTING-DESTINATION'
$factory->getFilesystem('schemea')->write('f.txt', 'SOURCE');
$factory->getFilesystem('schemeb')->write('f.txt', 'EXISTING-DESTINATION');
$fs->copy('schemea://f.txt', 'schemeb://f.txt', FileExists::Rename);

// H1 → observed size 0 after writing 10 bytes
stat('schemetest://later.txt');
$fs->saveData('CONTENT-12', 'schemetest://later.txt');
clearstatcache(TRUE, 'schemetest://later.txt');
stat('schemetest://later.txt')['size'];

// M1 → observed: the object survives
$factory->getFilesystem('schemetest')->write('lonely.txt', 'x');
$fs->deleteRecursive('schemetest://lonely.txt');
$factory->getFilesystem('schemetest')->fileExists('lonely.txt');
```

Run it with:

```bash
ddev exec bash -c 'SIMPLETEST_DB=mysql://db:db@db/test SIMPLETEST_BASE_URL=http://web \
  /var/www/html/vendor/bin/phpunit -c /var/www/html/web/core/phpunit.xml.dist \
  --bootstrap /var/www/html/web/core/tests/bootstrap.php \
  /var/www/html/web/modules/custom/flysystem/tests/src/Kernel/<probe>.php'
```

Tracker and board state (H4, M7, M8, M9):

```bash
gh issue list --repo codementality/flysystem-v4 --milestone "M3 Adapter hardening" --state all
gh issue list --repo codementality/flysystem-v4 --milestone "M4 flysystem_aws" --state all --json number,labels
gh api graphql -f query='query{repository(owner:"codementality",name:"flysystem-v4"){
  issue(number:103){blockedBy(first:20){nodes{number state}}}}}'
```

Static checks (H3, M6, M7, L1):

```bash
grep -n "adapter_config" web/modules/custom/flysystem/config/schema/flysystem.schema.yml
grep -rn "flysystem.settings" web/modules/custom/flysystem/src web/modules/custom/flysystem/config
find web/modules/custom/flysystem/config -type f     # → the schema file alone
grep -rn "testConnection\|connection_status" web/modules/custom/flysystem/src
grep -rni "drush" web/modules/custom/flysystem/src web/modules/custom/flysystem/*.yml
```

Board columns (M9) — the `gh issue list` above proves the labels and the `blocked_by` edges; the
Status field (which column each ticket sits in) comes from the board itself:

```bash
gh api graphql --paginate -f query='
query($endCursor: String) {
  organization(login: "codementality") {
    projectV2(number: 11) {
      items(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          content { ... on Issue { number state milestone { title } } }
          fieldValues(first: 20) { nodes {
            ... on ProjectV2ItemFieldSingleSelectValue {
              name field { ... on ProjectV2SingleSelectField { name } } } } }
        }
      }
    }
  }
}' --jq '.data.organization.projectV2.items.nodes[] |
  "\([.fieldValues.nodes[] | select(.field.name=="Status") | .name][0])|\(.content.state)|\(.content.milestone.title // "none")"' \
  | sort | uniq -c
```

Observed: `9 Backlog|OPEN|M4 flysystem_aws`, `1 Ready|OPEN|M4 flysystem_aws`, and every M0–M3 row
`Done|CLOSED` — nothing in In progress, In review, or Tests complete failing.

PHPUnit deprecation accounting (L4):

```bash
grep -n "deprecation" phpunit.log   # → one line only: "76 tests triggered 3 deprecations:"
                                    #   no section for the 24 PHPUnit deprecations
```

---

## Disposition

Nothing here has been filed, labelled, or moved — every item below is a proposal for your decision.

**Before any M4 code is written** (these are the foundations M4's driver sits on):

1. File and fix **C1**, **C2** — each with its T# red-test partner per AGENTS.md rule 12. C1's fix
   also amends `StatLayerTest`, so its T# must cover the corrected assertion.
2. File and fix **H1**, **H3**. H3 must land before #102 writes its own schema fragment.
3. Correct **M8** in `planning/plan-m4.md`, and apply the four **M9** board mutations. Both are
   documentation/board work with no code and no T#.

**Into the M4 milestone, sequenced with the driver:**

4. **M2**, **M3**, **M7** — all three surface for the first time on a real remote driver, and M2's
   fix removes the C7 `@todo`.
5. **H4** — one ticket per stub, so the deferrals stop pointing at closed tickets.

**Into M7 (test hardening) or M9 (release) as you judge:**

6. **H2**, **M1**, **M4**, **M5**, **M6**, **L3** — correctness and robustness, none of them
   blocking M4's start.
7. **L1**, **L4** — packaging and tooling; **L1** belongs with the M9 packaging pass, **L4** is a
   one-line change to `.ddev/commands/web/phpunit`.
8. **L2** — decide and record; "leave as documented" is a legitimate outcome.

**Governance note:** C1, C2, H1, H2 and M1 all live on code paths whose tickets are closed and
approved. Per the milestone-immutability rule, M3 is not reopened — these should be filed as new
tickets in a current milestone that cite the M3 ticket they correct, not as reopened M3 work.
