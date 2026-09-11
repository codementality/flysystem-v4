# M5R + M6 (sftp submodule) + plan-m7 — Independent Plan & Code Review

Status: Review, 2026-09-12. Scope: milestone 18 (M5R retrospective, 24 closed) and milestone 17
(M6 `flysystem_sftpv3`, 18 closed), module commits `f976fb8..6d87c5f` (M5R A3 through T164), plus
`planning/plan-m7.md` as drafted. Judged against `planning/plan-m6.md` (§1 contract, §3 standing
rules, §5 exit criterion), `planning/plan-m7.md`, `planning/config-and-upgrade.md` §2,
`planning/testing.md` §5/§8, `AGENTS.md` rules 8/10/11/12, and `flysystem-3.0-ref` (BC verification
reads only).

## Executive summary

**M6's code is materially complete and every canonical gate is clean, but the milestone must not
close as written: the shipped missing-fingerprint warning collapses to a single scheme-less entry
(H1), one proving leg the plan explicitly required was never written (H2), and M6's own integration
pass — the gate that exists to catch exactly H1's class of inter-pair defect — never ran (H3).**
M5R spot-checks (presigned opt-in, IAM tri-state) are consistent with their tickets. plan-m7 is
sound in shape but loses the M6 carry-over work and is silent on coverage and deprecation posture.

| Gate | Result |
|---|---|
| phpcs — canonical `.ddev/commands/web/phpcs.xml.dist`, full module | exit 0, no output |
| phpstan — canonical config, relative target, fresh cache | `[OK] No errors` |
| phpunit — `flysystem_sftpv3/tests/src/Kernel` | OK, 29 tests / 91 assertions (4 deprecations) |
| phpunit — `flysystem_sftpv3/tests/src/Functional` | OK, 8 tests / 116 assertions (5 deprecations) |
| phpunit — `flysystem_sftpv3/tests/src/FunctionalJavascript` | OK, 3 tests / 30 assertions (3 deprecations) |
| GitLab pipeline (final M6 push) | green (user-verified) |
| Milestone 17 (M6) | 0 open / 18 closed |
| Milestone 18 (M5R) | 0 open / 24 closed |
| M6 milestone integration pass (plan-m6 §5) | **NOT RUN** — see H3 |
| Coverage | **not measured since M4** (~66% and falling per the M4 watch) — see M4 finding |

## Findings — by severity

- **HIGH — H1.** The sftp missing-fingerprint requirement collapses: two fingerprint-less schemes yield one warning, and it names no scheme.
- **HIGH — H2.** `use_agent` is declared, wired, rendered and persisted, but no leg proves agent auth is attempted — the exact leg plan-m6 §1 named.
- **HIGH — H3.** M6's milestone integration pass never ran, so no leg covers any cross-pair key/seam combination; H1 is an instance of what it would have caught.
- **MEDIUM — M1.** `private_key_key_id` and `passphrase_key_id` have no resolution leg; only `password_key_id` is proven.
- **MEDIUM — M2.** B.6 ("a public sftp scheme requires `public_url_base`") has no sftp-specific proving leg; no defect found in the generic Core path.
- **MEDIUM — M3.** The v3→v4 auth-exclusivity delta (v3 rejected both-set and neither-set) is absent from the README's upgrade deltas.
- **MEDIUM — M4.** Coverage is unmeasured across M5R+M6 despite a standing "below 70% and dropping" watch.
- **MEDIUM — M5.** Two new core deprecations surfaced by the requirements-hook leg live only in a ticket comment; no determination ticket exists.
- **LOW — L1.** `FilesystemFactory::getFilesystem()`'s docblock still states directory visibility is "always forced to PRIVATE", contradicting B2's shipped behavior.
- **LOW — L2.** `resolveDirectoryVisibility($definition)` has no parameter type declaration and no `@param` tag.
- **LOW — L3.** `resolveDirectoryVisibility()` swallows every `Throwable` silently; the failure degrades safely but invisibly.
- **LOW — L4.** `.gitlab-ci.yml` ships hardcoded test credentials and `StrictHostKeyChecking=no` with the package, unlabeled as CI-only at the file head.

## Findings detail

### H1. The missing-fingerprint warning reports one scheme-less entry for all sftp schemes — HIGH *(verified)*

**What:** `SftpV3AdapterDriver::getRuntimeRequirements()` returns a constant array key
(`flysystem_sftp_fingerprint_missing`) and `FlysystemRequirements::runtime()` merges driver entries
with `+=` inside the per-scheme loop, so the first fingerprint-less sftp scheme's entry wins and all
later schemes' entries are discarded; the entry text names no scheme.
**Evidence:** `modules/flysystem_sftpv3/src/Plugin/Flysystem/Adapter/SftpV3AdapterDriver.php:309`
(constant key), `src/Hook/FlysystemRequirements.php:118` (`$requirements += $driverEntries;`). Probe
(throwaway kernel test, two fingerprint-less sftp schemes `schemetest` + `mediatest`, run
2026-09-12, then deleted): `===PROBE=== schemes=2 fingerprint_entries=1
keys=flysystem_sftp_fingerprint_missing` / `===ENTRY=== flysystem_sftp_fingerprint_missing |
names_scheme=NO`. Every other entry in the same hook is keyed per scheme
(`flysystem_iam_undetermined_' . $scheme`, `flysystem_nobase_' . $scheme`, …).
**Impact:** B1 was filed CRITICAL because an unverified host key is a MITM exposure; the mitigation
it shipped is a status-report warning. On any site with two or more sftp schemes, the warning
under-reports — an operator who fixes the one scheme they can identify sees a clean status page
while the remaining schemes still connect unverified.
**Fix:**
- Key the entry per scheme: the driver cannot see the scheme name, so either (a) pass the scheme to
  `getRuntimeRequirements(array $config, string $scheme)` and let the driver key/parameterize its
  entries, or (b) have `FlysystemRequirements::runtime()` re-key driver entries as
  `$key . '_' . $scheme` and inject `@scheme` into the driver-provided strings.
- Include the scheme name in the title/description text (the other entries' pattern).
- Amend `AdapterDriverPluginBase::getRuntimeRequirements()`'s contract docblock: keys must be unique
  per driver **and per scheme**.
- Add the red leg this needs: two fingerprint-less schemes ⇒ two Warning entries, each naming its
  scheme.

### H2. `use_agent` has no leg proving agent authentication is attempted — HIGH *(verified)*

**What:** plan-m6 §1 declares `use_agent` "proven by a leg asserting agent auth is actually
attempted when set (no silent fallback into password auth)"; the shipped legs only prove the key is
declared, reaches `SftpConnectionProvider::$useAgent`, renders in the form, and persists as FALSE.
**Evidence:** `grep -rn "use_agent\|useAgent" modules/flysystem_sftpv3/tests/` returns only:
`SftpV3DriverContractTest.php:103` (declared-key list), the knobs leg's property assertion,
`SftpV3ConfigFormRenderTest.php:100` (field renders), `SftpV3ConfigFormSaveTest.php:102,120`
(persists FALSE). No leg exercises an agent-auth attempt.
**Impact:** the one key whose misbehavior is silent — a config that intends agent auth but falls
back to password auth (or to anonymous) — is the key with no behavioral proof. This is the "declared
everywhere, consumed nowhere" class that B1 was filed to stop, reproduced one key over.
**Fix:** file a T#/impl pair: assert the agent path is entered when `use_agent` is TRUE — e.g. drive
`buildAdapter()` with `use_agent => TRUE` and no password/private_key against the service and assert
the failure is the agent-auth failure (phpseclib's agent error), not a password attempt; or assert at
the seam that no password material is passed when the agent is selected. If the distinction is not
observable at the seam, record that determination on the ticket (testability policy) and pin the
next-best guard.

### H3. M6's milestone integration pass never ran — HIGH *(verified)*

**What:** plan-m6 §5 and the standing M5-P1 rule require, before a milestone closes, a list of every
config key/service/seam that more than one pair touched, with one leg per **combination**; the pass
was never performed, and plan-m6 §2 records it as outstanding while all 18 tickets are closed.
**Evidence:** `planning/plan-m6.md` §2 ("Remaining before M6 closes per §5: the milestone
**integration pass** … the pass NOT yet run"); milestone 17 reads 0 open / 18 closed (REST,
2026-09-12). No file in `modules/flysystem_sftpv3/tests/` covers a multi-pair combination
explicitly; H1 above is a live cross-pair defect (B1's driver entry × the C9 requirements hook)
found by review rather than by a leg.
**Impact:** the milestone's tickets are closed, so nothing else will force the pass; inter-ticket
defects (H1's class) ship silently, and the next milestone inherits them.
**Fix:** run the pass before declaring M6 closed, minimally over the keys/seams touched by more than
one pair — `visibility` (B2 × staging × integration), `password_key_id` (entity × remap × save ×
settings), `root` (contract × mapping × remap × staging), `timeout`/`max_tries` (contract ×
settings/B.5), and the requirements hook (B1 × C9 entries). Each entry gets a combination leg or a
recorded "covered by <leg>" citation; H1's fix leg satisfies the hook entry.

### M1. Two of the three secret key-reference keys have no resolution leg — MEDIUM *(verified)*

**What:** `password_key_id`, `private_key_key_id` and `passphrase_key_id` share one resolver
(`SftpV3AdapterDriver::secretMaterial()`), but only `password_key_id` has a leg exercising
resolution (the unresolvable-reference logging leg); the other two appear only in declared-key
lists, form-render assertions, and an unset() in the settings test.
**Evidence:** `grep -rn "private_key_key_id\|passphrase_key_id" modules/flysystem_sftpv3/tests/` →
`SftpV3ConfigFormRenderTest.php:123,125`, `SftpV3DriverContractTest.php:105,106`,
`SftpV3SettingsPhpConfigTest.php:175,177` — no resolution or precedence assertion.
**Impact:** plan-m6 §3's binding rule ("every config-key line names its consuming code path and its
proving leg") is unmet for two keys; a regression in either key's name or precedence (plaintext
before reference) would pass the suite.
**Fix:** extend the contract test with two legs: a Key entity resolving `private_key_key_id` (and
`passphrase_key_id`) reaches `SftpConnectionProvider::$privateKey`/`$passphrase`, and an unresolvable
reference for each logs + throws like the password pair. One file, two legs, no new pair needed if
folded into the M6 carry-over ticket.

### M2. B.6's "public sftp requires public_url_base" has no sftp-specific leg — MEDIUM *(reviewed)*

**What:** plan-m6 §1/§4 state a public sftp scheme requires `public_url_base` with no driver-native
URL and no presigned fallback; the delivered legs prove the success path only (URL built from the
base), and the rejection/degradation path for sftp is unproven — it was deliberately dropped during
#107 authoring as "semantics unverified".
**Evidence:** `SftpV3ServiceIntegrationTest::testPublicSchemeUrlEndToEnd` (success only);
`SftpV3EntityMappingTest::testEntitySftpSchemeResolvesUrlThroughPublicUrlBase` (success only). Core
covers the entity path generically: `src/Entity/FlysystemFilesystem.php:201` rejects a public scheme
with no base/presigned/driver-source, and :219 rejects `presigned_expiry` on a driver that cannot
sign — league's `SftpAdapter` implements `FilesystemAdapter` only, so the sftp+presigned loophole is
closed. The settings.php path (no entity validation) degrades via the wrapper report + the
`flysystem_nobase_<scheme>` warning.
**Impact:** no live defect; the contract line rests on Core's generic behavior with no sftp pin, so a
future driver-level change (e.g. adding a temporaryUrl seam) could silently alter it.
**Fix:** one leg asserting a public sftp scheme without a base is rejected at entity validation, and
one asserting the settings.php variant reports the `flysystem_nobase_*` warning rather than throwing.

### M3. The v3→v4 auth-exclusivity delta is undocumented — MEDIUM *(verified)*

**What:** v3 rejected an sftp config that set **both** `password` and `private_key`, and one that set
**neither**; v4 enforces neither rule (its XOR pairs are plaintext-vs-key-reference), so both-set
configs authenticate by league's key-then-password fallback and neither-set configs fail at connect
time. The README's upgrade section lists four deltas and not this one.
**Evidence:** v3 `flysystem-3.0-ref/src/Plugin/Flysystem/Adapter/SftpAdapterDriver.php:166-176`
(both throws); v4 `modules/flysystem_sftpv3/src/Plugin/Flysystem/Adapter/SftpV3AdapterDriver.php`
(no equivalent check; `secretMaterial()` returns plaintext-before-reference per key, independently
per key); `README.md` "Upgrading from Flysystem 3.x" delta table (four rows, none covering auth
exclusivity).
**Impact:** the user's BC ruling requires every behavior delta be called out; an operator upgrading a
v3 config that relied on the eager "not both"/"at least one" rejection now gets a connect-time
failure instead of a save/build-time error, with no documentation of the change.
**Fix:** add the row to the README delta table (v3 rejected both/neither at build; v4 accepts both —
league tries key then password — and defers neither to connect time, reported to watchdog). If the
eager check is wanted back, that is a separate red-first pair, not a doc change.

### M4. Coverage is unmeasured across M5R and M6 — MEDIUM *(verified)*

**What:** the standing watch (M4, user-reported) was "below 70% for the first time, ~66% and
dropping"; M5R and M6 added roughly 40 legs and three new source files, and no coverage measurement
has been taken since.
**Evidence:** `.ddev/commands/web/phpunit-coverage` exists and was not run in the M6 stretch (no
coverage artifact or ticket comment in the milestone); the M4 handoff note in `LESSONS_LEARNED.md`
records the last known figure and the `NoAclAwsS3Adapter` multipart branches as known-zero.
**Impact:** M7 is the test-hardening milestone; starting it without a baseline means its exit
criterion ("no suite grows an unearned leg") has no quantitative counterpart, and known-zero branches
stay invisible.
**Fix:** take one baseline run at M6 closure, record the figure and the top uncovered branches on the
closure comment, and give M7 an explicit coverage objective (see P2).

### M5. Newly surfaced core deprecations have no determination ticket — MEDIUM *(verified)*

**What:** the requirements-hook leg surfaced `cache.backend.memory` and `cache.static`
(deprecated drupal:11.3.0, removed 13.0.0) for the first time in this suite; they are recorded in a
comment on #299 and nowhere else.
**Evidence:** CI output pasted on #299 (`issues/299#issuecomment-5638720865`); local runs show 3–5
deprecations per sftpv3 suite; `planning/testing.md` §5 treats phpunit deprecations *due to the
module* as "NOT success" and is silent on core-sourced ones beyond the drupal/key parking (#149, M9).
**Impact:** the deprecation count grows without an owner, and the "pipeline green means clean"
posture erodes — exactly the drift the §5 table exists to prevent.
**Fix:** file one M7 determination ticket: enumerate every deprecation in the suite, classify
(module / dependency / core-sourced), fix the module-caused ones, park the rest with citations
(drupal/key → #149), and state the posture in `testing.md` §5.

### L1. Stale docblock contradicts B2's shipped behavior — LOW *(verified)*

**What:** `FilesystemFactory::getFilesystem()`'s docblock still says "directory_visibility is always
forced to Visibility::PRIVATE", which B2 replaced with the driver-answered
`resolveDirectoryVisibility()`.
**Evidence:** `src/Flysystem/FilesystemFactory.php:434-435` (docblock) versus :457 + :479-491 (the
delegating code).
**Impact:** the next reader trusts the docblock and reasons about the wrong contract.
**Fix:** rewrite the paragraph to state the driver-answered default with the force-private fallback
and cite B2/#302.

### L2. `resolveDirectoryVisibility()` has an untyped parameter — LOW *(verified)*

**What:** the new private method takes `$definition` with no type declaration and no `@param` tag,
against the project rule that all parameters carry type hints.
**Evidence:** `src/Flysystem/FilesystemFactory.php:479`
(`private function resolveDirectoryVisibility($definition): string`) with a docblock carrying only
`@return`; phpcs exit 0 and phpstan `[OK]` — neither gate catches it in this position.
**Impact:** a wrong-typed caller is a runtime error instead of a static one; the gates will not warn.
**Fix:** type it `AdapterDefinition $definition` (the actual argument type) and add the `@param` line.

### L3. The directory-visibility resolution swallows failures silently — LOW *(verified)*

**What:** `resolveDirectoryVisibility()` catches every `Throwable` and falls back to force-private
with no log or requirement entry, one file away from the hook that turns an unanswerable driver into
an explicit Info entry.
**Evidence:** `src/Flysystem/FilesystemFactory.php:480-486`.
**Impact:** the fallback direction is safe (private), but a driver whose policy surface throws on
every request is invisible; the project doctrine is "could not check must not render as clean".
**Fix:** log once per scheme at debug/notice via the existing logger channel, or surface it through
the same requirements Info path the hook already has.

### L4. CI-only credentials and host-key bypass ship unlabeled — LOW *(reviewed)*

**What:** `.gitlab-ci.yml` contains `SFTP_USERS: sftp:sftp:1001:1001:upload`, `sshpass -p sftp`, and
`-oStrictHostKeyChecking=no`; the file ships in the composer package, and its header does not state
that these are ephemeral CI sidecar values.
**Evidence:** `.gitlab-ci.yml` (sftp service block, smoke job script lines).
**Impact:** a reader copying the smoke job into an operational context inherits a host-key bypass;
the values themselves grant nothing outside the job's sidecar network.
**Fix:** one comment line at the sftp service/smoke job head: ephemeral CI sidecar only, never an
operational pattern, and cross-reference the README's production fingerprint guidance.

## plan-m7 review — modifications needed before M7 starts

### P1. plan-m7 carries no M6 carry-over block — HIGH *(reviewed)*
**What:** H1, H2, M1, M2 and M3 have no home: M6's milestone is closed, and plan-m7 §1/§2 scope the
milestone-12 tickets only.
**Fix:** add a "§1.0 M6 carry-over (filed before M7 work starts)" block listing the pairs to file:
the fingerprint per-scheme keying pair (H1), the `use_agent` proof pair (H2), the key-reference legs
(M1), the B.6 rejection legs (M2), and the README delta row (M3, doc-only, no pair). Order them
ahead of #62/#63, since they belong to a milestone already declared complete.

### P2. No coverage objective — MEDIUM *(reviewed)*
**What:** the test-hardening milestone has no coverage baseline, target, or measurement step, while
the standing watch says ~66% and falling (M4).
**Fix:** add to §5 an exit criterion: baseline measured at M7 start, the top-three uncovered
behavioral branches either covered or recorded with a rationale, and no net coverage regression.

### P3. Deprecation posture unstated — MEDIUM *(reviewed)*
**What:** §4/§5 do not say what the suite's deprecation count must be at M7 exit, despite
`testing.md` §5 making module-caused deprecations a hard fail and M5's new core-sourced entries being
unowned.
**Fix:** state the three-way classification and the exit rule (module-caused: zero; dependency:
cited ticket; core-sourced: recorded determination) and reference the M5 ticket from P1's block.

### P4. Research tickets have no close-out path — LOW *(reviewed)*
**What:** #277 (stat-cache benchmark) and #278 (SeaweedFS evaluation) are in milestone 12, which must
reach 0 open, but §1 marks them "explicitly NOT codified as legs" without saying how they close.
**Fix:** state it: each closes with a findings comment plus a follow-on ticket if the finding needs
work, and neither gates the milestone's code-facing tickets.

### P5. The D12 matrix sits last with no early smoke — MEDIUM *(reviewed)*
**What:** §3 puts #72 last among code-facing tickets so the matrix runs a fully green suite, but any
compat failure then surfaces at the end of the milestone, when it must re-enter the red-first pair
flow.
**Fix:** keep the commitment last, and add an early throwaway probe step: run the existing suite once
on core ^12 / PHP 8.5 at M7 start, record failures as tickets, and let #72 land the matrix once they
are cleared.

### P6. The #201/#202 conflict needs a harder gate — LOW *(reviewed)*
**What:** §2 flags the settings-memoization pair against the `SETTINGS_PHP_READ_LIVE_NOT_MEMOIZED`
lesson and says it "must reconcile … or the pair gets re-scoped with the user before it starts" —
correct, but not expressed as a blocking state.
**Fix:** mark the pair `dependency-blocked` on the board with the lesson cited, and record in §2 that
it cannot enter Ready until the user rules.

## What this review got right (bounds on the findings)

- **TDD pair discipline held.** Every M6 ticket has a T# partner, reds authored first, user approval
  before implementation, and joint closes; the deviations (green-at-authoring pins) are disclosed on
  the tickets rather than hidden.
- **The v3 config contract is preserved verbatim.** Verified key-by-key against
  `flysystem-3.0-ref`'s `flysystem.adapter_config.sftp` and v3's driver: fifteen keys, same names,
  same flat positions, `public_url_base` top-level. No v3-valid sftp config becomes invalid.
- **Secrets never reach logs or exceptions.** `secretMaterial()`'s error path logs and throws with the
  Key entity id only; form secret fields are `#type => password` with no `#default_value`, and the
  entity strip is pinned by legs in #107 and #229.
- **Core stayed driver-agnostic through both B-seams.** B1 and B2 added generic surfaces
  (`getRuntimeRequirements()`, `defaultDirectoryVisibility()`) rather than sftp knowledge in Core, and
  the aws_s3/s3 force-private pins (#297/#298) remained untouched.
- **Service-path hygiene held.** Every service-backed class owns a unique remote prefix with per-leg
  unique keys; the one fixed-path slip was caught in authoring and corrected.
- **Gates are genuinely clean**, with output pasted in the gate table, and the pipeline is green on
  the final push.

## Verification

```bash
# Gate table
ssh web vendor/bin/phpcs --standard=.ddev/commands/web/phpcs.xml.dist web/modules/custom/flysystem   # exit 0
ssh web vendor/bin/phpstan clear-result-cache -q
ssh web vendor/bin/phpstan analyse -c .ddev/commands/web/phpstan.neon --no-progress web/modules/custom/flysystem   # [OK] No errors
# phpunit (canonical env: SIMPLETEST_DB=mysql://db:db@db/test, SIMPLETEST_BASE_URL=http://web)
#   Kernel        → OK, 29 tests / 91 assertions
#   Functional    → OK, 8 tests / 116 assertions
#   FunctionalJS  → OK, 3 tests / 30 assertions

# H1 (the probe was deleted after the run; re-create to reproduce)
#   two sftp schemes in $settings['flysystem'], neither with host_fingerprint, then:
#   module_handler->invoke('flysystem', 'runtime_requirements')
#   observed: fingerprint_entries=1, keys=flysystem_sftp_fingerprint_missing, names_scheme=NO

# H2 / M1 (absence of legs)
grep -rn "use_agent\|useAgent" web/modules/custom/flysystem/modules/flysystem_sftpv3/tests/
grep -rn "private_key_key_id\|passphrase_key_id" web/modules/custom/flysystem/modules/flysystem_sftpv3/tests/

# M2 (Core closes the presigned loophole)
sed -n '195,232p' web/modules/custom/flysystem/src/Entity/FlysystemFilesystem.php

# M3 (v3 enforced exclusivity)
sed -n '160,180p' flysystem-3.0-ref/src/Plugin/Flysystem/Adapter/SftpAdapterDriver.php

# Board
ssh web gh api "repos/codementality/flysystem-v4/milestones?per_page=100" --jq '.[] | select(.number==12 or .number==17 or .number==18) | "\(.number) \(.title) open=\(.open_issues) closed=\(.closed_issues)"'
```

## Disposition

**Before M6 is declared closed:**
1. H3 — run the integration pass; its output may absorb H1's leg.
2. H1 — file the pair (per-scheme keying + red leg + base-class contract docblock amendment); CRITICAL-adjacent, it defeats a shipped security mitigation.
3. H2 — file the pair (agent-auth proof, or a recorded testability determination).
4. M4 — take the coverage baseline and record it on the closure comment.

**Filed into M7 before its first ticket starts (P1's block):**
5. M1, M2 — fold into one carry-over legs ticket with its T# partner.
6. M3 — README delta row (doc-only, no pair).
7. M5 — deprecation determination ticket.
8. L1, L2, L3 — one hygiene ticket (three sub-items, one commit).
9. L4 — CI comment line; may ride with item 8.

**plan-m7 edits (no tickets, document changes):**
10. P1 (carry-over block), P2 (coverage criterion), P3 (deprecation posture), P5 (early D12 probe), P4 and P6 (wording/board state).
