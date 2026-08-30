# Flysystem v4 — Architecture

Status: **Draft** — derived from the design discussion (2026-08). Companion documents: `config-and-upgrade.md`, `testing.md`, `migration.md`, `feature-evaluation-log.md`, `drupal-issue-queue.md`.

---

## 1. Goals

Provide an **opt-in replacement layer** for Drupal Core's filesystem and stream-wrapper functionality. A site that configures a scheme (via settings.php or config entities) gets flysystem-backed storage; core schemes (`public://`, `private://`, `temporary://`) are **remappable** to flysystem adapters, and new schemes are definable. Unconfigured schemes behave exactly as core.

**Non-goals**: patching or rewriting Drupal Core. No backporting focus to v3 (byproducts only). Core ships two adapters (`in_memory`, `local`); three external-SDK adapters (`s3`, `aws_s3`, `sftp`) are optional submodules; third-party adapters are the community's responsibility. See `adapter-submodules.md` (the carve-out plan, 2026-08-30).

**Core constraint**: every flysystem service that replaces a core service **adheres to the existing core interface contract** (`StreamWrapperInterface`, `FileSystemInterface`, `StreamWrapperManagerInterface`), so contrib modules relying on those contracts continue to function.

## 2. Support boundary

- **Core adapters (shipped, supported, built into Core)**: `in_memory`, `local`.
- **Optional submodules (shipped with the project, enabled independently)**: `s3` (AsyncAws,
  `flysystem_asyncaws`), `aws_s3` (AWS SDK v3, `flysystem_aws`), `sftp` (`flysystem_sftpv3`). Each owns its
  driver plugin, schema, config form, and tests — Flysystem Core has zero prior knowledge of them.
  See `adapter-submodules.md`.
- **Third-party adapters (GCP, Azure, etc.)**: supported as *extension points* — the plugin API is stable, documented, and tested — but they are the community's responsibility, not a module support burden. Documented verbatim in the developer README.
- **In-memory adapter**: a shipped Core driver (REMOTE-type, exercises the remote code paths in tests).

## 3. Core architecture

### 3.1 The contract-faithful wrapper (load-bearing)

A single generic `FlysystemStreamWrapper` implements the full `StreamWrapperInterface` (and the `PhpStreamWrapperInterface` stream methods). It is **self-sufficient outside the container**: PHP instantiates wrappers directly for native calls (`move_uploaded_file()`, `is_dir()`, `fopen()`), so the wrapper resolves its scheme/definition from the URI alone via a static bootstrap path — no reliance on a primed DI factory (#3616485).

Because the decorated `stream_wrapper_manager` resolves flysystem wrappers for owned schemes through every core consumer (`getViaScheme`/`getViaUri`), the wrapper's **entire** interface surface is exercised in production. Every method is a tested contract (see §4).

### 3.2 The decorated `stream_wrapper_manager` — the single resolution seam

The module **decorates the `stream_wrapper_manager` service** with a subclass that, for any scheme flysystem owns (from either configuration source), returns the flysystem wrapper; for everything else it delegates to the core manager. This is the mechanism that makes "replace core services" work while adhering to `StreamWrapperManagerInterface`.

Rationale (VERIFIED against core 11.4): a tagged `scheme: public` service wins the `StreamWrapperClassesPass` array (last-wins) but **loses the Symfony `ServiceLocator` index** (`PriorityTaggedServiceTrait::findAndSortTaggedServices` is **first-wins**, `if (isset($indexes[$index])) continue;`). So without decoration, `getViaUri()` on a remapped `public://` would resolve core's `PublicStream`, breaking URL generation and `realpath`. The decorator is the only seam that makes both the class/type level and the instance-resolution level agree.

### 3.3 Scheme registration

- Schemes are **tagged DI services** (`stream_wrapper` tag, `scheme` attribute) collected by core's `StreamWrapperClassesPass` — the D11 mechanism (`hook_stream_wrappers` is dead since D9).
- **One registration path for both configuration sources.** settings.php schemes register at container build; config-entity schemes register at runtime through the decorated manager (which keeps core's manager in sync). This resolves the 3.0 defect where config-entity schemes bypassed core's manager entirely (#3618567, #3616485).
- Scheme names: lowercase letters, numbers, hyphens only; **no underscores** (PHP rejects them for stream schemes).

### 3.4 Single source of truth for scheme definitions

The `FilesystemFactory` is the single resolution point: **settings.php takes priority** over config entities per scheme (preserved 3.0 precedence). Both sources produce the same `AdapterDefinition` (normalized: driver, config, `public_url_base`, `writable`, visibility normalization).

## 4. Behavioral contracts (each is a tested requirement)

### 4.1 Stat layer (`url_stat`) — correctness core

- **Fabricated stat arrays are consistent and lie-free**: stable `dev`/`ino` derived from a hash of the path (never random per call), `mode` bits encode the correct file-type (`S_IFREG`/`S_IFDIR`) so `file_exists()`/`is_file()`/`is_dir()` tell the truth, and **private files keep the other-read bit** so `is_readable()`/private downloads don't 500 (#3618526).
- **`url_stat` never calls `visibility()`** — no ACL round trip, no throw on ACL-disabled buckets (#3616487). Stat is fabricated from `fileSize`/`lastModified`/`has` only.
- `is_dir` semantics for prefix-based stores: an existing prefix counts as a directory.
- **`realpath()` returns `FALSE` for remote, always** — never a URI, never a bogus path. `FALSE` is load-bearing: both GD and ImageMagick key their staging off it, and core's `FileSystem::realpath()` handles it explicitly.

### 4.2 `getType()` — per-scheme, adapter-driven

The wrapper's type classification (LOCAL/REMOTE) is derived from the adapter, not a constant. Load-bearing consumers: GD's staging decision (`getWrappers(LOCAL)`, bitwise AND filter) and the `STREAM_IS_URL` registration flag. Local adapter → LOCAL; S3/SFTP → REMOTE.

### 4.3 URL policy (`getExternalUrl`)

- **Public content**: `public_url_base` is the primary mechanism (preserved 3.0 setting, cache-safe). When the base host differs from the site, `FileUrlGenerator::transformRelative()` leaves it absolute; when it matches, it relativizes.
- **No-base remote public scheme**: neither `public_url_base` nor explicit `presigned_expiry` → **loud configuration error at validation time** (never a broken `<img>` at render time).
- **Presigned**: explicit opt-in only (`presigned_expiry`), documented cache-unsafe. The v3 implicit default (3600s) is a **deliberate, documented BC break**.
- **Private content**: access-checked via the `file_download` route (streams adapter → PHP → browser); origin-masked by design.
- **Encoding**: every URL path segment is percent-encoded (`#`, spaces, commas) — never raw concatenation (#3616492).
- **No double-slash / protocol-relative artifacts** from empty directory paths (#3616488, #3616491).
- **Prefix inclusion**: when a scheme uses an S3 `prefix`, `getExternalUrl()` includes it (the prefix is part of the object key); the 3.0-ref 404 on prefixed public URLs is fixed.
- **`assets://` interplay**: verified unaffected (it `extends PublicStream` and sidesteps our shadow) — but explicitly chosen, not discovered.

### 4.4 Write path — single PUT on flush

- **Buffer all `fwrite`s into a seekable temp/`php://temp`; issue exactly one upload on `stream_flush`** (never per-`fwrite`; PHP's `copy()` moves 8KB chunks, and per-chunk uploads are the write-performance killer).
- Multipart only above a threshold.
- **Native copy/move when both ends are flysystem-owned** (`stream_rename` delegates to the adapter's native `move()`; S3 CopyObject is server-side). Cross-adapter moves stream.
- **Stat-cache invalidation is a mandatory step of the write path**: every mutation (replace/delete/rename/mkdir/rmdir) clears PHP's stat cache (`clearstatcache`) for the affected paths **and** invalidates the module's persistent stat-cache entries (object + parent prefixes).
- Content-Type on write: Drupal's guessed mime is passed explicitly (`mimetype` on aws_s3, `ContentType` on s3) so stored S3 Content-Type == Drupal `filemime`.

### 4.5 Read path — seekable semantics

Remote read streams are buffered (memory up to a threshold, then temp) so consumers that `fseek` (GD `getimagesize`, mime detection, PDF/office readers) work (#3616493). `stream_cast()` behaves consistently.

### 4.6 Stat cache

- **Persistent stat cache** (a cache bin, keyed per object, TTL-bounded) for cross-request read savings — Drupal's bias toward caching, honored.
- **Explicit expiry built into file management**: mutations invalidate affected entries (see §4.4). The only unavoidable staleness edge is writes outside Drupal (direct to S3 by another app); the TTL bounds it, and it is documented.

### 4.7 Temp files

`temporary://` stays **local, always** — aligned with core's `FileSystem.php:647` (default temp dir) and `PhpStorageFactory.php:49` (opcache). GD and ImageMagick staging both write through `temporary://`; `tempnam()` needs a real local path.

### 4.8 Local-path contract (`getDirectoryPath`, `deleteRecursive`)

- The wrapper implements the full surface core can call on a scheme, including the `LocalStream`-ish methods core reaches for (`getDirectoryPath()` from `AssetRoutes`, `tempnam()`, path processors). Where core's assumptions are genuinely local-only, the decorated `file_system` routes around them (#3600726, #3611227, #3540678).
- **`deleteRecursive()` is correct for remote schemes** — the decorated `file_system` must not inherit core's early-return-on-`realpath()==FALSE` bug (core #3559132; `drush image-flush` currently deletes nothing on remote storage).

## 5. Exception handling — three boundaries

Per `feature-evaluation-log.md` Item 5:

1. **Stream wrapper**: never throws. Catches every flysystem exception inside `stream_*`, returns the primitive contract value, `trigger_error()` with an actionable message when `STREAM_REPORT_ERRORS` is set, and logs via watchdog (`operation()` + `location()` + `reason()`).
2. **Decorated `file_system`**: translates flysystem exceptions → the core `FileException` subclasses (`UnableToReadFile`→`FileNotExistsException`; `UnableToWriteFile`/`UnableToMoveFile`/`UnableToCopyFile`→`FileWriteException`; `UnableToCreateDirectory`→`DirectoryNotReadyException`; mount/scheme failures→`InvalidStreamWrapperException`; existence→bool). Reuses the 8 core subclasses, never invents new ones; passes the flysystem exception as `$previous`.
3. **CLI/admin** (connection test, migration, reconcile): one clean line from `operation()`/`location()`/`reason()`; config/validation errors surface as validation messages, never stack dumps.

## 6. Visibility strategy

Per `feature-evaluation-log.md` Item 6:

- **Scheme-derived visibility is the source of truth**: `public://`-type schemes → `Visibility::PUBLIC`, private → `Visibility::PRIVATE`, passed as write config. `directory_visibility` forced to **private** (the S3 default is public — root of #3616482).
- **Per-scheme `use_acl` flag, driver-scoped config key, default `FALSE`**: when off, subclassed S3 adapters omit the ACL on upload/copy/createDirectory, `visibility()` returns the scheme default (no GetObjectAcl), `setVisibility()` no-ops. Required to work on modern BucketOwnerEnforced buckets (any ACL → `AccessControlListNotSupported`). When on, stock ACL behavior. **Documented explicitly + described in the config-entity form field** (not just labeled).
- **Never call `visibility()` inside `url_stat`** (§4.1).
- **copy/move**: `retain_visibility = false` or explicit visibility on S3 paths (avoids GetObjectAcl round trips); document the local/SFTP 0664→0644 normalization; explicit destination visibility on cross-adapter moves.
- **`chmod` → `stream_metadata`**: explicit mode→visibility map aligned with Drupal's semantics (reconciled with the module's `modeToVisibility`; never rely on `inverseForFile` exact-match, which reads Drupal's 0664 as public).
- **Access control stays Drupal-side**: visibility is best-effort metadata (flysystem's own docs disclaim it); public serving relies on scheme routing + bucket policy/CDN, private on the `file_download` route.

## 7. Read-only schemes

Per `feature-evaluation-log.md` Item 8 — the preserved `writable` flag becomes behaviorally enforced (it was informational-only in 3.0):

- `writable = FALSE` wraps the adapter in `ReadOnlyFilesystemAdapter` (`league/flysystem-read-only`) at the filesystem factory — one seam covers every write path.
- The wrapper rejects write-mode `stream_open` up front (return FALSE), mirroring core's `ReadOnlyStream`.
- **`unlink()` returns TRUE** (core `ReadOnlyStream` precedent) so `file_delete()` can remove the `file_managed` DB reference without deleting the object — important for externally-managed files (e.g. third-party PDFs on S3).

## 8. GD + ImageMagick support

Both toolkits are supported through the wrapper contract — neither needs flysystem-specific staging:

- **GD** (`GDToolkit::save`, 11.4): keys its staging off `getWrappers(LOCAL)` — if the destination scheme lacks the LOCAL bit, it writes to `temporary://` and `file_system->move()`s to the destination. Correct `getType()` per §4.2 makes this work.
- **ImageMagick** (`imagemagick` 5.0.1): probes `file_system->realpath($uri)`; on FALSE it stages to `temporary://`, shells out to `magick` on the local path, and `move()`s the result back through the wrapper. Correct `realpath()` (FALSE for remote, never a bogus string) makes this work.
- Both publish via `file_system->move()` → the streamed, single-PUT write path (§4.4) and the stat-cache invalidation.

## 9. Mime handling

Per `feature-evaluation-log.md` Item 1: **Drupal owns the label** (`MimeTypeGuesser`, extension-only, remote-safe, zero I/O); the module passes Drupal's guessed mime to the adapter on write (`mimetype`/`ContentType` config) so stored S3 Content-Type equals Drupal's `filemime`. Adapter `FinfoMimeTypeDetector` is only the fallback for objects written outside Drupal. Never call `mimeType()` on SFTP casually (whole-file read).

## 10. Checksums

Per `feature-evaluation-log.md` Item 3: expose a per-scheme checksum/integrity API (`Filesystem::checksum` — S3 ETag via HeadObject, streaming MD5 elsewhere). Used by the migration submodule's post-move verification, the reconcile command, and drush transfer checks. **ETag caveat**: S3 ETag == file MD5 only for single-PUT non-SSE-KMS objects; cross-adapter verification uses streaming MD5 on both ends.

## 11. Adapter plugin contract

Per Q4 and the developer README requirement:

- **All adapters (including the two Core drivers and the three submodule adapters) are plugins** discovered via attribute + plugin manager (D11/D12-native). Contrib adapters are first-class.
- Each plugin **declares its whole contract in one place**: config keys (types, labels, defaults — replacing 3.0's scattered `?? default` fallbacks), which keys are secrets (Key-module `*_key_id` resolution, preserved), LOCAL/REMOTE type, visibility support. One declaration feeds the admin form, config schema (`flysystem.adapter_config.[%parent.driver]`), the adapter factory, and the connection test. **The entity holds zero driver knowledge**: the secret exactly-one-of validation derives its pairs from the selected plugin's `getConfigKeys()` `secret` markers, never from a Core constant (`adapter-submodules.md` §3).
- **The three submodules are the reference "contrib-style" plugins** — they prove the contract end-to-end via the same discovery → registration → scheme-mapping → runtime path a third-party contrib adapter uses (`adapter-submodules.md` §2.2).
- **Developer README (first-class deliverable)**: a step-by-step walkthrough for implementing an adapter plugin — config-key declaration, schema fragment, secret handling, type, connection test, required tests — using one shipped adapter as the annotated reference. Written so the discovery-mechanism choice doesn't leak into the contributor experience.

## 12. Drupal 12 constraints

- **PHP `>=8.4`; `core_version_requirement: ^11.4 || ^12`.** Develop against 11.4 today; test against both majors. (PHP floor corrected 2026-08-29 per `independent-plan-review.md` B/C4: a `^11.4` module must install on 8.4; the D12 leg raises to 8.5 — tracked as #72.)
- **Never use an API flagged for removal in 11.4+** (the core team's deprecation markers are authoritative). Specifically: use `FileExists` enum everywhere (`EXISTS_*` constants are removed in D12), never pass ints.
- `StreamWrapperInterface` is byte-identical in 11 and 12 (VERIFIED) — build against the current surface with confidence.
- **Never hard-reference `\Drupal\system\FileDownloadController`** (namespace move in-flight in 12); rely on interfaces/services.
- Keep hooks object-oriented (D12 confines legacy procedural hooks to the main extension file). PHPUnit 11 in tests.

## 13. Core contract-violation determinations

Per the design discussion (VERIFIED against core 11.4):

| Core call site | Determination |
|---|---|
| Status/admin sites (`SystemRequirements`, `SystemRequirementsHooks`, `FileSystemForm`, `ThemeSettingsForm` `PublicStream::basePath()`) | **Refuse to reproduce** — document that status shows the physical location; optional flysystem status-report checks |
| `HtaccessWriter` (`PrivateStream::basePath()`) | **Refuse** — remote private schemes rely on Drupal's access checks, not `.htaccess`; documented security implication (Apache/`.htaccess` and ported-rule Nginx sites warned) |
| `FileSystem.php:647` temp dir, `PhpStorageFactory:49` opcache | **Accept as-is** — temp/opcache stay local by design |
| `AssetsStream extends PublicStream` | **Accept, verified** — `assets://` sidesteps the shadow; chosen divergence |

## 14. Internal uses (not UI)

`listContents`/`DirectoryListing` stay internal: migration walking, reconcile, `deleteRecursive()`, `scanDirectory()` parity, wrapper `dir_opendir()`. **Never exposed to the Media Library** (entity-query-driven; a listing would be a second source of truth). Any future tree browsing gates S3 deep listings (paginated ListObjectsV2) behind explicit user intent.

## 15. Open items (deferred to implementation)

- Adapter discovery: **attribute + plugin manager** (resolved; see `plan-m1.md` §2 and `adapter-submodules.md`).
- Stat-cache TTL value and cache-bin choice.
- Connection-test UX details.
- Whether the connection-status entity fields gain fields (additive only).