# M6 — flysystem_sftpv3 Submodule (sftp driver): Implementation Contract

Scope: the M6 flysystem_sftpv3 milestone tickets (milestone "M6 flysystem_sftpv3", 14 open issues, zero closed — verified 2026-09-10) and their dependencies. Source of
truth: `planning/adapter-submodules.md` (§1 decision, §2.2 submodule contents, §4 packaging Option A,
§5 re-scoping), `planning/architecture.md` (§4 behavioral contracts, §5 exceptions, §6 visibility,
§11 adapter plugin contract), `planning/testing.md` (§2 TDD + seams, §4 integration infrastructure,
§5 pain-map, §8 milestones), `planning/config-and-upgrade.md` (§2 preserved settings.php shapes, §3 preserved
config-entity shapes), and `planning/feature-evaluation-log.md`. Milestone exit criterion:
**the `sftp` adapter's contract and SFTP-service integration suites pass** — the
submodule ships a working `sftp` driver proven against a real SFTP service. This
document is the living execution contract for M6.

**Document status (2026-09-10):** live contract — M6 unstarted. M5 is complete
(`planning/plan-m5.md` closing record); milestone 18 (M5R Retrospective review
issues) sits between M5 and M6. Everything below inherits M4/M5's proven patterns
and their corrections. Milestone-immutability applies here identically once M6 closes.

---

## 1. M6 goal and boundary

M6 delivers the third optional adapter submodule: `flysystem_sftpv3`, a complete, self-contained Drupal
module and its own composer package, shipping the `sftp` adapter driver
(via `league/flysystem-sftp-v3`). It is the **third contrib-style plugin** proving
the Core adapter-plugin contract (`architecture.md` §11; `adapter-submodules.md`
§2.2), built entirely on M4/M5's settled patterns (TDD two-ticket dance, probe-first legs,
mock-below-emulator where the service cannot discriminate).

**In M6:**

- The `flysystem_sftpv3` submodule: `sftp` driver plugin (`SftpV3AdapterDriver`, plugin ID `sftp`), its config schema fragment (`flysystem.adapter_config.sftp`), its config form,
  its own composer.json (`league/flysystem-sftp-v3` in `require`), its own test suite (contract kernel + SFTP-service integration).
- The `sftp` driver contract: preserved config-key set (`host`, `username`, `root`,
  `password`/`private_key`/`passphrase` + `*_key_id` with `secret` markers,
  `port`, `timeout`, `max_tries`, `use_agent`, `host_fingerprint`,
  `visibility`), `buildAdapter()` (league/flysystem-sftp-v3), TYPE_REMOTE,
  supportsVisibility TRUE, `buildConfigurationForm()`, XOR secret validation via the plugin-derived path (#100).
- The SFTP service container (#212, the Floci-#71 analog): GitLab pipeline service + local parity via the DDEV addon (`iljapolanskis/ddev-sftp`, recorded on #106) + documented setup. Gates every integration leg below.
- The validation tickets: mapping round-trip (#155/#158), GD + ImageMagick staging with `sftp`
  (#163/#169), core-scheme remap onto `sftp` (#164/#170, incl. the M4/M5 lessons: registration order, stat writability, streaming upload fallback, per-leg unique names, per-class unique service paths — §3), settings.php config (#217/#218),
  config-form save (#228/#229), config-form render leg (#211, gates #106 directly).

**Not in M6:** the migration submodule
(M8), release (M9), the D12 test matrix (#72, M7). The M9 retrospective (#243) tracks the
Floci upstream gaps for end-of-project action.

---

## 2. Execution status (2026-09-10)

M6 gate status: **unstarted — 14 open, 0 closed (verified 2026-09-10).** T#s with no open blockers in Ready, implementations in Backlog; nothing In progress.

### 2.1 Open tickets and edges (verified via GraphQL `blockedBy`; non-M6 blockers #78/#100/#24/#222 all CLOSED)

| Ticket | What it is | Open blockers |
|---|---|---|
| **#106** | flysystem_sftpv3 submodule (sftp driver) | #107, #211 |
| **#107** | T106: red tests — submodule (sftp) | — |
| **#211** | T106b: sftp config-form render reds (gates #106) | — |
| **#212** | SFTP service container (CI + local parity + docs) | — |
| **#155 / #158** | Mapping round-trip (feature + T155) | #106 + #212 + #158 / — |
| **#163 / #169** | GD + ImageMagick staging (feature + T163) | #106 + #212 + #169 / — |
| **#164 / #170** | Core-scheme remap (feature + T164) | #106 + #212 + #170 / — |
| **#217 / #218** | settings.php config (feature + T217) | #106 + #218 / #106 |
| **#228 / #229** | Config-form save (feature + T229) | #106 + #229 / #106 |

Board columns (verified 2026-09-10): Ready — #107, #211. Backlog — the other twelve. Hygiene note: #212 has no blockers but sits in Backlog; it is startable and belongs in Ready at the next board reconciliation.

### 2.2 Work order (deepest unstarted blocker first)

**#107 + #211 + #212 → #106 → #158/#169/#170/#218/#229 → #155/#163/#164/#217/#228.** Rationale: #107, #211, and #212 gate the driver and its proving ground and have no blockers; the T#s that feed #106-gated features come next (their output idles otherwise — consumer-chain rule: #158/#169/#170/#218/#229 are themselves unblocked, but working them before #106 starts strands approved reds). #212 must land before any service-backed leg runs green anywhere.

---

## 3. Standing constraints (inherited from M4/M5 — binding, not re-litigated)

- `declare(strict_types=1)` everywhere; full type hints; constructor DI in service classes.
- Cache metadata on all render arrays; English user-facing strings in `$this->t()`.
- No debug code. PHPStan clean; PHPCS Drupal standard clean (canonical `.ddev/commands/web/*` configs).
- `FileExists` enum everywhere; no APIs flagged for removal.
- **No code forward from v3**; planning docs are the sole spec source.
- **No driver knowledge in Core** — everything `sftp`-specific lives in the submodule.
- The SFTP service is a **testing service ONLY**; production code has zero test-service dependency.
- Core's `drupal/key` deprecations deferred to M9 (#149).
- **Tests measure; they never provision** (assert environment service/paths, FAIL when absent).
- **Green ≠ scope complete** (open `blocked_by` = not done).
- **Explicit test methods, never data providers** (`@dataProvider` deprecated PHPUnit 11→12; `#[DataProvider]` silently ignored by this runner — verified M4 #239).
- **Mock below the service where it cannot discriminate** (M4 #240 pattern).
- **Probe-first legs** (measure stock behavior, never assume it); green-at-authoring pins gated through T# review per rule 12.
- **QA law**: phpunit scoped to changed files (`SIMPLETEST_DB=mysql://db:db@db/test`, `SIMPLETEST_BASE_URL=http://web`); phpcs/phpstan full-module canonical configs; actual output pasted; phpcs clean preconditions review.
- **One ticket delivered at a time**; board reads filtered to the current milestone.
- **Every config-key line names its consuming code path and its proving leg**, not just the key name (M5 §3, binding since the C1/P2 finding).
- **Any config key settable from both settings.php and the admin form requires a proving leg per seam** (M5 §3, binding since the C2/P3 finding).
- **Testability policy: addressable now stays; unaddressable-or-unmockable defers to M9 with the reason recorded** (M5 §3, H4 precedent).
- **Service object keys are unique per test CLASS (mandatory, M5 §3 as enforced 2026-09-10).** CI runs one phpunit job for the whole module against shared services: the SFTP service is shared exactly like Floci, so identical path+key used by two classes read each other's objects (the 2026-09-10 stale-object false-green). Every test class owns its remote path prefix; per-leg unique names inside it. Reusing another class's prefix is a defect.
- **Efficient tracker queries only** (LESSONS_LEARNED 2026-09-10, binding): board reads are milestone-scoped and batched (one pull per phase, reused); single-card checks via scoped queries or the mutation echo; REST preferred for non-move operations; never re-pull to confirm routine moves.

---

## 4. Test plan summary

- **Contract layer**: Kernel tests against the `sftp` driver (real phpseclib/SFTP) — discovery, config-key contract (incl. `secret` markers), buildAdapter, XOR secret validation, required-key enforcement.
- **Integration layer**: SFTP-service-backed Kernel tests — PUT/GET round trips, visibility semantics, `public_url_base` URLs end-to-end. No CloudFront/presigned scope (sftp has neither).
- **Validation mirrors**: mapping round-trip (#155), GD/ImageMagick staging (#163, incl. per-class unique service paths), core-scheme remap (#164, incl. the M4/M5 lessons), settings.php config (#217), config-form save/render (#228, #211).
- **Infrastructure first**: #212 lands the service (CI container + local addon parity + docs) before any service-backed leg is expected green; service-backed legs assert the environment and fail when absent — they never provision it.
- Every slice: red → green → (review); `#[RunTestsInSeparateProcesses]` on Kernel/Functional classes, never Unit; behavior through seams only.

---

## 5. Milestone exit criterion

**The sftp contract and SFTP-service integration suites pass** — the driver is discovered, configures, builds, validates secrets, and works end-to-end against the SFTP service (round trips, visibility, public URLs), plus the validation mirrors (mapping, staging, remap, settings.php, config form) and the #212 infrastructure deliverable (CI container + local parity + docs). M4/M5's full QA gate (pipeline green, coverage watch) applies unchanged. M5R review issues (milestone 18) precede M6's start. M6 is Done when all milestone tickets are closed on the board with review; then it is never revisited.
