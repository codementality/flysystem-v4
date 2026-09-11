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
- The `sftp` driver contract: preserved config-key set, each key naming its consuming code path and its proving leg (binding §3 rule — a key that cannot name a leg is not ready to be declared):
  - `host`, `username`, `password`, `private_key`, `passphrase`, `port` → read by `SftpV3AdapterDriver::buildAdapter()` into league `SftpConnectionProvider` (pass-through to phpseclib); proven by #106 contract legs (build + auth against the SFTP service).
  - `host_fingerprint` → `SftpConnectionProvider::$hostFingerprint`, verified in `checkFingerprint()` — which returns early when empty (fails open, league source), so an absent fingerprint raises a `hook_runtime_requirements` warning, never a hard failure; proven by T-B1/B1 legs (match connects, mismatch throws `UnableToEstablishAuthenticityOfHost`, absent connects + warns).
  - `use_agent` → `SftpConnectionProvider::$useAgent` (league default FALSE); proven by a leg asserting agent auth is actually attempted when set (no silent fallback into password auth).
  - `password_key_id` / `private_key_key_id` / `passphrase_key_id` (`secret` markers) → Key-module resolution (C1 pattern); proven by #106 contract legs.
  - `root` → league `SftpAdapter` path prefix; proven by #155 round-trip legs.
  - `visibility` → file visibility through the league `PortableVisibilityConverter`; directory visibility follows the driver policy (B.2: `sftp` follows scheme visibility; `aws_s3`/`s3` stay forced-private, pinned by #297/#298); proven by #163 staging legs plus the T-B2/B2 traversability leg (public-scheme directory traversable by a non-owner).
  - `timeout` / `max_tries` → `SftpConnectionProvider` (league defaults 10s / 4 tries = 40s worst case per scheme per request — NOT shipped; the driver sets lower values targeting a low-single-digit-second render-path budget, rationale in §4); proven by the #217/#218 degradation leg (unreachable host degrades within budget).
- A public `sftp` scheme requires `public_url_base`; there is no driver-native URL and no presigned fallback (B.6).
- The `sftp` driver contract further: `buildAdapter()` (league/flysystem-sftp-v3), TYPE_REMOTE, supportsVisibility TRUE, `buildConfigurationForm()`, XOR secret validation via the plugin-derived path (#100).
- The SFTP service container (#212, the Floci-#71 analog): GitLab pipeline service + local parity via the DDEV addon (`iljapolanskis/ddev-sftp`, recorded on #106) + documented setup. Gates every integration leg below.
- The validation tickets: mapping round-trip (#155/#158), GD + ImageMagick staging with `sftp`
  (#163/#169), core-scheme remap onto `sftp` (#164/#170, incl. the M4/M5 lessons: registration order, stat writability, streaming upload fallback, per-leg unique names, per-class unique service paths — §3), settings.php config (#217/#218),
  config-form save (#228/#229), config-form render leg (#211, gates #106 directly).

- **No in M6:** the migration submodule
(M8), release (M9), the D12 test matrix (#72, M7). The M9 retrospective (#243) tracks the
Floci upstream gaps for end-of-project action.

**Provider knobs intentionally NOT in M6 scope (declared keys are the contract):** the league `SftpConnectionProvider` (verified at vendored 3.36.0 source + the adapter's docs page) accepts additional knobs beyond the contract — `connectivityChecker` (disclosed as the last constructor argument on the league docs page's Setup example) and `preferredAlgorithms` / `disableStatCache` (NOT on the docs page; constructor-only, verified in vendored source). None are in the preserved v3 config shape or this contract, so none become module config keys. Recording the non-consumption decision here so these don't surface as C1-pattern declared-but-unconsumed keys; extending scope later requires a red leg per the standing rules.

M5R A6 scope note (M5R #296, worked before M6): `presigned_expiry` is declared on the `s3` driver (key + schema + form field, aws_s3 #252 public-scheme gating mirrored) — agreed, expressed functionality since M5, not new scope.

---

## 2. Execution status (2026-09-12 — M6 execution complete, closure pending)

M6 gate status: **all 18 tickets closed (verified via REST 2026-09-12; milestone 17 shows 0 open /
18 closed).** Every TDD pair of §2.1 below is worked to Done: the reds authored first, the user's
review gate held per pair, and the joint-close rule applied (#106+#107+#211 trio, #299+#301,
#300+#302, #218+#217, #158+#155, #169+#163, #170+#164, #229+#228, #212 standalone-infra).
Remaining before M6 closes per §5: the milestone **integration pass** (the M5 P1 rule — one leg
per seam/key combination that more than one pair touched) and the final pipeline/coverage check.
The remainder of this §2 is the as-built record; §6 lists every change from this contract's
original text.

### 2.1 Open tickets and edges (verified via GraphQL `blockedBy` + REST on 2026-09-11; non-M6 blockers #78/#100/#24/#222 all CLOSED)

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
| **#299 / #301** | T-B1 / B1: host_fingerprint fail-closed pair (B.1) | — / #299 + **#106** |
| **#300 / #302** | T-B2 / B2: sftp directory-visibility policy pair (B.2) | — / #300 + **#106** |

Board columns (verified 2026-09-11): Ready — #107, #211, #212, #299, #300. Backlog — #106,
#155, #163, #164, #217, #228, #301, #302. #212's earlier Backlog position was already
reconciled. The #106 blocker edges on #301/#302 were added during the pre-start plan review
(2026-09-11, user-approved): they were MISSING — T-B1/T-B2's reds are authored alongside
#107/#211, but the B implementations consume #106's driver, so working #301/#302 before #106
delivers the driver would strand approved reds (the #54/#17 consumer-chain trap).

### 2.2 Work order (deepest unstarted blocker first)

**#212 + #107 + #211 → #106 → #299/#300 reds (authored alongside #107 per the B.1/B.2 handoff;
impls #301/#302 after #106 delivers the driver) → #158/#169/#170/#218/#229 →
#155/#163/#164/#217/#228.** The prior gate wording — "#106 additionally gated on the M5R A.1–A.4
implementations" — is SATISFIED: that pair set closed with the M5R milestone (milestone 18,
zero open). Rationale: #107, #211, and #212 gate the driver and its proving ground and have
no blockers; the T#s that feed #106-gated features come next (consumer-chain rule: #158/#169/
#170/#218/#229 are individually unblocked, but working them before #106 starts strands approved
reds). #212 must land before any service-backed leg runs green anywhere.

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
- **Milestone integration pass (required before a milestone may close).** List every config key, service and seam that more than one pair in this milestone touched. For each, name one leg exercising the **combination**, not the pairs separately. The milestone closes only when that list is empty or every entry has its leg. (Binding since the M5 P1 finding: per-ticket gates cannot see inter-ticket defects.)
- **Config consumers name their keys; resolution has a single owner** (binding since the M5 P3/M2 finding): every new component that reads config names the keys it reads and the contract it reads them under. When two components read the same key, one of them owns the resolution and the other calls it — never two readers of the same raw config.

---

## 4. Test plan summary

- **Contract layer**: Kernel tests against the `sftp` driver (real phpseclib/SFTP) — discovery, config-key contract (incl. `secret` markers), buildAdapter, XOR secret validation, required-key enforcement.
- **Integration layer**: SFTP-service-backed Kernel tests — PUT/GET round trips, visibility semantics, `public_url_base` URLs end-to-end. No CloudFront/presigned scope (sftp has neither).
- **Validation mirrors**: mapping round-trip (#155), GD/ImageMagick staging (#163, incl. per-class unique service paths), core-scheme remap (#164, incl. the M4/M5 lessons), settings.php config (#217), config-form save/render (#228, #211).
- **Infrastructure first**: #212 lands the service (CI container + local addon parity + docs) before any service-backed leg is expected green; service-backed legs assert the environment and fail when absent — they never provision it.
- **Directory traversability (B.2):** one leg asserting a public `sftp` scheme's directories are traversable by a non-owner (T-B2; the regression-guard pins for `aws_s3`/`s3` live in M5R #297/#298).
- **Unreachable-host degradation (B.5):** one leg asserting an unreachable host degrades within the render-path budget (low single-digit seconds — league's shipped 10s × 4 tries would stall every request touching the scheme, including anonymous renders; the driver's lower shipped values and their rationale are recorded in §1). Folds into #217/#218 — no new pair.
- Every slice: red → green → (review); `#[RunTestsInSeparateProcesses]` on Kernel/Functional classes, never Unit; behavior through seams only.

---

## 5. Milestone exit criterion

**The sftp contract and SFTP-service integration suites pass** — the driver is discovered, configures, builds, validates secrets, and works end-to-end against the SFTP service (round trips, visibility, public URLs), plus the validation mirrors (mapping, staging, remap, settings.php, config form) and the #212 infrastructure deliverable (CI container + local parity + docs). M4/M5's full QA gate (pipeline green, coverage watch) applies unchanged. M5R review issues (milestone 18) precede M6's start. M6 is Done when all milestone tickets are closed on the board with review; then it is never revisited.

---

## 6. As-built record (2026-09-12) — changes from this contract's original text

Every deviation/finding made during execution, recorded per rule 11 (corrections on tickets, mirrored here). The record is VERIFIED — each item names its proving leg or ticket.

1. **The driver consumes all fifteen declared keys; the config shape is FLAT** (preserved v3, config-and-upgrade.md §2). Three cross-cutting corrections landed after their reds exposed shapes:
   - **Top-level driver surfaces (Core, no driver knowledge):**
     - `AdapterDriverPluginBase::getRuntimeRequirements()` (B.1 seam) — the hook composes driver-owned requirement entries (#301); M5R-A1's could-not-check Info pattern preserved (the empty catch flagged at review became an Info entry, never silence).
     - `AdapterDriverPluginBase::defaultDirectoryVisibility()` (B.2 seam) — `FilesystemFactory::getFilesystem()` no longer force-wires `OPTION_DIRECTORY_VISIBILITY => PRIVATE` for every scheme; the driver answers (sftp: FOLLOW the scheme visibility) and the factory composes; NULL keeps the force-private S3 default (#302) — the #297/#298 pins were untouched.
   - **Driver-side mappings:** `providerMaxTries()` — league `maxTries` counts retries BEYOND the first attempt; the driver maps `max_tries` → `max_tries - 1` so one declared try = one attempt (#217; proved by #218's 6s red landing at 3s).
   - **Form shape:** the #229 reds exposed that the credentials fieldset SAVED a nested `credentials.*` shape the schema lacked; #228 flattened the fields (form field names ARE the saved shape) and completed the schema fragment (the six pair-source keys as top-level strings). Dependent pins re-pinned: #211's render leg naming + #229's two submissions + its leg-4 seed (the XOR-both-halves shape).
   - **Schema fragment:** shipped fragment completed to 1:1 with the v3 `flysystem.adapter_config.sftp` mapping after the ConfigSchemaChecker `config.password_key_id missing schema` errors (#229 legs 1/3).
2. **CI corrections found by the first real sftp runs (#212):** the scripted-sftp smoke line lost `-b /dev/stdin` (batch mode disables password auth outright) and the phpseclib login probe became an openssh-client+sshpass login (the sftp SDK belongs to the submodule — the require/require-dev split rule; the class was absent from the CI vendor until #106).
3. **The B.5 budget:** shipped `timeout 3 / max_tries 1` — league's 10s × 4-tries worst case was 40s per scheme touch. The B.5 red (#218 leg 4, TEST-NET-1 host) failed at 6.02s BECAUSE of item 1's mapping; the corrected leg runs inside the 5s budget.
4. **BC ruling (user, 2026-09-12): upgrade without reconfiguration wins.** The v3→v4 sftp shape is preserved verbatim (all fifteen keys flat, `public_url_base` top-level); `root` stays OPTIONAL in v4 (v3 required it) — documented in the README "Upgrading from Flysystem 3.x" section, never re-enforced. Also there: the report-instead-of-throw delta, the 3s/1-try budget, the fingerprint fail-open warning, and the `use_acl` opt-in note.
5. **Scheme naming:** idiom recorded — sftp has NO S3-style `prefix` key; the per-class remote prefix rides inside `root` (`upload/<prefix>`); per-class unique prefixes and per-leg unique keys enforced across all service-backed files (plan-m5.md §3 carried forward).
6. **Where the pair order deviated from §2.2's plan:** corrected mid-work by the user — after the #106/#107/#211 trio closed, #301 came NEXT (not #300), because #301's only remaining blocker (#299, approved) was already satisfied; the red graph beat the stale snapshot. #300/#302 followed. Both corrections recorded on the tickets.
7. **The as-built env (for the record):** plain `ssh web gh ...` restored after the web-container re-creation wiped gh's persisted login (LESSONS_LEARNED 2026-09-12 entry: sshd never forwards the compose env; the login state was the thing every earlier session silently relied on).
