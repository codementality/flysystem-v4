# Lessons Learned

## Session: Flysystem v4 design (2026-08-27)

### [DRUPAL_11_STREAM_WRAPPER_OVERRIDE_SPLIT] — 2026-08-27

- **Problem**: A module tagging its own service with `scheme: public` does NOT fully override core's `public://` wrapper. `StreamWrapperClassesPass` (the `$wrapperClasses` array used by `getClass()`/`isValidScheme()`/`register()`) is **last-wins**, but Symfony's `ServiceLocatorTagPass` (the scheme-keyed locator used by `getViaUri()`/`getViaScheme()`) is **first-wins** — `PriorityTaggedServiceTrait::findAndSortTaggedServices` does `if (isset($indexes[$index])) continue;`. Core's `stream_wrapper.public` is registered first, so the module's service is dropped from the locator entirely.
- **Root cause**: Two resolution mechanisms with opposite collision semantics; the PHP-level wrapper is overridable, the Drupal-service-level resolution is not.
- **Failure type**: `KNOWLEDGE_GAP`
- **Solution**: Decorate the `stream_wrapper_manager` service with a subclass that returns the flysystem wrapper for owned schemes and delegates otherwise — the single seam that makes remapped core schemes resolve correctly.
- **Category**: drupal-api
- **Applies to**: the flysystem v4 implementation session; future sessions touching stream wrapper overrides
- **Suggested improvement**: encode in the architecture doc (done: `planning/architecture.md` §3.2); verify in a real container build at implementation time.

### [D11_STREAM_WRAPPER_REGISTRATION_IS_TAGGED_SERVICES] — 2026-08-27

- **Problem**: `hook_stream_wrappers()` is DEAD in Drupal 11 (D8/9-era). Grep found only 2 docblock mentions in all of `web/`.
- **Root cause**: Core moved to tagged DI services (`stream_wrapper` tag + `scheme` attribute) collected by `StreamWrapperClassesPass` at container compile.
- **Failure type**: `STALE_KNOWLEDGE`
- **Solution**: Register wrappers as tagged services; core's `StreamWrapperManager::register()` handles PHP-level registration from the collected class array.
- **Category**: drupal-api
- **Applies to**: any session implementing stream wrappers on D10/D11/D12
- **Suggested improvement**: flysystem-3.0-ref's docs/code reference `RegisterStreamWrappersPass`/`addStreamWrapper()` which do NOT exist — do not port that architecture.

### [D12_FILEEXISTS_ENUM_REQUIRED] — 2026-08-27

- **Problem**: `FileSystemInterface::EXISTS_*` constants are removed in Drupal 12; `copy()`/`move()`/`saveData()`/`getDestinationFilename()` take a strictly-typed `FileExists` enum in 12 (the `FileExists|int` union is gone — passing an int fatals).
- **Root cause**: Core deprecation cycle; 12 removed the legacy int path.
- **Failure type**: `STALE_KNOWLEDGE`
- **Solution**: Always use `FileExists::Replace/Rename/Error`; never pass ints — even on D11 (both accept the enum).
- **Category**: drupal-api
- **Applies to**: D12-ready module work (flysystem v4)
- **Suggested improvement**: module targets `^11.4 || ^12`; test matrix covers both majors.

### [FLYSYSTEM_S3_ACLS_ALWAYS_SENT] — 2026-08-27

- **Problem**: league/flysystem 3.35 S3 adapters (AWS SDK + AsyncAws) ALWAYS send an `x-amz-acl` header on write/copy/createDirectory (default `private`); there is NO stock config to suppress it. On modern BucketOwnerEnforced / Block Public Access buckets any ACL value → `AccessControlListNotSupported` → every write fails.
- **Root cause**: Adapter design predates AWS disabling ACLs by default (2023); `visibility()`/`setVisibility()` on S3 are GetObjectAcl/PutObjectAcl round trips that throw on ACL-disabled buckets.
- **Failure type**: `ENVIRONMENT_QUIRK` (upstream library behavior)
- **Solution**: Per-scheme `use_acl` flag (default FALSE) → subclassed S3 adapters that omit ACLs, return the scheme default from `visibility()`, and no-op `setVisibility()`.
- **Category**: other (league/flysystem)
- **Applies to**: flysystem v4 implementation; any module wrapping S3 via league/flysystem
- **Suggested improvement**: also `directory_visibility` defaults to PUBLIC on S3 (fix #3616482) — force it to private.

### [PHP_STREAM_WRAPPERS_MUST_NOT_THROW] — 2026-08-27

- **Problem**: A PHP stream wrapper's `stream_*` methods must NOT throw — an exception inside becomes a fatal "Uncaught Exception". They return primitives (`FALSE`/`null`/`''`) and PHP emits its own warnings.
- **Root cause**: PHP stream-wrapper contract.
- **Failure type**: `KNOWLEDGE_GAP`
- **Solution**: Catch every flysystem exception inside `stream_*`; return the primitive contract value; `trigger_error()` when `STREAM_REPORT_ERRORS` is set; watchdog-log with `operation()`/`location()`/`reason()`. The wrapper is the last line of defense (core's `LocalStream` calls the `file_system` service from inside the wrapper).
- **Category**: php
- **Applies to**: flysystem v4 wrapper implementation
- **Suggested improvement**: encode in exception-strategy section (done: `architecture.md` §5).