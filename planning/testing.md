# Flysystem v4 — Testing

Status: **Draft**. Companion: `architecture.md`, `feature-evaluation-log.md`, `drupal-issue-queue.md`.

## 1. Test bar (definition of done, in test terms)

The module is not "done" until every behavioral decision in `architecture.md` is encoded as a regression test, runnable in CI with **no external network**, plus an integration layer against Floci-emulated AWS. Two layers:

1. **Contract layer** — fast, deterministic kernel tests. Real adapter code (no mocks for adapter behavior), no network, no disk.
2. **Integration layer** — kernel tests running the **real** S3 adapter against **Floci-emulated S3 + CloudFront**, locally (DDEV addon) and in the GitLab pipeline (Floci containers — confirmed allowed/supported with the testing team).

## 2. Test-driven development process (project-wide commitment)

The project adopts **TDD** and adheres to it — the design is already spec-first, so the behavioral contracts in `architecture.md` §4–§7 *are* the test specifications. Confirmed 2026-08-27.

**The loop**: red → green → (review). Write the failing test first, then only enough code to pass. Refactoring is not part of the loop — it belongs to code review.

**Red-test tickets**: each feature has a test ticket (T#) whose sole deliverable is failing tests. Per the board model, T# sits in the **"Tests complete, failing"** column once its red tests are authored (its terminal state, NOT Done); the implementation ticket then starts (the red state satisfies the blocking edge for starting) and makes the tests green, after which **both** move to Done. If a T#'s tests are already green when its turn arrives, it goes straight to Done. See `docs/agents/board.md` "The two-ticket test/implementation dance".

**Vertical slices, not horizontal.** One seam, one test, one minimal implementation per cycle. Never write the full test suite and then the implementation — a horizontal "all tests first" pass tests *imagined* behavior and commits to test structure before understanding the code. Each test is a tracer bullet that responds to what the last cycle taught.

**Seams — pre-agreed public boundaries (confirmed with the user 2026-08-27).** Tests live at seams, never against internals. No test is written at an unconfirmed seam:

1. **Stream wrapper** (`StreamWrapperInterface` / PHP stream layer) — via native PHP stream ops on a scheme URI: `fopen`/`fread`/`fseek`/`file_exists`/`is_dir`/`copy`/`rename`/`chmod`. Covers stat fabrication, `realpath()` FALSE, seekability, single-PUT writes, read-only rejection, temp-local.
2. **Decorated `stream_wrapper_manager`** (`StreamWrapperManagerInterface`) — `getViaUri` on a remapped `public://` resolves to the flysystem wrapper; `getWrappers`/`getClass`/`isValidScheme`; `getType` classification; registration from both config sources.
3. **Decorated `file_system`** (`FileSystemInterface`) — `copy`/`move`/`saveData`/`delete`/`getDestinationFilename`; flysystem→Drupal `FileException` mapping; `deleteRecursive` correctness.
4. **URL generation** (`getExternalUrl` via `FileUrlGenerator`) — the full URL policy: `public_url_base`, explicit presigned, loud error when neither, per-segment encoding, no double-slash, prefix inclusion, private route.
5. **Module service API** — checksum, config precedence (settings vs entity), connection test.
6. **Adapter plugin contract** — a fixture adapter configures, validates, builds a `Filesystem`, passes the connection test.
7. **Migration submodule** — walk/progress/conflict/verification through its command/service.
8. **Integrations** — GD/ImageMagick staging with a remote scheme.

The **Floci integration layer exercises seams 1–5 against real S3** — same assertions, real adapter.

**Good tests**: assert behavior through seams, never implementation details; expected values come from independent sources (known-good literals / the spec — never recomputed the way the code does); each test reads like a specification of an observable capability.

**Pipeline enforcement**: every merge runs the full suite (contract + Floci) in the Drupal GitLab pipeline; a red test can never be merged. The "next red tests" live in the GitHub issue backlog — which is how GitHub issues + TDD compose.

## 3. Contract layer

- **In-memory adapter fixture** (`feature-evaluation-log.md` Item 7): a test-only "inMemory" adapter driver plugin in a dedicated fixture module (`tests/modules/flysystem_inmemory_test/`) so kernel tests configure a **full scheme** backed by a real, complete `FilesystemAdapter` — exercising the wrapper, decorated `stream_wrapper_manager`, and registration path end-to-end. Built fresh (no code or naming carried from v3 — see plan-m1.md §1a).
  - Declared **REMOTE-type** so tests exercise the high-risk remote code paths.
  - Gotchas encoded: `writeStream` buffers (don't assert streaming semantics); directories are virtual; visibility is a symbolic string.
- **Mocked adapters** only where counting is required (e.g. "exactly one PUT on flush" — a counting adapter mock).
- No external network; S3 SDK mocked at the client level where the contract layer needs S3-specific behavior.

## 4. Integration layer — Floci

- Floci emulates **AWS S3 and CloudFront**.
- **Local dev**: the DDEV addon (already in this project; local S3 endpoint `floci-aws-4566`). The `aws_s3` driver's endpoint/path-style override (#3618527) is required for this and is a shipped feature.
- **CI**: Floci Docker containers in the GitLab pipeline.
- Exercises what mocks can't: real PUT/GET/HEAD round trips, multipart upload behavior, visibility/ACL semantics, presigned URL generation, `public_url_base`/CloudFront URLs end-to-end, and stat fabrication against real S3 `lastModified`/`size` metadata.
- **ACL-disabled bucket scenario**: the integration suite must cover the modern BucketOwnerEnforced bucket (any ACL → failure) to prove the `use_acl = false` subclassed-adapter path works.

## 5. Pain-map acceptance suite (the regression-prevention list)

Each item in `architecture.md` §4–§7 gets a named test (primarily contract layer; S3-specific ones in the Floci layer). Each is a **red test first** per §2:

| Behavior | Test |
|---|---|
| Stat fabrication | Correct `mode` bits so `file_exists`/`is_file`/`is_dir` tell the truth; stable `dev`/`ino`; private files readable (#3618526) |
| `url_stat` ACL-free | Never calls `visibility()`; works on ACL-disabled buckets (#3616487) |
| `realpath()` | Returns `FALSE` for remote, never a bogus string |
| `getType()` | Per-scheme, adapter-driven; GD staging decision depends on it |
| URL policy | `public_url_base` URLs; explicit-presigned; **loud error when neither**; per-segment encoding (#3616492); no double-slash (#3616488/#3616491); prefix included; private route resolves |
| Write path | **Exactly one PUT on flush** (counting mock); buffered `fwrite`s; native same-adapter move |
| Stat-cache invalidation | A mutation clears PHP's stat cache and our cache for affected paths (own + PHP) |
| Seekable reads | `fseek` works on a remote-style read stream (#3616493) |
| `temporary://` | Stays local, always |
| Decorated manager | A remapped `public://` resolves to the flysystem wrapper via `getViaUri` |
| GD / ImageMagick | Staging still works when the scheme is remote (realpath FALSE / non-LOCAL type) |
| Visibility | `use_acl=false`: no ACL sent, works on ACL-disabled bucket; `use_acl=true`: explicit ACL; `directory_visibility` private (#3616482) |
| Read-only | `writable=false`: all writes rejected, write-mode `stream_open` fails, `unlink` returns TRUE (DB ref removable) |
| Exceptions | flysystem → Drupal `FileException` mapping; wrapper never throws |
| Checksum | Per-scheme integrity API; ETag vs streaming MD5 (multipart/SSE-KMS caveat) |
| Mime on write | Stored S3 Content-Type equals Drupal's `filemime` |
| Migration | Post-move verification; conflict policy; non-atomic move handling |
| 3.0 regression-prevention (#3616485) | Wrapper self-sufficiency: native calls (`move_uploaded_file`, `is_dir`, `fopen`) work without a primed factory |

## 6. CI & environments

- **Test matrix**: currently Drupal 11.4 on PHP 8.4 (module not yet D12-ready). Drupal 12 + PHP 8.5 (D12 floor) added when the module targets it. PHPUnit 11 for the D12 leg.
- Floci containers run in the GitLab pipeline; DDEV addon for local integration runs.
- No test depends on real AWS credentials or external network.
- **Config form**: Drupal core's `phpunit.xml.dist` ("Form CORE"), with env vars inline — `SIMPLETEST_DB=mysql://db:db@db/test SIMPLETEST_BASE_URL=http://web ./vendor/bin/phpunit -c web/core/phpunit.xml.dist --bootstrap web/core/tests/bootstrap.php <test-path>`. Matches `.ddev/commands/web/phpunit` (the canonical GitLab-CI-mirroring command).
- `#[RunTestsInSeparateProcesses]` on Kernel/Functional classes (D11.3+ requirement), never on Unit.

### Pipeline-success definition (user, 2026-08-28)

"Pipeline success" is not a blanket green. The following criteria govern whether a GitLab pipeline run counts as pass:

| Job result | Verdict | Action |
|---|---|---|
| `cspell` warnings | **Pass** (with debt) | Fix with the next code push |
| CSS lint warnings | **Pass** (with debt) | Fix with the next code push |
| JS lint (`eslint`) warnings | **Pass** (with debt) | Fix with the next code push |
| `phpcs` warnings/errors **due to the Flysystem module** | **NOT success** | Fix before the pipeline counts as passing |
| `phpstan` warnings **due to the Flysystem module** | **NOT success** | Fix before the pipeline counts as passing |
| `phpunit` deprecations **due to the Flysystem module** | **NOT success** | Fix before the pipeline counts as passing |
| `phpunit` test failures (any) | **NOT success** | Always address |

Rule of thumb: non-PHP hygiene jobs (cspell, css, js lint) may be deferred a push; anything that reflects the module's PHP correctness — phpcs, phpstan, phpunit deprecations, phpunit failures — must be fixed before the run is considered a pass.

## 7. Adapter-plugin developer README (test requirement)

The developer README (see `architecture.md` §11) must include the **required tests** for a new adapter plugin and use one shipped adapter as the annotated reference implementation. The bar: a contributor can go from zero to a working, tested adapter plugin using only the README.

## 8. Milestones (each phase begins with its red tests)

Phase milestones derived from the design's dependency structure. **Every phase starts by writing the failing tests for its contracts (red), then implementing to green.** Each exit criterion is a test result, not a feature list.

**Design freeze status (user, 2026-08-28): COMPLETE — but iterable.** The design freeze concluded; however the project runs agile, not waterfall. Design decisions recorded in the planning docs may be revisited and iterated as features are developed, tested, and unanticipated roadblocks surface. Any iteration to a frozen decision is proposed, reviewed, and recorded before it takes effect.

- **M0 — Design freeze & project setup**: planning docs approved; GitHub repo + seeded issue backlog; CI skeleton. Exit: docs approved, issues created.
- **M1 — Foundation**: module skeleton, composer deps (`league/flysystem` v3, `flysystem-read-only`, `drupal/key`), `core ^11.4 || ^12` + PHP 8.5, the adapter plugin system + dynamic schema, config-entity + settings.php parsing, tagged-service registration, the **decorated `stream_wrapper_manager`**, connection test. Exit: a configured scheme resolves through the decorated manager — kernel test proves a remapped `public://` resolves to the flysystem wrapper.
- **M2 — The contract-faithful wrapper** (the center of gravity): stat layer, `realpath()` FALSE, `getType()`, URL policy, single-PUT write path, seekable reads, stat-cache + invalidation, temp-local, `getDirectoryPath`/`deleteRecursive` handling, exception strategy. Exit: the pain-map contract tests pass against the in-memory fixture.
- **M3 — Adapter hardening & integrations**: `use_acl`/visibility/read-only enforcement, mime-on-write, GD + ImageMagick verification, image-style routes, checksum API. Exit: GD and ImageMagick staging work with a remote scheme; Floci integration tests pass for visibility/ACL/URLs.
- **M4 — Test hardening & CI**: full two-layer suite in the GitLab pipeline (Floci containers), 3.0 regression-prevention coverage, D11.4 + D12 matrix. Exit: CI green on both majors; the `drupal-issue-queue.md` regression list is covered.
- **M5 — Migration submodule**: MountManager engine, walk/progress/conflict/verification, drush, tests. Exit: local→S3 migration verified against Floci; checksum verification proven.
- **M6 — Release**: upgrade guide + BC-break documentation, adapter-plugin developer README, config-and-upgrade verification, 4.0 release.