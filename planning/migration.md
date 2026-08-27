# Flysystem v4 — Migration Submodule

Status: **Draft**. Companion: `architecture.md`, `config-and-upgrade.md`, `feature-evaluation-log.md`.

## 1. Purpose & scope

An **optional, opt-in submodule** (`flysystem_migrate`-style) that moves files between configured schemes/adapters (e.g. local `public://` → S3). It is NOT required for the 3.0→4.0 upgrade (config carries over, files stay in place); it serves operators **switching storage backends**.

**Engine**: `League\Flysystem\MountManager` (verified viable, v3.35.3). The submodule is the orchestration layer on top.

## 2. What MountManager provides (verified)

- A `FilesystemOperator` that routes on `scheme://` prefixes — Drupal URIs already satisfy its format.
- Cross-mount `copy()`/`move()` **stream** (`readStream` → `writeStream`, never whole-file in memory); visibility retained by default; same-instance ops use adapter-native operations (S3 server-side CopyObject).
- Clean exception taxonomy (`FilesystemOperationFailed::operation()`).
- `checksum()` for post-move verification.

## 3. What the submodule must add (MountManager is transport, not a migration tool)

1. **Mount wiring** — build a `MountManager` keyed by Drupal scheme (or an alias map) from the module's configured adapters; build fresh per command run.
2. **Directory walk** — v3 has **no recursive copy**: iterate `listContents('scheme://', LIST_DEEP)`, filter `StorageAttributes` for files (`isFile()`), process per file.
3. **Progress** — byte-based progress from `fileSize`, plus per-file counts (for the drush command and any batch UI).
4. **Conflict policy** — MountManager overwrites blindly. Implement skip-if-exists / overwrite / version (copy-then-rename) semantics driven by `fileExists` + `lastModified`.
5. **Post-move verification** — cross-mount move is **copy-then-delete, non-atomic**: a failure between leaves the file on both systems. Verify destination before deleting source. Use the checksum API (`feature-evaluation-log.md` Item 3): same-S3 or local↔local → cheap checksum; **cross-adapter or unreliable-ETag cases → streaming MD5 on both ends** (S3 ETag == file MD5 only for single-PUT, non-SSE-KMS objects — never assume equality).
6. **Drush integration** — a command iterating the walk, throttling/batching, mapping `FilesystemOperationFailed::operation()` + `reason()` to clean messages (no stack dumps — see exception strategy).
7. **URI mapping decision** — Drupal URIs (`scheme://path`) stay scheme-prefixed; if only the *adapter* behind a scheme changes, **no URI rewrite is needed** (the migration moves objects within/between adapters while URIs stay identical). A full scheme-to-scheme rewrite would cascade into `file_managed` and entity field tables — out of scope unless explicitly requested.
8. **Empty directories** — v3 has no `copyDirectory`; empty dirs never migrate unless explicitly `createDirectory`-ed (S3 dirs are 0-byte keys; local dirs implicit). Document.

## 4. Rules & guardrails

- **Cannot migrate into a read-only scheme** (target scheme `writable = FALSE` → reject early with a clear message).
- **Read-only source schemes are fine** (reading is allowed).
- Respect the per-scheme `visibility`/`use_acl` settings for the destination writes (`feature-evaluation-log.md` Item 6).
- Large files stream through MountManager; note that the S3 write path delegates to the SDK's uploader (multipart/seek behavior is SDK-side — verify with the largest target objects).
- Two schemes sharing one adapter still stream (MountManager's fast path is object-identity only) — documented.
- Cross-request restart/resume: batch-friendly, resumable where feasible (the 3.0 `flysystem_migrate` used UI + queue + cron; the submodule should support a queue/batch path, not just a blocking drush command).

## 5. Relationship to the reconcile command

The 3.0 `flysystem:reconcile` drush command (#3610035) creates File/Media entities from unmanaged files on a remote filesystem. That is a **different concern** from migration (entity reconciliation vs file movement). v4 carries reconcile forward as its own capability; the migration submodule moves files; the two compose (reconcile before/after a migration to update the `file_managed` table for moved files, if URIs change).

## 6. Testing

- Contract layer: migration walk, conflict policy, verification logic against the **in-memory adapter fixture** (`testing.md` §2).
- Integration layer: real S3 → S3 and local → S3 migrations against **Floci**.
- Non-atomicity: a simulated failure mid-move must not lose data (verification-before-delete proven by test).
- Checksum verification: ETag path (same-S3) and streaming-MD5 path (cross-adapter) both tested.