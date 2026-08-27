# Drupal Flysystem — Issue Queue Review (for the flysystem v4 rewrite)

Purpose: reconcile every relevant filed issue against the 4.0 design.

Triage rules used in this document:
- **Section A — 3.0.x issues closed in the last 6 months** (Feb 27 – Aug 27, 2026): **regression-prevention** items — every behavior 4.0 must not reintroduce.
- **Section B — 2.2/2.3 issues**: triaged by whether they are **resolved by dropping league/flysystem v1** (`[v1]`) or are **Drupal-side, still relevant** (`[relevant]`), plus `[unknown]` where the root cause could not be determined from the record and `[tooling]` for non-behavioral items.

Status note (VERIFIED): as of 2026-08-27 the latest 3.0.x release is **3.0.0-beta3 (2026-08-20)**. No 3.0.0 stable, no RC, no 3.1.x exist yet. Release cycle: alpha1 (Jun 20) → beta1 (Jul 11) → beta2 (Jul 26) → beta3 (Aug 20).

---

# Section A — 3.0.x issues (regression-prevention)

## 3.0.0-beta3 — 2026-08-20 (all seven issues)

- [#3616485](https://www.drupal.org/project/flysystem/issues/3616485) — FlysystemStreamWrapper's static factory is never primed (nothing calls FlysystemStreamWrapperManager::register()). *Fixed.* PHP instantiates stream wrappers internally, bypassing DI; the factory was never primed, so native calls (`move_uploaded_file()`, `is_dir()`, `fopen()`) got a factory-less wrapper and uploads silently failed. **4.0 must not**: rely on container wiring for native wrapper calls — the wrapper must self-bootstrap from the URI.
- [#3616482](https://www.drupal.org/project/flysystem/issues/3616482) — Creating directories fails on S3 buckets with ACLs disabled (FlysystemFileSystem forces a public ACL). *Fixed.* **4.0 must not**: force a public ACL on mkdir; must work on ACL-disabled buckets (Object Ownership enforced / Block Public Access).
- [#3616488](https://www.drupal.org/project/flysystem/issues/3616488) — Image style routes get a `//styles/...` path when the public scheme's directory path is empty. *Fixed.* Route built as `'/' . '' . '/styles/...'` → `//styles/...`, parsed protocol-relative, derivatives 404. **4.0 must not**: emit double-slash / protocol-relative paths from route building.
- [#3616487](https://www.drupal.org/project/flysystem/issues/3616487) — url_stat() fails on S3 buckets with ACLs disabled because it calls visibility(). *Fixed.* A `visibility()` round trip in `url_stat()` errored on ACL-disabled buckets, making existing files appear missing. **4.0 must not**: let stat depend on a visibility/ACL call.
- [#3616492](https://www.drupal.org/project/flysystem/issues/3616492) — getExternalUrl() does not encode path segments (`#`, spaces, commas). *Fixed.* Raw target concatenated into public URL; `#` truncates the request. **4.0 must not**: emit unencoded URL path segments.
- [#3616493](https://www.drupal.org/project/flysystem/issues/3616493) — Image toolkit fails on S3 because read streams are not seekable (getimagesize() cannot fseek()). *Fixed.* S3 GetObject bodies are non-seekable HTTP streams but the wrapper advertised seekability; fix buffered into `php://temp`. **4.0 must not**: advertise seekable without actually providing it.
- [#3618271](https://www.drupal.org/project/flysystem/issues/3618271) — Overriding private:// with a remote adapter 404s: getExternalUrl() points at an unregistered route. *Fixed.* **4.0 must not**: generate external URLs for private schemes that resolve to an unregistered route.

## 3.0.0-beta2 — 2026-07-26

- [#3611227](https://www.drupal.org/project/flysystem/issues/3611227) — Error when assets:// stream wrapper is overridden with a Flysystem scheme. *Fixed.* Wrapper lacks `getDirectoryPath()` (a `LocalStream` method, not on the interface), required by core `AssetRoutes.php`. **4.0 must not**: ship a wrapper that fatals on the `assets://` override path.
- [#3610969](https://www.drupal.org/project/flysystem/issues/3610969) — Issue with Redirect Module. *Fixed.* With the Redirect module, the route normalizer 301-redirects image-style derivative routes; fix set `_disable_route_normalizer = TRUE`. **4.0 must not**: ship routes vulnerable to the normalizer.
- [#3600648](https://www.drupal.org/project/flysystem/issues/3600648) — File migration with MountManager (submodule). *Fixed (feature).* Scheme→scheme migration submodule (UI + queue + cron). The 4.0 migration submodule builds on this.

## 3.0.0-beta1 — 2026-07-11

- [#3610019](https://www.drupal.org/project/flysystem/issues/3610019) — Address PHPStan issues from the pipeline. *Fixed.* `[tooling]`
- [#3610020](https://www.drupal.org/project/flysystem/issues/3610020) — Address Coding Standards issues from pipeline. *Fixed.* `[tooling]`
- [#3610033](https://www.drupal.org/project/flysystem/issues/3610033) — Create a Plugin system for adding new Adapters with contrib modules. *Fixed (feature).* The adapter plugin system — 4.0 keeps this architecture, hardened per the design.
- [#3610035](https://www.drupal.org/project/flysystem/issues/3610035) — Create a drush command that creates File and Media entities from unmanaged files on a remote filesystem (`flysystem:reconcile`). *Fixed (feature).* Reconciliation capability — 4.0 decides how to carry this forward.

## Other 3.x issues closed in the window

- [#3600726](https://www.drupal.org/project/flysystem/issues/3600726) — Fatal error on installation. *Closed (fixed).* `getDirectoryPath() on false` in `PathProcessorImageStyles->processInbound()` on module install. Same `getDirectoryPath()` theme as #3611227.
- [#3378738](https://www.drupal.org/project/flysystem/issues/3378738) — Planning for Release 3.0.0, Drupal 10.3+ Compatibility, Flysystem v3.1 Compatibility. *Closed (outdated).* Roadmap issue, superseded by the 3.0 rewrite.

## Open 3.x issues (regression-relevant — not yet fixed)

- [#3618526](https://www.drupal.org/project/flysystem/issues/3618526) — Private-visibility url_stat() mode (0600) breaks is_readable() — every private download 500s "File must be readable". *Needs review (open), filed 2026-08-21.* Synthetic 0600 mode + uid/gid 0 → readability heuristic fails. **4.0 must get the private-file stat mode right.**
- [#3618567](https://www.drupal.org/project/flysystem/issues/3618567) — Config based scheme is broken and no longer functions. *Needs work (open).* Config-entity scheme definitions broke during refactor; dual source of truth (settings.php vs config entities) incoherent. **4.0's single-source-of-truth design must resolve this.**
- [#3618527](https://www.drupal.org/project/flysystem/issues/3618527) — aws_s3 driver: support S3-compatible endpoint override (MinIO/LocalStack). *Needs review (open).* **Directly required by the 4.0 Floci test bar.**
- [#3616491](https://www.drupal.org/project/flysystem/issues/3616491) — getExternalUrl() returns protocol-relative URL for image styles when public dir path empty. *Open.* `getPublicDirectoryPath()` returns `''` → `//styles/...`. **4.0's URL policy must define empty-directory-path handling.**

---

# Section B — 2.2/2.3 issues (last v1-based series)

Triage legend: `[v1]` = resolved by dropping league/flysystem v1 / its legacy adapters · `[relevant]` = Drupal-side, still relevant to 4.0 · `[unknown]` = root cause not determinable from the record · `[tooling]` = non-behavioral.

## 2.2.0 / 2.3.0 final — 2025-08-25

- [#3513799](https://www.drupal.org/project/flysystem/issues/3513799) — Regression: Image style generation no longer works for non-local drivers. *Fixed in 2.2.0-rc1 / 2.3.0-rc1.* `[relevant]` Remote wrappers couldn't create image derivatives — Drupal-side derivative logic.

## 2.3.0-alpha1 / alpha2 and 2.2.0-beta1 — Jan 2025

- [#2661588](https://www.drupal.org/project/flysystem/issues/2661588) — Support delivering local image styles until remote upload is complete. `[relevant]` Image-delivery behavior on remote adapters.
- [#2691731](https://www.drupal.org/project/flysystem/issues/2691731) — Provide migrations of existing field schemes. `[relevant]` Scheme migration.
- [#3109940](https://www.drupal.org/project/flysystem/issues/3109940) — Requirements check fails on install when dependencies present. `[relevant]` Install-time.
- [#3311075](https://www.drupal.org/project/flysystem/issues/3311075) — Rendering content too early PHP exception. `[relevant]`
- [#3457193](https://www.drupal.org/project/flysystem/issues/3457193) — Drupal 10.3.x: ImageStyleDownloadController::deliver requires "$required_derivative_scheme". `[relevant]`
- [#3486923](https://www.drupal.org/project/flysystem/issues/3486923) — Drupal 11 compatibility for 2.3.x. `[relevant]`
- [#3494101](https://www.drupal.org/project/flysystem/issues/3494101) — Establish automated test coverage for Flysystem. `[tooling]`
- [#3496496](https://www.drupal.org/project/flysystem/issues/3496496) / [#3496505](https://www.drupal.org/project/flysystem/issues/3496505) — Fix failing tests / coding standards. `[tooling]`
- [#3497516](https://www.drupal.org/project/flysystem/issues/3497516) — Remove Flysystem CollectionOptimizer classes (assets:// now in core). `[relevant]` Asset handling.
- [#3497952](https://www.drupal.org/project/flysystem/issues/3497952) — composer.json metadata. `[tooling]`
- [#3498150](https://www.drupal.org/project/flysystem/issues/3498150) — Error with namespacing in use statement, Stat plugin. `[unknown]`
- [#3498194](https://www.drupal.org/project/flysystem/issues/3498194) / [#3498720](https://www.drupal.org/project/flysystem/issues/3498720) — Route requirement boolean values must be strings. `[relevant]` Route config.
- [#3498983](https://www.drupal.org/project/flysystem/issues/3498983) — Remove deprecated listener from phpunit.xml.dist. `[tooling]`

## 2.3.0-alpha2 / 2.2.0-beta2 — Jan 2025

- [#3415603](https://www.drupal.org/project/flysystem/issues/3415603) — CssCollectionOptimizerLazy / JsCollectionOptimizerLazy use removed inherited member state. `[relevant]` Superseded by core `assets://` in the rewrite.
- [#3502794](https://www.drupal.org/project/flysystem/issues/3502794) — Class "Codementality\FlysystemStreamWrapper" not found. `[v1]` Caused by the twistor→codementality library fork swap (the abandoned twistor lib). Resolved by dropping v1.

## 2.2.1 / 2.3.1 — 2026-07-03 (in the 6-month window)

- [#3540678](https://www.drupal.org/project/flysystem/issues/3540678) — FlysystemBridge missing getDirectoryPath() method required by Drupal's FileSystem::tempnam(). *Closed (fixed).* `[relevant]` Drupal-side wrapper/interface gap — fatal when generating temp files for remote streams. **The recurring `getDirectoryPath()` theme (also #3611227 / #3600726 in 3.0).**
- [#3608245](https://www.drupal.org/project/flysystem/issues/3608245) — Update composer.json to reflect new external library tag. `[tooling]`
- [#3379832](https://www.drupal.org/project/flysystem/issues/3379832) — FlysystemServiceProvider::swapDumper Needs to Support file_additional_public_schemes. *Fixed in 2.2.1.* `[relevant]` The CSS/JS dumper-swap only handled `public://`, not `file_additional_public_schemes`.
- [#3525203](https://www.drupal.org/project/flysystem/issues/3525203) — Flysystem creates an additional add content action link. *Fixed in 2.3.1.* `[relevant]` Duplicate UI link.

## 2.2.2 — 2026-07-26 (in the 6-month window)

- [#3504144](https://www.drupal.org/project/flysystem/issues/3504144) — serve_js/css BC layer in Drupal 10 is broken in 2.2.0-beta2. *Fixed in 2.2.2.* `[relevant]` Legacy asset BC layer; the rewrite drops these optimizer classes in favor of core `assets://`.

## Open 2.x issues

- Recommended version 2.3.0-rc1 not compatible with core 10.5. *Active (2.2.0-rc1).* `[unknown]`
- Dependencies missing: stream wrapper. *Active (2.3.0-alpha1).* `[v1]` Install-time dependency check for the codementality fork class — likely resolved by the rewrite.
- [PP-1] Support replacing Drupal Core's assets:// stream wrapper with a Flysystem implementation. *Postponed (2.3.x-dev).* `[relevant]` 3.0 implements this (see #3611227).
- Support delivering aggregated assets (JavaScript & CSS) until remote upload is complete. *Patch (2.2.x-dev).* `[relevant]`
- Documentation needs updating and could be clearer. *Postponed.* `[tooling]`
- Trying to use FlySystem (remote media via SFTP) with IMCE. *Needs review (2.3.x-dev).* `[unknown]`
- getExternalUrl prefixes language to file URL when multilingual. *Needs work (2.3.x-dev).* `[relevant]` URL building — must carry into 4.0's hardened URL path.
- Add test coverage for FieldMigration. *Active.* `[tooling]`
- Add drush commands for getting and putting files. *Active.* `[relevant]` 3.0 addresses via #3610035 (reconcile).
- Altering response of setVisibility method (for SFTP adapter). *Needs work (2.3.x-dev).* `[unknown]` Visibility model changed in v3 — underlying need may or may not persist.
- .gif Images only upload first frame when using S3. *Active (2.3.x-dev).* `[unknown]` Likely v1 S3-adapter coupled; verify against the new S3 adapters.

---

# Cross-cutting synthesis

1. **The `getDirectoryPath()` / wrapper-surface gap is the single most repeated defect** — it appears in both series (#3540678 in 2.x; #3611227, #3600726 in 3.0) and hits core `FileSystem::tempnam()`, `AssetRoutes`, and `PathProcessorImageStyles`. The 4.0 wrapper must implement the full surface core can call on a scheme, or route around it via the decorated `file_system`.
2. **The S3 cluster** (ACL-disabled buckets #3616482/#3616487, non-seekable streams #3616493) is 3.0-specific and must not regress — these are core 4.0 design requirements already.
3. **External-URL correctness** (encoding #3616492, no double-slash #3616488/#3616491, private-scheme routes #3618271, multilingual) — the hardened URL path must carry forward.
4. **`[v1]` items are genuinely resolved by dropping league/flysystem v1** and can be closed out in triage.
5. **Open live risks at the window's end**: #3618526 (private downloads 500), #3618567 (config-based schemes broken), #3618527 (S3-compatible endpoint — needed for the Floci test bar), #3616491 (protocol-relative URLs).