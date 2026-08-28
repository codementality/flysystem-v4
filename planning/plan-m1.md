# M1 — Foundation: Implementation Contract

Scope: the six M1 GitHub issues (#2–#7). Source of truth: `planning/architecture.md` (§3, §11, §12), `planning/testing.md` (§2, §3, §6), `planning/config-and-upgrade.md` (§2, §3). Milestone exit criterion: **a kernel test proves a remapped `public://` resolves to the flysystem wrapper through the decorated `stream_wrapper_manager`** (`testing.md` §8 M1).

## 1. Module facts

- Machine name: `flysystem` (matches 3.0-ref and the empty dev dir `web/modules/custom/flysystem/`).
- Dev home in this repo: `web/modules/custom/flysystem/` (docroot `web` per `.ddev/config.yaml`).
- `core_version_requirement: ^11.4 || ^12`; `dependencies: drupal:file, drupal:image, key:key`.
- Module `composer.json` `"php": ">=8.4"` — required for installability on the current D11.4 dev stack (PHP 8.4); the D12 leg runs PHP 8.5. (Deviates from "PHP 8.5" phrasing in `architecture.md` §12: a `^11.4 || ^12` module must install on 8.4. D12 test leg targets 8.5.)
- Only composer dep the module needs beyond league/flysystem v3 (already in site root): `league/flysystem-read-only` (used in M3, but declared now per #2).
- Tests run against **Drupal core's `phpunit.xml.dist`** (Form CORE — no project-root phpunit.xml), env vars inline: `SIMPLETEST_DB=mysql://db:db@db/test SIMPLETEST_BASE_URL=http://web ./vendor/bin/phpunit -c web/core/phpunit.xml.dist --bootstrap web/core/tests/bootstrap.php <test-path>`. Matches the project's `.ddev/commands/web/phpunit`. `#[RunTestsInSeparateProcesses]` on Kernel/Functional classes, never on Unit.

## 1a. NO CODE FORWARD FROM V3 (binding, user directive 2026-08-28)

The v4 rewrite brings **NO CODE FORWARD from Flysystem v3**. The `flysystem-3.0-ref/` directory is **off-limits as an implementation source** — no reading, no adapting, no copying of its classes, logic, service wiring, or structure.

- The **sole spec source** is `planning/architecture.md`, `planning/testing.md`, `planning/config-and-upgrade.md`, `planning/migration.md`, `planning/feature-evaluation-log.md`, `planning/drupal-issue-queue.md`.
- The **only v3 artifact that survives** is the **format of configuration** (the `settings.php` array shape + config-entity structure) to keep user backward compatibility — and that is already captured verbatim in `planning/config-and-upgrade.md` §2–§3. Agents never need to open v3-ref even for this.
- Every implementation must be written fresh from the behavioral contracts in `architecture.md` §4–§7. If a design decision in v3 looks tempting, it must be **re-derived from the spec**, not inherited.
- Violation of this rule aborts the project.

## 2. Open decision resolution

Adapter discovery (GitHub #38): **attribute + plugin manager** (D11/D12-native), per `architecture.md` §11. Rejected: service-tagged adapters (harder contrib DX). The developer README (M6) hides this choice from contributors anyway.

## 3. Vertical slices (TDD — one seam, red test first, then minimal green)

### Slice 1 — #2 Module skeleton
Files: `flysystem.info.yml`, `flysystem.module` (minimal), module `composer.json`, empty `services.yml` only if a service is defined.
Red test: Kernel test that installs the module (`installSchema`/`$this->installConfig` equivalent) without schema/config errors.
Green: skeleton files only. Verify: `./vendor/bin/phpunit --filter testModuleInstalls` via the canonical command (Form CORE).

### Slice 2 — #3 In-memory adapter fixture
A test-only `inMemory` adapter driver plugin in a dedicated fixture module `tests/modules/flysystem_inmemory_test/` (engine `league/flysystem-memory` is already in require-dev). Declared **REMOTE-type** so tests exercise high-risk remote paths. Gotchas (testing.md §3): `writeStream` buffers; directories virtual; visibility symbolic string. NOTE: the fixture module name is deliberately NOT the 3.0 artifact name (`flysystem_test_adapter`) — no code or naming is carried forward from v3 (plan-m1 §1a).
Red test (T3, #41): a kernel test resolves the `in_memory` driver through the plugin contract — `createInstance('in_memory', [])` → `buildAdapter([])` → `Filesystem` write → assert `fileExists`/`read` return the written data. (The "through the factory" variant is NOT part of T3: the FilesystemFactory is Slice 4/#5, downstream — see dependency graph. The factory-path assertion belongs to T5/#42.)
Green: the driver plugin (already shipped with the fixture module) — the red test passes once the plugin contract resolves it.

### Slice 3 — #4 Adapter plugin system + dynamic schema
Plugin manager (`plugin.manager.flysystem.adapter_driver`), base driver plugin interface + attribute, per-plugin contract declaration (config keys w/ types/labels/defaults, secret refs, LOCAL/REMOTE type, visibility support). Dynamic schema `flysystem.adapter_config.[%parent.driver]` (drives `config: type: flysystem.adapter_config.[%parent.driver]` in the `flysystem.filesystem.*` entity schema).
Red test: a fixture plugin's declared config keys produce a valid config schema fragment; the plugin manager discovers a fixture plugin.
Green: plugin manager + declaration API + schema generation for the shipped drivers (local, s3, aws_s3, sftp) and the in-memory fixture.
Verify: `ssh web drush php:eval` on schema validate, plus PHPUnit.

### Slice 4 — #5 FilesystemFactory single source of truth
`FilesystemFactory`: settings.php (via `@settings`) and config-entity (via entity storage) → normalized `AdapterDefinition`; **settings.php wins per scheme** (preserved precedence); connection test.
Red test: precedence (same scheme in both sources → settings.php wins); connection test returns `untested`/status for a reachable in-memory scheme.
Green: factory + definition value object + connection-test service.

### Slice 5 — #6 Tagged-service scheme registration
Schemes as tagged DI services (`stream_wrapper` tag + `scheme` attribute) for settings.php schemes (container build); config-entity schemes register at runtime via the decorated manager keeping core's manager in sync. Scheme names: `[a-z0-9-]` only (no underscores).
Red test: a configured scheme appears in the manager's known schemes; `isValidScheme` true.
Green: services.yml tagged registration + runtime registration path.

### Slice 6 — #7 Decorated stream_wrapper_manager (M1 exit)
Decorate `stream_wrapper_manager` (`FlysystemStreamWrapperManager` subclass): for owned schemes return the flysystem wrapper; else delegate. Rationale (VERIFIED, architecture.md §3.2): classes array last-wins, Symfony ServiceLocator first-wins — decoration is the only seam making both agree.
**Exit test (red first)**: kernel test — a scheme remapped to `public://` resolves via `getViaUri('public://...')` to the flysystem wrapper class.
Green: decorator service definition (`decorates: stream_wrapper_manager`), owned-scheme resolution, delegation fallback.
Verify: the exit kernel test + `ssh web drush cr` clean.

## 4. Constraints

- `declare(strict_types=1)` everywhere; full type hints; constructor DI (never `\Drupal::service()` in classes).
- Cache metadata on all render arrays (admin pages later; not in M1 scope beyond services).
- English user-facing strings wrapped in `$this->t()` (only M1 UI = connection-test output later; keep to a minimum).
- No debug code. PHPStan level 8 clean for new code; PHPCS Drupal standard clean.
- Never use APIs flagged for removal in 11.4+; `FileExists` enum everywhere (no ints).
- Do NOT implement M2 contracts (stat layer, URL policy, write path, exceptions, temp-local, etc.) in M1 — the wrapper can be a thin stub resolving the scheme; M2 hardens it.

## 5. Test plan summary

- All tests Kernel or Unit. No Functional tests in M1 (no UI). No network.
- Contract layer only in M1; Floci integration arrives in M4 (the `aws_s3` endpoint override is #24, not M1).
- Every slice: red → green → stop; no refactoring inside the loop.

## 6. Verification commands (canonical `.ddev/commands/web/*`, matching the GitLab pipeline)

```bash
# phpunit — Drupal core's phpunit.xml.dist (Form CORE), inline env vars
SIMPLETEST_DB=mysql://db:db@db/test SIMPLETEST_BASE_URL=http://web \
  ./vendor/bin/phpunit -c web/core/phpunit.xml.dist \
  --bootstrap web/core/tests/bootstrap.php \
  web/modules/custom/flysystem/tests/src/Kernel
# phpstan — module config in .ddev/commands/web
./vendor/bin/phpstan analyse --no-progress -c .ddev/commands/web/phpstan.neon web/modules/custom/flysystem
# phpcs — GitLab-pipeline-equivalent config in .ddev/commands/web (Drupal ruleset + contrib extension list)
./vendor/bin/phpcs --standard=.ddev/commands/web/phpcs.xml.dist web/modules/custom/flysystem
```