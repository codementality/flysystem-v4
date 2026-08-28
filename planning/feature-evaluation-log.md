# Flysystem v4 — Feature Evaluation Log

Purpose: evaluate league/flysystem v3 capabilities that the Drupal 3.0 module did not leverage, decide their relevance for the v4 rewrite, and record each verdict. One entry per item evaluated.

Legend — Verdict: **INCORPORATE** (build in) · **PARTIAL** (incorporate with limits) · **DON'T INCORPORATE** (explicitly out of scope).

---

## Item 1 — Mime-type detection (2026-08-27)

- **Source**: https://flysystem.thephpleague.com/docs/advanced/mime-type-detection/ + installed `league/mime-type-detection` / adapters (v3.35.3).
- **Question**: Drupal has its own mime-type detection. Is flysystem's a better alternative for v4?
- **Findings** (VERIFIED from source):
  - Drupal 11.4's `MimeTypeGuesser` is **extension-only**: the only tagged `mime_type_guesser` is `ExtensionMimeTypeGuesser` (pure `basename()` + in-memory `MimeTypeMap`, zero filesystem I/O, no finfo). It is already remote-safe — `realpath() === FALSE` for remote wrappers is handled explicitly and the URI passes through to extension lookup. Only an unmapped extension degrades to `application/octet-stream`.
  - The flysystem detectors (`FinfoMimeTypeDetector`, `ExtensionMimeTypeDetector`, `FallbackMimeTypeDetector`) are used by the adapters at the **storage boundary**: both S3 adapters inject a default `FinfoMimeTypeDetector` and set the stored object `Content-Type` on write. For stream/resource bodies, finfo detection degrades to **extension-only** (`is_string` gate), and the adapter **never consults Drupal's guesser** — so stored S3 Content-Type can diverge from Drupal's `filemime`.
  - Explicit write-time override exists on both S3 drivers: AwsS3V3 honors a `mimetype` config shortcut; AsyncAws requires `ContentType` (no `mimetype` shortcut). Passing either disables adapter detection.
  - `Filesystem::mimeType()` on S3 returns **stored** metadata (HeadObject round-trip); on SFTP it reads the entire file to detect (expensive). Drupal's guesser is free and in-memory.
  - A registered-guesser seam (`mime_type_guesser` tag, first non-null wins) exists but costs a network call per guess if it prefers stored S3 metadata.
- **Verdict**: **PARTIAL** — flysystem's detection is *not* a replacement for Drupal's; it is the storage-boundary fallback.
- **Decision**:
  - **Drupal owns the label**: v4 never displaces Drupal's `MimeTypeGuesser` for `filemime`, upload validation, or download `Content-Type`.
  - **Drupal is the source of truth at the write boundary**: on every write to a scheme, v4 passes Drupal's guessed mime to the adapter explicitly (`mimetype` on AwsS3V3, `ContentType` on AsyncAws), so the stored S3 Content-Type equals Drupal's `filemime` by construction.
  - **Adapter `FinfoMimeTypeDetector` remains only the fallback** when no explicit type is available (e.g. objects written outside Drupal).
  - **Do not** call `Filesystem::mimeType()` on SFTP casually (whole-file read); not needed given the write-time sync policy.
  - Status: **INCORPORATED into v4 write path; explicitly NOT incorporated into Drupal's guess path.**

---

## Item 2 — Public URLs (2026-08-27)

- **Source**: https://flysystem.thephpleague.com/docs/usage/public-urls/ + installed `src/UrlGeneration/` (v3.35.3).
- **Question**: should flysystem's `publicUrl` machinery implement v4's URL policy (`public_url_base` / CDN base + relative path)?
- **Findings** (VERIFIED from source):
  - `PublicUrlGenerator` interface + three stock implementations: `PrefixPublicUrlGenerator` (prefix + path, single-slash join via `PathPrefixer`), `ShardedPrefixPublicUrlGenerator` (shard selection = `abs(crc32($path)) % count`), `ChainedPublicUrlGenerator` (insertion order, first success).
  - `Filesystem::publicUrl()` resolution order: injected generator → `public_url` config (string = prefix, array = sharded) → adapter implementing `PublicUrlGenerator` → throws. **The `public_url` config beats the adapter** — structurally identical to our `public_url_base` (CloudFront base wins over the bucket URL).
  - **Critical: none of the stock generators percent-encode path segments** (`PathPrefixer`: `prefix . ltrim(path)`, whitespace-trim only). Used as shipped, they would reintroduce the `#`/space/comma URL bug (#3616492).
  - `AwsS3V3Adapter::publicUrl()` → `S3Client::getObjectUrl` → virtual-hosted bucket URL; the **SDK does encode the key** (rawurlencode, `/` preserved). This is the "public bucket" URL our policy excluded as a default.
  - **No access-controlled/private-route concept exists in flysystem's URL machinery at all** — the private scheme case (Drupal `file_download` route) is wrapper-only by necessity.
  - Presigned (`temporaryUrl`) is a sibling interface (`TemporaryUrlGenerator`), adapter-level only, no config option.
- **Verdict**: **DON'T INCORPORATE** the stock machinery.
- **Decision**:
  - The wrapper's `getExternalUrl()` remains the single source of Drupal URLs per the locked policy: CDN base + **per-segment-encoded** relative path for public schemes, access-controlled route for private schemes, explicit presigned opt-in for `aws_s3`.
  - Do **not** route Drupal URL generation through flysystem's stock `publicUrl` generators (no encoding, no private-route handling).
  - The `public_url` config concept *confirms* the shape of `public_url_base` but the implementation stays wrapper-owned.
  - Noted for future (not now): `ShardedPrefixPublicUrlGenerator` as a possible CDN-sharding option; a custom injected `PublicUrlGenerator` (base + encoded segments) as an internal convenience.
  - Status: **NOT incorporated; evaluation confirmed the locked URL policy.**

---

## Item 3 — Checksums (2026-08-27)

- **Source**: https://flysystem.thephpleague.com/docs/usage/checksums/ + installed source (v3.35.3). Requested as an INCORPORATE; also flagged by requester as a candidate to backport to v3.
- **Findings** (VERIFIED from source):
  - `Filesystem::checksum()`: if the adapter implements `ChecksumProvider`, delegate; otherwise fall back to streaming MD5 (`CalculateChecksumFromStream`: `readStream` + `hash_update_stream`, `checksum_algo` config default `md5`). Streaming — no whole-file memory blowup on any adapter.
  - Adapters: **Local** implements `ChecksumProvider` (via `hash_file`, fast). **AwsS3V3** implements it with default `checksum_algo: 'etag'` — a single HeadObject round-trip returning the stored `ETag` (quotes trimmed); any non-`etag` algo throws `ChecksumAlgoIsNotSupported` and `Filesystem::checksum()` falls back to streaming MD5. **AsyncAws S3, SFTP, memory**: no `ChecksumProvider` → streaming MD5 (full object read).
  - **ETag caveat**: an S3 `ETag` equals the file's MD5 **only** for single-PUT, non-SSE-KMS objects. Multipart uploads produce a composite ETag (`md5(concat part-md5s)-N`); SSE-KMS/SSE-C ETags are not the MD5. So ETag is a cheap *change-detection* hint, **not** authoritative cross-system file integrity.
- **Verdict**: **INCORPORATE**.
- **Decision**:
  - Expose a checksum/integrity API on the flysystem service (per scheme) for contrib use (media integrity checks, dedup, change detection).
  - **Migration submodule**: use for post-move/post-copy verification (compensates the MountManager non-atomic copy-then-delete). Same-S3 or local↔local → cheap checksum; cross-adapter (local↔S3) or where ETag is unreliable (multipart / SSE-KMS) → **streaming MD5 on both ends**, or document the ETag caveat. Never compare a locally computed MD5 against an S3 ETag and assume equality.
  - **Reconcile command** (carried from #3610035): verify remote objects against expectations using the same API.
  - drush get/put transfer verification (2.x open feature request).
  - Backport to v3: noted as a candidate (byproduct of the rewrite, not a focus).
  - Status: **INCORPORATED (v4); backport candidate (v3).**

---

## Item 4 — Directory listings (2026-08-27)

- **Source**: https://flysystem.thephpleague.com/docs/usage/directory-listings/. Evaluated with a critical eye — concern that it may add no value and complicate Drupal's Media Library.
- **Findings** (VERIFIED from source):
  - `DirectoryListing` is a lazy iterable wrapper (`filter`/`map` via generators, `sortByPath`/`toArray` materialize, **read-once**, no `first()`). `Filesystem::listContents()` is lazy; adapter costs differ: Local = free in-memory walk; SFTP = one round trip **per directory**; **S3 = paginated ListObjectsV2 — a deep listing of a large bucket is many API round trips**.
  - **Drupal's Media Library is purely entity-query-driven**: it's a `media_library` View over `media_field_data`, `MediaLibraryState` is a `ParameterBag` value object, the widget persists **media entity IDs**, and selection goes through `EntityQuery` (`DefaultSelection::buildEntityQuery`). No filesystem directory listing exists anywhere in `media`/`media_library` core.
  - The only core directory walker is `FileSystem::doScanDirectory()` — used solely for module/theme/test discovery, local-only. **Core ships no user-facing file browser.**
  - flysystem-3.0-ref uses `listContents` only internally: reconcile (`FileReconciler:117`), `deleteRecursive()` (`FlysystemFileSystem:578`), `scanDirectory()` parity (`:971`), connection test (`ConnectionTester:61`), stream-wrapper `dir_opendir()` (`:890`), migration orphan-finder (`MigrationBatchForm:380`).
- **Verdict**: **DON'T INCORPORATE as a Drupal-facing/UI feature.** Internal-only.
- **Decision**:
  - `listContents`/`DirectoryListing` remain an **internal tool**: migration walking, reconcile, `deleteRecursive()`, `scanDirectory()` parity, and the wrapper's `dir_opendir()` — exactly where the ref used it.
  - **Never expose directory listings to the Media Library or any user-facing browser.** It is entity-query-driven; a listing would be a second source of truth with zero added capability (entities ≠ `StorageAttributes` paths; bridging always requires the reverse entity lookup).
  - If any admin/drush tree listing is ever built, gate S3 deep listings behind explicit user intent (page-sized/batch) — never materialize whole buckets.
  - Status: **NOT incorporated as UI; incorporated internally (migration / reconcile / delete / scan / `dir_opendir`).**

---

## Item 5 — Exception handling (2026-08-27)

- **Source**: https://flysystem.thephpleague.com/docs/usage/exception-handling/. Not a feature — a cross-cutting strategy: catch and handle flysystem exceptions elegantly, never present an end user with a stack dump.
- **Findings** (VERIFIED from source):
  - flysystem taxonomy: `FilesystemException` marker; `FilesystemOperationFailed` adds `operation()` (14 constants) and most expose `location()`/`reason()`/`source()`/`destination()`. **Two families (URL generation, checksum, mount resolution, path traversal) implement bare `FilesystemException` with no `operation()`** — dispatch must branch on class or marker, not `operation()` uniformly.
  - Messages are mostly actionable sentences; caveat: `UnableToMoveFile`/`UnableToListContents` **embed the previous low-level exception's message** (use accessors, not `getMessage()`).
  - **Drupal's hierarchy (correction to common names):** `FileException` base + `FileNotExistsException`, `FileExistsException`, `FileWriteException`, `DirectoryNotReadyException`, `NotRegularFileException`, `NotRegularDirectoryException`, `InvalidStreamWrapperException` — all message-only constructors. Core callers (`file.module` upload flow, `FileUploadResource`) **catch the exact subclasses to pick UI strings**, so a faithful mapping preserves them.
  - **Stream-wrapper contract**: `stream_*` methods must NOT throw — return `FALSE`/`null` + `trigger_error()` (gated on `STREAM_REPORT_ERRORS`) + watchdog (`LocalStream` demonstrates). Critical: `LocalStream` calls the `file_system` service inside the wrapper (`unlink`/`mkdir`/`rmdir`) — so the **decorated service and the wrapper must share the same strategy**; the wrapper is the last line of defense against the "Uncaught Exception" fatal.
- **Verdict**: **STRATEGY — incorporate as a mandatory design requirement.**
- **Decision** — three boundaries:
  1. **Stream wrapper**: never throw. Catch every flysystem exception inside `stream_*`, return the primitive contract value (`FALSE`/`null`/`''`), `trigger_error()` with an actionable message when `STREAM_REPORT_ERRORS` is set, and log via watchdog with `operation()` + `location()` + `reason()`.
  2. **Decorated `file_system`**: translate flysystem exceptions → the core `FileException` subclasses (mapping: `UnableToReadFile`→`FileNotExistsException`; `UnableToWriteFile`/`UnableToMoveFile`/`UnableToCopyFile`→`FileWriteException`; `UnableToCreateDirectory`→`DirectoryNotReadyException`; mount/scheme failures→`InvalidStreamWrapperException`; `UnableToCheckExistence` family→return bool; `FileExistsException` only when enforcing `FileExists::Error`). **Reuse the 8 core subclasses, never invent new ones**; pass the flysystem exception as `$previous`.
  3. **CLI/admin** (connection test, migration, reconcile): may throw, but present one clean line from `operation()`/`location()`/`reason()`; config/validation exceptions (`InvalidVisibilityProvided`, `InvalidStreamProvided`, `ChecksumAlgoIsNotSupported`) surface as **validation messages**, not I/O errors. No stack dumps.
  - Status: **INCORPORATED as a cross-cutting strategy** (feeds the architecture document's exception-handling section).

---

## Item 6 — Visibility (incl. Unix visibility) (2026-08-27)

- **Sources**: https://flysystem.thephpleague.com/docs/visibility/ and https://flysystem.thephpleague.com/docs/usage/unix-visibility/. Evaluated as *particularly relevant*; the evaluation supports that strongly — it is the bridge between Drupal's access model and the object store's.
- **Findings** (VERIFIED from source):
  - **Model mismatch**: Drupal's access model is **scheme-derived** — the `File` entity has **no per-file visibility attribute** (fields: filename, uri, filemime, filesize, status, created, changed); `public://` = webserver/object URL, `private://` = access-checked route. Flysystem's model is **per-object** — ACL on S3, chmod on local/SFTP, via a binary `public`/`private` abstraction.
  - **S3 writes ALWAYS send an ACL** (default `private` via `determineAcl()`), and stock 3.35.3 has **no way to suppress it**. On BucketOwnerEnforced / Block Public Access buckets (the AWS modern default), **any ACL value → `AccessControlListNotSupported` → every write/copy/createDirectory fails**. This is the root of the v3 bug cluster (#3616482, #3616487). Only a subclassed adapter (or flysystem's planned `use_acls` option, issue #1874) fixes it.
  - **`visibility()`/`setVisibility()` on S3 = GetObjectAcl/PutObjectAcl round trips that throw on ACL-disabled buckets.** `createDirectory()` uses `directory_visibility` defaulting to **PUBLIC** on S3 (root of #3616482). `retain_visibility` defaults true → **cross-filesystem copy reads source `visibility()` (GetObjectAcl)** — round trip + throws on ACL-disabled.
  - **Unix visibility** (`PortableVisibilityConverter`): maps public/private → 0644/0600 (files), 0755/0700 (dirs). `inverseForFile()` uses hard `===` and **falls back to PUBLIC** — so Drupal's 0664 reads as **public**, and local/SFTP `copy()` with retain=true **rewrites a 0664 file to 0644**. The docs explicitly disclaim: "checking visibility should NOT be used as an indication the file is public or private." Drupal's defaults are CHMOD_FILE=0664, CHMOD_DIRECTORY=0775.
  - **Custom converter injection exists** on both Local and SFTP adapters (constructor param); a Drupal-aware converter (0664/0775) can be injected per scheme. The ref's own `modeToVisibility()` disagrees with the converter on non-canonical modes (e.g. 0700 → converter: public, module: private).
  - **Writes without visibility work on Local/SFTP** (chmod skipped, umask governs); **impossible on S3** (ACL always sent).
  - Drupal's `FileSystem::chmod()` calls PHP `chmod()` on the URI → routes to the wrapper's `stream_metadata()` (`STREAM_META_ACCESS`) — a remote wrapper must implement it, receiving an **int mode**, not `'public'`/`'private'`.
- **Verdict**: **INCORPORATE** — load-bearing, not optional.
- **Decision**:
  1. **Scheme-derived visibility is the source of truth**: build each scheme's `Filesystem` with default config `visibility` = scheme-derived (`public://`→`public`, `private://`→`private`), **`directory_visibility` = `private`** (fixes #3616482), `retain_visibility` = true.
  2. **Per-scheme `use_acl` flag, driver-scoped config key, default `FALSE`** (confirmed — no explicit choice defaults to FALSE): when off, use a **subclassed S3 adapter** that omits the ACL on upload/copy/createDirectory, overrides `visibility()` to return the scheme default (no GetObjectAcl) and `setVisibility()` to no-op. This is the **only** way to work on modern BucketOwnerEnforced buckets. When on (legacy ACL-enabled buckets), stock behavior with explicit ACLs. (`use_acl` is an implementation seam; upstream's future `use_acls` option should supersede the subclass if it lands.)
     - Declared by the `s3`/`aws_s3` adapter plugins only; lives in the `config` sub-array of both the settings.php array and the config entity — purely additive, no 3.0 config needs changing to upgrade.
     - **Documentation obligation**: `use_acl` (and its FALSE default) must be **explicitly called out** in the scheme-config documentation and the upgrade guide.
     - **Form obligation**: the admin form field must **expressly describe** the setting and its default in the field description (not just the label).
  3. **Never call `visibility()` inside `url_stat`** (cost + ACL-disabled failure) — reaffirmed.
  4. **copy/move**: pass `retain_visibility = false` or explicit visibility to avoid the GetObjectAcl round trip; document the local/SFTP 0664→0644 normalization; set explicit destination visibility (scheme-derived) on cross-adapter moves.
  5. **`stream_metadata`/`chmod`**: implement on the wrapper with an **explicit mode→visibility map aligned with Drupal's semantics** (reconciled with `modeToVisibility`; never rely on `inverseForFile` exact-match). On S3, dispatch `setVisibility` only when `use_acl` is true, else no-op + log.
  6. **Unix visibility sub-feature**: keep the binary abstraction, but do **not** impose flysystem's canonical bits over Drupal's semantics on local/SFTP — either skip visibility on write (Drupal's chmod/umask governs) or inject a Drupal-aware converter per scheme.
  7. **Access control stays Drupal-side**: visibility is best-effort metadata (per the docs' own disclaimer), never the access-control mechanism; public serving relies on scheme routing + bucket policy / CDN, private on the `file_download` route.
  - Status: **INCORPORATED as a load-bearing strategy.**

---

## Item 7 — In-memory adapter (2026-08-27)

- **Source**: https://flysystem.thephpleague.com/docs/adapter/in-memory/. Proposed primarily to make testing easier.
- **Findings** (VERIFIED from source):
  - `InMemoryFilesystemAdapter implements FilesystemAdapter` — a **complete** implementation, no unsupported stubs: fileExists, read/readStream, write/writeStream, delete (no-op for missing), copy/move, listContents (deep), fileSize/mimeType/lastModified, visibility/setVisibility, createDirectory/deleteDirectory. Not a `ChecksumProvider`, but `Filesystem::checksum()` falls back to stream-based MD5 so it works.
  - `readStream()` returns a rewindable, **seekable `php://temp`** stream — good for stream-wrapper tests (the seekability contract). `writeStream()` pulls the whole stream via `stream_get_contents` — **not real streaming** (do not assert large-file streaming against it).
  - Visibility is a **symbolic per-file string, unvalidated** (neither chmod nor ACL). Directories are **virtual** — they exist only while files sit under them (`directoryExists` requires ≥1 file); don't assert directory persistence independent of contents.
  - Data is in-memory only, lost at process end; constructor takes a default visibility (`PUBLIC`).
  - **Already present**: `league/flysystem-memory ^3.0` in composer require-dev (installed 3.31.0). flysystem-3.0-ref uses it **extensively** in its Kernel + Unit + StreamWrapper test suites, via a test-fixture driver plugin (`tests/modules/flysystem_test_adapter/.../TestMemoryAdapterDriver.php`) that returns `new InMemoryFilesystemAdapter()`, plus anonymous subclasses that override `visibility()` to throw (mimicking the S3 ACL-disabled case).
- **Verdict**: **INCORPORATE — as a test-support adapter, not a production adapter.**
- **Decision**:
  - Ship an **"inMemory" adapter driver plugin as a test-support fixture**: a test-only driver in a dedicated fixture module so kernel tests can configure a full scheme backed by a real adapter — exercising the wrapper, decorated manager, and registration/resolution path end-to-end against real adapter code, without mocks, network, or disk. Built fresh for v4 (no code or naming carried from v3 — see plan-m1.md §1a).
  - **NOT part of the 4-adapter production support boundary.** It is test-only: data is non-persistent, and it must not appear as an operator-selectable production adapter. Declare it **REMOTE-type** so tests exercise the high-risk remote code paths (`realpath()` FALSE, seekable buffering, staging triggers).
  - Complements the Floci integration layer: in-memory for the fast contract layer, Floci-emulated S3 for the real S3-adapter behaviors.
  - Status: **INCORPORATED (test-support only).**

---

## Item 8 — Read-only adapter (2026-08-27)

- **Source**: https://flysystem.thephpleague.com/docs/adapter/read-only/. Use case: files generated/managed outside Drupal on a remote object store (e.g. third-party PDFs); Drupal only displays/transmits them; the scheme must reject all writes.
- **Findings** (VERIFIED from source):
  - The read-only mechanism is `League\Flysystem\ReadOnly\ReadOnlyFilesystemAdapter` (package `league/flysystem-read-only`, **not currently installed**). It extends `DecoratedAdapter`, implements `FilesystemAdapter` + `PublicUrlGenerator` + `ChecksumProvider` + `TemporaryUrlGenerator`; blocks write/writeStream/delete/deleteDirectory/createDirectory/setVisibility/move/copy (each throwing the matching `UnableTo*File` exception with "…this is a readonly adapter."); allows all reads, metadata, checksum, and URL generation.
  - **The preserved `writable` flag in 3.0 is informational only — never enforced**: `FilesystemFactory::buildFilesystem()` ignores it, `FlysystemFileSystem` methods carry no `writable` guard, and the wrapper accepts write-mode `stream_open`. The flag exists and shows in the UI but has zero behavioral effect — a genuine bad habit.
  - Core precedent: `ReadOnlyStream`/`LocalReadOnlyStream` reject non-read modes in `stream_open()`; notably **`unlink()` returns TRUE** (comment: "so that file_delete() will remove db reference to file. File is not actually deleted") — `ModuleStream`/`ThemeStream` rely on this.
  - The ref's `FlysystemFileSystem` already maps the `UnableTo*File` family to Drupal `FileException` — engine exceptions surface correctly once enforced.
- **Verdict**: **INCORPORATE**.
- **Decision**:
  - Add `league/flysystem-read-only` to composer (runtime dependency).
  - **Engine-level enforcement** at the filesystem factory: when a scheme's `writable` is FALSE, wrap the adapter in `ReadOnlyFilesystemAdapter` before constructing the `Filesystem` — one seam covers every write path (saveData/copy/move/delete/uploads) through the factory.
  - **Wrapper**: reject write-mode `stream_open` up front (return FALSE), mirroring core's `ReadOnlyStream`; convert the engine's `UnableTo*` exceptions per the exception-handling strategy.
  - **`unlink()` semantics** follow core's `ReadOnlyStream` precedent: return TRUE so `file_delete()` can remove the `file_managed` DB reference while the object is not deleted — important for the externally-managed-files use case.
  - `writable` becomes behaviorally enforced (closing the 3.0 informational-only gap); existing 3.0 configs that set `writable: false` gain real enforcement on upgrade (documented).
  - Status: **INCORPORATED.**

---

## Item 9 — Path prefixing + URL masking (2026-08-27) — RESOLVED

- **Source**: https://flysystem.thephpleague.com/docs/adapter/path-prefixing/. Evaluated against a potential use case: reviving the 2.2-era "URL masking" feature (remote files streamed through a Drupal URL hiding the real origin).
- **What path prefixing is** (VERIFIED from source) — two mechanisms share the name:
  1. The documented feature = a **decorator** `PathPrefixedAdapter` (separate package `league/flysystem-path-prefixing`, not installed) that wraps any adapter.
  2. The mechanism the module actually uses = the built-in **`PathPrefixer`** embedded in each adapter, fed by constructor params: S3 `prefix` (default `''`, exposed by both S3 drivers in the ref), Local `location`/SFTP `root` (the root *is* the prefixer).
  - **Semantics**: the prefix is a **virtual root**. The caller addresses `a.jpg`; the adapter operates on `prefix/a.jpg`. Drupal URIs always carry the **unprefixed** path; the prefix is applied internally and transparently. `listContents()` returns **stripped** paths.
  - **Critical consequence — URLs**: on S3 the prefix is part of the object key, so object-store URLs **must include it** (the adapter's own `publicUrl()` does). The 3.0-ref wrapper builds direct URLs from the **unprefixed** target + `public_url_base` → **with a prefix configured and a bare-bucket base URL, public direct URLs 404**. v4 must fix this in `getExternalUrl()`.
  - Operator semantics: enabling a prefix on a bucket with existing unprefixed objects makes them invisible; disabling one orphans prefixed objects → **"set before filling the bucket," not a migration tool**. Path traversal is guarded by `WhitespacePathNormalizer` before prefixing.
- **The masking investigation** (VERIFIED): the remembered masking was NOT `sites/default/files/[scheme]/...`. The `sites/default/files` shape was **local-adapter-only** (a local root inside the public dir, served from disk). Actual 2.x S3 masking = the base module's `/_flysystem/{scheme}/{filepath}` route streaming through core `FileDownloadController` + `hook_file_download` — and that route had **no access check** (`_access: TRUE`; `hook_file_download` only set Content-Type/Length). flysystem_s3 (separate project, now unmaintained — maintainer inactive since 2024) was just the S3 driver plugin; its only URL modes were the base `/_flysystem/...` route (default) or direct bucket URLs (`'public' => TRUE`).
- **Verdict**:
  - **URL masking (public): DON'T INCORPORATE.** It was a public transparent proxy (security-by-obscurity, no access checks), the anti-CDN (every request through Drupal), and the source of the 2.2 pain cluster (image styles, Range/206, nginx, stale caching, interop). The **legitimate** access-controlled, origin-masked serving is already provided by v4's private streaming route.
  - **Path prefixing: PARTIAL.** Keep the S3 `prefix` config knob (already present, default `''`); **fix `getExternalUrl()` to include the prefix**; document the "set before filling the bucket" semantics.
- **Decision**:
  - No masked-public-URL feature in v4. Harden the private streaming route instead (Range/206 support, correct headers, cache metadata).
  - Origin-masking for genuinely public content is documented as a CDN-origin / reverse-proxy concern (out of module scope).
  - The S3 `prefix` knob stays with the URL-includes-prefix correctness fix.
  - Status: **DON'T INCORPORATE (masking); PARTIAL (prefix knob + URL fix).**