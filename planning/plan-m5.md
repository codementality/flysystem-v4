# M5 — flysystem_asyncaws Submodule (s3 driver): Implementation Contract

Scope: the M5 flysystem_asyncaws milestone tickets (milestone "M5 flysystem_asyncaws", 15 open issues, zero closed — verified 2026-09-08) and their dependencies. Source of
truth: `planning/adapter-submodules.md` (§1 decision, §2.2 submodule contents, §4 packaging Option A,
§5 re-scoping), `planning/architecture.md` (§4 behavioral contracts, §5 exceptions, §6 visibility,
§11 adapter plugin contract), `planning/testing.md` (§2 TDD + seams, §4 Floci integration with the
M4-corrected emulator limits, §5 pain-map, §8 milestones), `planning/config-and-upgrade.md` (§2 preserved settings.php shapes, §3 preserved
config-entity shapes), and `planning/feature-evaluation-log.md`. Milestone exit criterion
(`testing.md` §8 M5): **the `s3` adapter's contract and Floci integration suites pass** — the
submodule ships a working `s3` driver proven against Floci-emulated S3. This
document is the living execution contract for M5.

**Document status (2026-09-08):** live contract — M5 unstarted. M4 is complete and frozen
(`planning/plan-m4.md` §9 closing record); everything below inherits M4's proven patterns
and its corrections. Milestone-immutability applies here identically once M5 closes.

---

## 1. M5 goal and boundary

M5 delivers the second optional adapter submodule: `flysystem_asyncaws`, a complete, self-contained Drupal
module and its own composer package, shipping the `s3` adapter driver
(AsyncAws via `league/flysystem-async-aws-s3`). It is the **second contrib-style plugin** proving
the Core adapter-plugin contract (`architecture.md` §11; `adapter-submodules.md`
§2.2), built entirely on M4's settled patterns (TDD two-ticket dance, probe-first legs,
mock-below-emulator where Floci cannot discriminate).

**In M5:**

- The `flysystem_asyncaws` submodule: `s3` driver plugin, its config schema fragment, its config form,
  its own composer.json, its own test suite (contract kernel + Floci integration).
- The `s3` driver contract: preserved config-key set (`bucket`, `region`, `prefix`,
  `visibility` — note the asymmetry: `s3` uses `default_visibility`, `aws_s3` uses `visibility`,
  both normalize through `AdapterDefinition`), `endpoint`, `path_style_endpoint`,
  `send_chunked_body`, `default_visibility`, `credentials.key`/`secret`/`secret_key_id` with `secret`
  markers, `use_acl`, `buildAdapter()` (league/flysystem-async-aws-s3), TYPE_REMOTE,
  supportsVisibility TRUE, `buildConfigurationForm()`.
- The `s3`-specific halves of re-scoped Core contracts: `use_acl` subclassed adapter (#17-split),
  stored Content-Type == `filemime` (#19-split), S3 ETag checksum (#23-split) — all THREE pinned
  by #105's amended legs (anti-#102-hole guard: claimed halves must be proven before #104 closes).
- The Floci IAM ground (shared with M4's #224/#225 — no duplication): public/private/`noacl`
  buckets plus the proven emulator limits (no enforcement of any kind, signatures unverified).
- The validation tickets: mapping round-trip (#154/#157), GD + ImageMagick staging with `s3`
  (#161/#167), core-scheme remap onto `s3` (#162/#168), settings.php config (#215/#216),
  config-form save (#226/#227), config-form render leg (#210, gates #104 directly).
- The asyncaws half of the ACL-disabled scenario (#245/#246, deferred from #84).

**Not in M5:** the SFTP submodule (M6), the migration submodule
(M8), release (M9), the D12 test matrix (#72, M7). The M9 retrospective (#243) tracks the
Floci upstream gaps (unenforced ACL mechanisms, unverified signatures) for end-of-project action.

---

## 2. Execution status (2026-09-08)

M5 gate status: **unstarted — 15 open, 0 closed.** No ticket in any active column.

### 2.1 Open tickets and edges (verified via GraphQL `blocked_by`)

| Ticket | What it is | Open blockers |
|---|---|---|
| **#104** | flysystem_asyncaws submodule (s3 driver) | #105, #210 |
| **#105** | T104: red tests — submodule (s3, amended: halves legs) | — |
| **#210** | T104b: s3 config-form render reds (gates #104) | — |
| **#154 / #157** | Mapping round-trip (feature + T154) | #104 + #157 / — |
| **#161 / #167** | GD + ImageMagick staging (feature + T161) | #104 + #167 / — |
| **#162 / #168** | Core-scheme remap (feature + T162) | #104 + #168 / — |
| **#215 / #216** | settings.php config (feature + T215, amended: missing-keys leg + presigned probe) | #104 + #216 / #104 |
| **#226 / #227** | Config-form save (feature + T227) | #104 + #227 / #104 |
| **#245 / #246** | s3 ACL-disabled scenario (feature + T245) | #104 + #246 / #105 |

### 2.2 Work order (deepest unstarted blocker first)

**#105 + #210 → #104 → #157/#167/#168/#216/#227 → #154/#161/#162/#215/#226 → #246 → #245.** Rationale: #105 and #210 gate the driver itself and have no blockers; the T#s that feed #104-gated features come next (their output idles otherwise — consumer-chain rule); #245/#246 close the milestone (need #104 plus #105 started).

---

## 3. Standing constraints (inherited from M4 — binding, not re-litigated)

- `declare(strict_types=1)` everywhere; full type hints; constructor DI in service classes.
- Cache metadata on all render arrays; English user-facing strings in `$this->t()`.
- No debug code. PHPStan clean; PHPCS Drupal standard clean (canonical `.ddev/commands/web/*` configs).
- `FileExists` enum everywhere; no APIs flagged for removal.
- **No code forward from v3**; planning docs are the sole spec source.
- **No driver knowledge in Core** — everything `s3`-specific lives in the submodule.
- Floci is a **testing emulator ONLY**; production code has zero Floci dependency.
- Core's `drupal/key` deprecations deferred to M9 (#149).
- **Tests measure; they never provision** (assert environment buckets, FAIL when absent).
- **Green ≠ scope complete** (open `blocked_by` = not done).
- **Explicit test methods, never data providers** (`@dataProvider` deprecated PHPUnit 11→12; `#[DataProvider]` silently ignored by this runner — verified M4 #239).
- **Mock below the emulator where Floci cannot discriminate** (M4 #240 pattern); E2E enforcement waits on #243.
- **Probe-first legs** (measure stock behavior, never assume it); green-at-authoring pins gated through T# review per rule 12.
- **QA law**: phpunit scoped to changed files (`SIMPLETEST_DB=mysql://db:db@db/test`, `SIMPLETEST_BASE_URL=http://web`); phpcs/phpstan full-module canonical configs; actual output pasted; phpcs clean preconditions review.
- **One ticket delivered at a time**; board reads filtered to the current milestone.

---

## 4. Test plan summary

- **Contract layer**: Kernel tests against the `s3` driver (real AsyncAws SDK) — discovery, config-key contract (incl. `secret` markers), buildAdapter, XOR secret validation, required-key enforcement, plus the three halves legs (use_acl switch, mime probe, checksum probe per #105's amendment).
- **Integration layer**: Floci-backed Kernel tests — PUT/GET/HEAD round trips, visibility semantics, presigned shape (per #216's probe question — measure whether the adapter signs without a config key), `public_url_base` URLs end-to-end. CloudFront: NO preserved key exists for `s3` — no CloudFront scope (unlike aws_s3).
- **Validation mirrors**: mapping round-trip (#154), GD/ImageMagick staging (#161), core-scheme remap (#162, incl. the M4 lessons: registration order, stat writability, streaming upload fallback, per-leg unique Floci names), settings.php config (#215, incl. missing-keys leg), config-form save/render (#226, #210).
- **Scenario**: s3 ACL-disabled (#245) per its fork design (mock-first unless the emulator enforces by then).
- Every slice: red → green → (review); `#[RunTestsInSeparateProcesses]` on Kernel/Functional classes, never Unit; behavior through seams only.

---

## 5. Milestone exit criterion

`testing.md` §8 M5: **the s3 contract and Floci integration suites pass** — the driver is discovered, configures, builds, validates secrets, and works end-to-end against Floci (round trips, visibility, presigned shape, public URLs), plus the validation mirrors (mapping, staging, remap, settings.php, config form) and the scenario pair. M4's full QA gate (7-minute pipeline, ~66% coverage watch) applies unchanged. M5 is Done when all milestone tickets are closed on the board with review; then it is never revisited.
