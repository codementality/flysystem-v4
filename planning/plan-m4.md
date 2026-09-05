# M4 — flysystem_aws Submodule (aws_s3 driver): Implementation Contract

Scope: the M4 flysystem_aws milestone tickets (milestone #15) and their dependencies. Source of
truth: `planning/adapter-submodules.md` (§1 decision, §2.2 submodule contents, §4 packaging Option A,
§5 re-scoping), `planning/architecture.md` (§4 behavioral contracts, §5 exceptions, §6 visibility,
§11 adapter plugin contract), `planning/testing.md` (§2 TDD + seams, §4 Floci integration, §5 pain-map,
§8 milestones), `planning/config-and-upgrade.md` (§2 preserved settings.php shapes, §3 preserved
config-entity shapes), and `planning/feature-evaluation-log.md`. Milestone exit criterion
(`testing.md` §8 M4): **the `aws_s3` adapter's contract and Floci integration suites pass** — the
submodule ships a working `aws_s3` driver proven against Floci-emulated S3 + CloudFront. This
document is the living execution contract for M4 and is kept current for the independent project
review.

**Document status (2026-09-05):** live contract — drafted at M3 completion, ahead of M4 execution.

---

## 1. M4 goal and boundary

M4 delivers the first optional adapter submodule: `flysystem_aws`, a complete, self-contained Drupal
module and its own composer package (`drupal/flysystem_aws`), shipping the `aws_s3` adapter driver
(AWS SDK v3 via `league/flysystem-aws-s3-v3`). It is the **reference "contrib-style" plugin** that
proves the Core adapter-plugin contract end-to-end (`architecture.md` §11; `adapter-submodules.md`
§2.2) and the first consumer of the **Floci** test infrastructure.

**In M4:**

- The `flysystem_aws` submodule: `aws_s3` driver plugin, its config schema fragment, its config form,
  its own composer.json, its own test suite (contract kernel + Floci integration).
- The `aws_s3` driver contract: full preserved config-key set (`bucket`, `region`, `prefix`,
  `visibility`, `presigned_expiry`, `cloudfront.domain`, `credentials.key/secret/secret_key_id` with
  `secret` markers, `use_acl`), `buildAdapter()` (league/flysystem-aws-s3-v3), TYPE_REMOTE,
  supportsVisibility TRUE, `buildConfigurationForm()`.
- The endpoint/path-style override (#3618527) — required for Floci and MinIO; a shipped feature of
  the submodule.
- The S3-specific halves of re-scoped Core contracts: `use_acl` subclassed adapter (#17-split),
  stored Content-Type == `filemime` (#19-split), S3 ETag checksum (#23-split), Floci ACL-disabled
  bucket scenario (#84).
- The Floci integration layer (#24/#61) — **now a prerequisite of M4, not an M7 afterthought**
  (corrected 2026-09-05 per the user: M4 cannot be tested without the emulated S3/CloudFront; the
  milestone-placement and dependency edges were fixed on the board).
- The validation tickets: mapping round-trip (#153/#156), GD + ImageMagick staging with `aws_s3`
  (#159/#165), core-scheme remap onto `aws_s3` (#160/#166).

**Not in M4:** the AsyncAws `s3` submodule (M5), the SFTP submodule (M6), the migration submodule
(M8), release (M9), the D12 test matrix (#72, M7). Core ships `local` only; `in_memory` stays a
dev-only test fixture.

---

## 2. Execution status (2026-09-05)

All M4 tickets are **Backlog / Ready** on the board; nothing has been worked. The M4 gate is the
**Floci integration layer (#24/#61)** — the T# (#61) is Ready (all blockers closed); the feature
(#24) is Backlog, blocked by its T#.

### 2.1 Done

*(none — M4 not yet started.)*

### 2.2 In flight

*(none.)*

### 2.3 Open, not started

| Ticket | What it is | Blocked by | Notes |
|---|---|---|---|
| **#24** | M3→M4: Floci integration layer + aws_s3 endpoint override | #61 (T24) + closed (#78/#71/#70/#37/#2/#1) | The M4 gate. Floci is a testing emulator ONLY (Core knows nothing of it — user decision 2026-08-30). Re-scoped 2026-08-30; moved to M4 + wired as submodule prerequisite 2026-09-05. |
| **#61** | T24: red tests — Floci integration layer | all closed | Ready. Red integration tests against Floci-emulated S3/CloudFront: real PUT/GET/HEAD, visibility/ACL, presigned, public_url_base/CloudFront URLs, ACL-disabled bucket scenario. |
| **#102** | M4: flysystem_aws submodule (aws_s3 driver) | #24 (Floci), #103 (T102) | The M4 deliverable. |
| **#103** | T102: red tests — flysystem_aws submodule | — | Red contract tests for the `aws_s3` driver. |
| **#153** | Mapping round-trip validation (scheme → aws_s3, write + read) | #156 (T153) | Mirror of Core #150, for the aws_s3 adapter. |
| **#156** | T153: red tests — aws_s3 mapping round-trip | — | |
| **#159** | GD + ImageMagick staging tests (aws_s3 scheme) | #165 (T159) | Mirror of Core #20/#21/#57/#58, against the real aws_s3 adapter. |
| **#165** | T159: red tests — GD + ImageMagick staging with aws_s3 | — | |
| **#160** | Core-scheme remap tests (public/private/assets as remote via aws_s3) | #166 (T160) | Mirror of Core #108/#109/#110, onto the aws_s3 adapter. |
| **#166** | T160: red tests — public/private/assets remapped to aws_s3 | — | |

---

## 3. Dependency graph (M4-relevant)

Edges verified 2026-09-05 via GraphQL `blockedBy`:

- **#24** (Floci integration layer) `blocked_by` #61 (T24) + closed #78/#71/#70/#37/#2/#1.
- **#61** (T24) `blocked_by` all closed — **Ready**.
- **#102** (flysystem_aws) `blocked_by` **#24 (Floci)** + #103 (T102).
- **#103** (T102) `blocked_by` none open.
- **#153** `blocked_by` #156; **#159** `blocked_by` #165; **#160** `blocked_by` #166.
- **#36** (4.0 release) must gate on the submodules shipping (M1 review A4 finding — recompute the
  transitive closure; add #102/#104/#106 edges if not already present).

**Correction applied 2026-09-05 (user-driven):** the Floci layer (#24/#61) was previously renumbered
to M7, leaving M4's Floci-leg untestable. The board now places it **in M4** and wires #102/#104
`blocked_by` #24 — Floci is a prerequisite of the S3 submodules, not a post-M6 afterthought. (The
earlier mis-wiring of #104 `blocked_by #102` was removed.)

The two-ticket dance per `docs/agents/board.md`: each feature starts once its T# is red
("Tests complete, failing" satisfies the blocking edge for starting); both move to Done together when
the tests turn green and are approved. **NO "straight to Done" bypass** — green-at-authoring T#s are
authored as regression pins and gated through the T# review (AGENTS.md rule 12).

---

## 4. Vertical slices (TDD — red test first, then minimal green)

Per `testing.md` §2 (vertical slices, one seam at a time). The seam is the boundary named in
`testing.md` §2; the red test is authored first; only enough code to pass is written. Slice order
follows the dependency chain — **deepest unstarted blocker first** (board.md consumer-chain rule).

### Slice 0 — Floci integration layer (#24/#61) — THE M4 GATE

- **#61 (T24)** — red integration tests against Floci-emulated S3/CloudFront. Done = tests FAIL
  against the current state (no shared Floci test harness exists in the submodule's suite).
- **#24** — the shared Floci test harness the submodules consume: the `aws_s3` endpoint/path-style
  override (#3618527, required for Floci and MinIO) and the Floci test infrastructure (container
  wiring consumed from #71's CI spike + the local DDEV addon). Core keeps no Floci knowledge; the
  harness lives in the submodule's test surface.
- Gate: the `floci-aws` CI job (#71, Done) boots the emulator in the pipeline; the local DDEV addon
  covers local runs.

### Slice 1 — The submodule skeleton + contract red tests (#103)

- The `flysystem_aws` module skeleton: `flysystem_aws.info.yml` (enables independently),
  `drupal/flysystem_aws` composer.json with `league/flysystem-aws-s3-v3` in `require`.
- Red: T102 contract kernel tests — `plugin.manager.flysystem.adapter_driver` discovers `aws_s3`
  when the submodule is enabled; `getConfigKeys()` declares the full preserved config-key contract
  with correct `secret` markers; `buildAdapter()` constructs a working AWS SDK v3 S3 adapter from
  declared config; XOR secret validation fires via the plugin-derived path (#100, no Core constant).

### Slice 2 — The `aws_s3` driver (#102)

- The driver plugin class: plugin ID `aws_s3`, full `getConfigKeys()` (bucket, region, prefix,
  visibility, presigned_expiry, cloudfront.domain, credentials.key/secret/secret_key_id with `secret`
  markers, use_acl), `buildAdapter()` (league/flysystem-aws-s3-v3), TYPE_REMOTE, supportsVisibility
  TRUE, `buildConfigurationForm()`.
- Config schema fragment `flysystem.adapter_config.aws_s3` in the submodule's `config/schema/`.
- The endpoint/path-style override (#3618527) — required for Floci and MinIO.
- Green: the T102 contract tests turn green.

### Slice 3 — S3-specific re-scoped Core halves (#17-split use_acl, #19-split mime, #23-split ETag, #84 ACL-disabled)

- `use_acl` subclassed adapter: off = omit ACLs (modern BucketOwnerEnforced buckets work),
  `visibility()` returns the scheme default (no GetObjectAcl), `setVisibility()` no-ops; on = stock
  ACL behavior. `directory_visibility` forced private (#3616482).
- Stored Content-Type == Drupal `filemime` (#19-split): write path passes the guessed mime.
- S3 ETag checksum (#23-split): the per-scheme checksum API returns the S3 ETag via HeadObject.
- Floci ACL-disabled bucket scenario (#84): prove `use_acl = false` works on a BucketOwnerEnforced
  bucket (any ACL → failure).

### Slice 4 — Validation tickets (mirrors of Core M3 patterns)

- **#153/#156** — mapping round-trip: a scheme configured with the `aws_s3` driver writes and reads
  back a file with its content (the #150 pattern, against the real adapter via Floci).
- **#159/#165** — GD + ImageMagick staging with the `aws_s3` scheme (the #20/#21/#57/#58 pattern:
  realpath FALSE → temporary:// staging → move back through the wrapper; real adapter via Floci).
- **#160/#166** — core-scheme remap onto `aws_s3`: public/private/assets as REMOTE schemes via the
  aws_s3 adapter (the #108/#109/#110 pattern; URL resolution per §4.3, private download route, asset
  routes, fallback on removal).

**Slice order note:** the board's `blocked_by` edges, not this list, are authoritative for
sequencing. This list documents *why* each slice is where it is.

---

## 5. Constraints

- `declare(strict_types=1)` everywhere; full type hints; constructor DI in service classes.
- Cache metadata on all render arrays; English user-facing strings in `$this->t()` (translations
  rule).
- No debug code. PHPStan level 8 clean for new code; PHPCS Drupal standard clean (canonical
  `.ddev/commands/web/phpcs.xml.dist`).
- Never use APIs flagged for removal in 11.4+; `FileExists` enum everywhere (no ints)
  (`architecture.md` §12).
- **No code forward from v3** (`plan-m1.md` §1a binding for M4 as well); planning docs are the sole
  spec source. `flysystem-3.0-ref/` is off-limits as an implementation source.
- **The submodule is the reference contrib-style plugin** — it must prove the contract via the same
  discovery → registration → scheme-mapping → runtime path a third-party contrib adapter uses
  (`adapter-submodules.md` §2.2).
- **Preserved configuration shape, additive-only** (`config-and-upgrade.md` §1, §3): the aws_s3
  settings.php and config-entity shapes survive verbatim; only documented BC breaks (§4 of
  config-and-upgrade.md) apply.
- **No driver knowledge in Core** — everything `aws_s3`-specific lives in the submodule
  (`adapter-submodules.md` §2.1).
- Floci is a **testing emulator ONLY**; production code has zero Floci dependency.
- Core's `drupal/key` deprecations remain deferred to M9 (#149) — not M4 scope.

---

## 6. Test plan summary

- **Contract layer**: Kernel tests against the `aws_s3` driver's adapter (real SDK, no mocks for
  adapter behavior) — discovery, config-key contract, buildAdapter, secret validation, and the
  driver-agnostic rows from `testing.md` §5 (visibility/ACL, mime Content-Type, checksum ETag are
  S3-specific and land here).
- **Integration layer**: Floci-backed Kernel tests — real PUT/GET/HEAD round trips against
  Floci-emulated S3 + CloudFront, visibility/ACL semantics, presigned URL generation,
  `public_url_base`/CloudFront URLs end-to-end, ACL-disabled bucket scenario (#84). Same assertions,
  real adapter (`testing.md` §6).
- **Validation mirrors**: mapping round-trip (#153), GD + ImageMagick staging (#159), core-scheme
  remap (#160) — against the real aws_s3 adapter via Floci.
- Every slice: red → green → (review); no refactoring inside the loop.
- `#[RunTestsInSeparateProcesses]` on Kernel/Functional classes; never on Unit.
- No test asserts implementation details — behavior through seams only.
- Floci runs locally via the DDEV addon and in CI via the `floci-aws` job (#71, Done). ImageMagick
  binaries are installed in the pipeline (`phpunit` before_script).

---

## 7. Verification commands (canonical `.ddev/commands/web/*`)

```bash
ssh web .ddev/commands/web/phpunit     # module suite (contract + Floci legs)
ssh web .ddev/commands/web/phpstan
ssh web .ddev/commands/web/phpcs
# Floci local: the DDEV addon (floci-aws) is running; submodule Floci tests target its endpoint.
# Coverage (on demand, host): ddev test-coverage — requires Xdebug; report at codecov/
```

Note: `floci-check` is submodule-testing; it exercises the Floci emulator through the submodule's
suite. The `phpunit-ostests` (MinIO) leg is object-store scope — verify applicability to the aws_s3
submodule before relying on it.

---

## 8. Milestone exit criterion (rechecked)

`testing.md` §8 M4: **the S3 submodules' contract and Floci integration suites pass** — the `aws_s3`
driver is discovered, configures, builds, validates secrets, and works end-to-end against
Floci-emulated S3 + CloudFront (real PUT/GET/HEAD, visibility/ACL, presigned, CloudFront URLs,
ACL-disabled), plus the validation mirrors (mapping round-trip, GD/ImageMagick staging, core-scheme
remap). M4 is Done when all M4 milestone tickets are closed on the board with review
(#24/#61, #102/#103, #153/#156, #159/#165, #160/#166). Per the milestone-immutability rule
(user, 2026-08-30): once M4 is complete (all tickets worked, approved, Done), it is never revisited
or changed.