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

**Document status (2026-09-08, CLOSED):** M4 complete — 0 open issues, 59 closed in milestone #15 (verified via milestone issue list). Exit criterion met: the `aws_s3` adapter is discovered, configures, builds, validates secrets, and works end-to-end against Floci-emulated S3 (real PUT/GET/HEAD, visibility/ACL-shape handling, presigned, public_url_base + CloudFront URLs), plus all validation mirrors green. Documented exclusions (not defects): end-to-end ACL-enforcement proof waits on an enforcing backend (M9 retrospective #243); the asyncaws half of the ACL scenario lives in M5 (#245/#246). Per the milestone-immutability rule this document is now frozen; corrections live in later milestones, never here.

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

## 2. Execution status (2026-09-08, FINAL)

M4 gate status: **COMPLETE — all milestone tickets closed with review** (0 open / 59 closed, verified). The slices below all landed, including scope folded in during execution (see §9 closing record for the audit trail).

### 2.1 Done (all)

| Ticket(s) | What it is |
|---|---|
| **#24 / #61** | Floci integration layer + endpoint override + integration reds (incl. CloudFront leg). |
| **#102 / #103** | flysystem_aws submodule + aws_s3 driver contract. |
| **#213 / #214** | settings.php config for aws_s3 (incl. presigned + CloudFront URL wiring in Core `getExternalUrl()`, precedence presigned > base > CloudFront). |
| **#219 / #220 / #221** | aws_s3 config form plugin + save validation. |
| **#222 / #223, #230 / #231, #232 / #233** | Settings.php precedence, adapter-swap precedence, misconfiguration reporting. |
| **#224 / #225** | Floci IAM buckets (public/private + `noacl` existence) + IAM reds (trimmed to achievable scope). |
| **#234 / #235** | IAM-conflict detection (LoggingFilesystem reactive catch + base-over-private hook check) + reds. |
| **#236 / #240** | use_acl subclassed adapter + mock-handler reds. |
| **#237 / #239** | mime-on-write verification (wrapper injection proven). |
| **#238 / #242** | ETag checksum verification (inherited, proven through subclass path). |
| **#153 / #156** | Mapping round-trip, entity-half proof (settings half pre-proven). |
| **#159 / #165** | GD + ImageMagick staging mirrors. |
| **#160 / #166** | Core-scheme remap (registration-order fix + stat writability + moveUploadedFile streaming fallback). |
| **#171 – #194** | Core corrections C1/H1/C2/H2/H3/M2/M3/M4/M7/H4 + T# partners (incl. #177/#178 transferContent streaming). |
| **#84 / #241** | ACL-disabled scenario disposition (wire + wiring proof; E2E parked on #243). |
| **#244** | README settings.php reference. |

### 2.2 In flight

*(none — milestone complete.)*

### 2.3 Open, not started

*(none — all milestone tickets closed. The pre-close snapshot below is retained for the audit trail; §§3–4 describe the executed order.)*

| Ticket | What it was at last snapshot | Notes |
|---|---|---|
| **#61 / #213 / #214** | Floci remaining scope + settings.php pair | Closed: #214 reds → #213 implementation (incl. CloudFront wiring) → #61 remaining scope. |
| **#224 / #225** | Floci IAM buckets | Closed: public/private + `noacl` existence; IAM reds trimmed to achievable scope. |
| **#153 / #156, #159 / #165, #160 / #166** | Validation mirrors | Closed: entity-half mapping proof; staging mirrors; remap (registration-order + stat fixes). |
| **#102 / #103** | Submodule + driver | Closed earlier in the milestone. |

### 2.3a Core corrections + M4-sequenced Core work (from the M3 code review)

Filed 2026-09-05 from `planning/m3-code-review.md`. M3 is complete and immutable; these are new M4
tickets that cite the M3 issues they correct (governance note in the review). Every feature ticket
has its T# partner (AGENTS.md rule 12). The deferred (non-blocking) fixes from the same review sit in
M7 (#195–#206) and M8 (#207/#208, L1 — drush packaging, needs-human, user decides later in the project).

| Ticket | What it is | Blocked by | Blocks |
|---|---|---|---|
| **#172** (C1) | url_stat() returns FALSE for missing objects | #171 (TC1) | #61 |
| **#174** (H1) | stat-cache invalidation on owned-scheme mutations | #173 (TH1) | #61 |
| **#176** (C2) | copy()/move() return the resolved destination URI | #175 (TC2) | #159, #160 |
| **#178** (H2) | stream transferContent() (no whole-file buffering) | #177 (TH2) | #159 |
| **#180** (H3) | remove s3/aws_s3/sftp schema fragments from Core | #179 (TH3) | #102 |
| **#182** (M2) | private download: scheme in URL + prefix strip | #181 (TM2) | #102 |
| **#184** (M3) | presigned_expiry requires public_url_base + signing seam | #183 (TM3) | #102 |
| **#186** (M4) | assertRequiredConfig() on AdapterDriverPluginBase | #185 (TM4) | #102 |
| **#188** (M7) | Test connection AJAX on FlysystemFilesystemForm | #187 (TM7) | #102 |
| **#190/#192/#194** (H4) | stream_metadata (chmod→visibility+touch) / realpath (LOCAL) / stream_lock (LOCAL flock) — implemented per the core `LocalStream` contract (§4.1/§6) | #189/#191/#193 | — |

---

## 3. Dependency graph (M4-relevant)

Edges verified 2026-09-05 via GraphQL `blockedBy`:

- **#24** (Floci integration layer) `blocked_by` #61 (T24) + closed #78/#71/#70/#37/#2/#1.
- **#61** (T24) `blocked_by` **#172 (C1)** + **#174 (H1)** + closed — the Floci integration tests need truthful stat semantics (C1) and post-write invalidation (H1).
- **#102** (flysystem_aws) `blocked_by` **#24 (Floci)** + #103 (T102) + **#180 (H3), #182 (M2), #184 (M3), #186 (M4), #188 (M7)**.
- **#103** (T102) `blocked_by` **#24 (Floci)** + closed (#100/#23/#19/#17/#78) — startable once #24 starts.
- **#153** `blocked_by` #156 + **#102**; **#159** `blocked_by` #165 + **#102** + **#176 (C2)** + **#178 (H2)**; **#160** `blocked_by` #166 + **#102** + **#176 (C2)**.
- **#36** (4.0 release) must gate on the submodules shipping (M1 review A4 finding); the #102/#104/#106 edges are present.

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

### Slice -1 — Core corrections (M3 code review, M4 milestone) — before the gate

C1 (#172/#171), H1 (#174/#173), C2 (#176/#175), H2 (#178/#177), H3 (#180/#179), plus the
M4-sequenced Core work M2 (#182/#181), M3 (#184/#183), M4 (#186/#185), M7 (#188/#187). These unblock
#61 and #102 (see §3). Each is a TDD two-ticket dance with full local QA. H4
(#189–#194) is implementation scope grounded in core `LocalStream`
(`web/core/lib/Drupal/Core/StreamWrapper/LocalStream.php`) + architecture §4.1/§6:
`stream_metadata` chmod→visibility and touch, `realpath()` for LOCAL schemes,
`stream_lock()` flock for LOCAL schemes (FALSE stays the honest remote value).

### Slice 0 — Floci integration layer (#24/#61) — THE M4 GATE

- **#61 (T24)** — red integration tests against Floci-emulated S3/CloudFront. Done = tests FAIL
  against the current state (no shared Floci test harness exists in the submodule's suite).
- **#24** — the shared Floci test harness the submodules consume: the `aws_s3` endpoint/path-style
  override (#3618527, required for Floci and MinIO) and the Floci test infrastructure (container
  wiring consumed from #71's CI spike + the local DDEV addon). Core keeps no Floci knowledge; the
  harness lives in the submodule's test surface.
- Gate: the `phpunit` CI job carries the emulator as a `floci-aws` service
  (the standalone `floci-aws` smoke job from #71 only proves the emulator
  boots); the local DDEV addon covers local runs.

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
- Floci runs locally via the DDEV addon and in CI via the `floci-aws` service
  attached to the `phpunit` job (#24; #71 proved the emulator boots). ImageMagick
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
remap). M4 is Done when all M4 milestone tickets are closed on the board with review — the Core
corrections and M4-sequenced Core work (#171–#194), the Floci gate (#24/#61), the submodule
(#102/#103), and the validation mirrors (#153/#156, #159/#165, #160/#166). Per the milestone-immutability rule
(user, 2026-08-30): once M4 is complete (all tickets worked, approved, Done), it is never revisited
or changed.

---

## 9. Closing record 2026-09-08 (supersedes all prior handoffs; document frozen)

Execution order as worked: #214 reds → #213 (+ CloudFront wiring) → #61 remaining scope → #224/#225 (IAM + `noacl` existence) → #234/#235 (conflict layer) → #236/#240 (subclass + mocks) → #237/#239 (mime) → #238/#242 (ETag) → #153/#156 (entity mapping) → #177/#178 (transferContent streaming) → #159/#165 (staging) → #160/#166 (remap: registration order + stat writability + moveUploadedFile fallback) → #84/#241 (scenario disposition) → #244 (README). M4 audit tickets #245/#246 filed for M5; spec amendments posted on M5 #105/#216.

Scope folded in during execution (all on ticket records with user approval): CloudFront URL branch + precedence; stat uid/euid + read-only write-bit stripping; `moveUploadedFile` streaming fallback for remote URIs; `LoggingFilesystem` reactive catch + base-over-private hook check; transferContent streaming; `noacl` existence-only provisioning; mock-handler strategy where Floci cannot discriminate (ACL-disabled, signature verification — parked on M9 #243 with upstream-filing trigger).

Standing corrections (user directives, see `LESSONS_LEARNED.md`): tests measure, never provision; green ≠ scope complete (open `blocked_by` = not done); phpunit scoped locally with `SIMPLETEST_DB=mysql://db:db@db/test`; canonical configs only, actual output pasted; one ticket delivered at a time.

CI design (settled): phpunit job provisions `public`/`private`/`noacl` + public-read policy + auth-enforcement flag in `before_script` via inline zero-`$` SDK lines (byte-for-byte what runs; `yaml_parse_file` gate after every edit).