# Flysystem v4 — Adapter Plugin Carve-Out Plan

Status: **Draft for review** (2026-08-30). Decision driver: recurring leakage of driver-specific
knowledge into Flysystem Core (documented in `LESSONS_LEARNED.md` as the v3 failure mode; re-surfaced
2026-08-30 in `FlysystemFilesystem::SECRET_XOR_PAIRS`). Companion docs to update: `architecture.md`,
`config-and-upgrade.md`, `testing.md`. This plan supersedes the four-shipped-drivers shape of #78/#89.

---

## 1. The decision (user, 2026-08-30)

**Flysystem Core ships exactly two adapter drivers, built into Core: `in_memory` and `local`.**
The three external-SDK adapters become **optional submodules** shipped with the Flysystem project but
only active when enabled:

| Submodule | SDK | Driver plugin ID | Source adapter docs |
|---|---|---|---|
| `flysystem_aws` | `league/flysystem-aws-s3-v3` | `aws_s3` | https://flysystem.thephpleague.com/docs/adapter/aws-s3-v3/ |
| `flysystem_asyncaws` | `league/flysystem-async-aws-s3` | `s3` | https://flysystem.thephpleague.com/docs/adapter/async-aws-s3/ |
| `flysystem_sftpv3` | `league/flysystem-sftp-v3` | `sftp` | https://flysystem.thephpleague.com/docs/adapter/sftp-v3/ |

**Rationale:** the plugin contract (`AdapterDriverPluginBase`, `AdapterDriverPluginManager`) was built
precisely so Core has zero prior knowledge of any adapter. Every time that contract was bypassed
(`SECRET_XOR_PAIRS`, the Core schema fragments, the SDKs in Core's composer.json), the premise broke:
Flysystem Core had to know about a driver in advance. Physical separation into optionally-enabled
submodules makes the boundary structural rather than conventional — Core cannot reference a driver
that does not exist until its submodule is enabled.

**The proof:** the submodules are themselves the reference implementation of "a contrib module adds an
adapter." They exercise the identical discovery → registration → scheme-mapping → runtime path a
third-party contrib adapter would, so the contract is proven by shipped code, not by promise.

---

## 2. Target architecture

### 2.1 What Flysystem Core contains (after the carve-out)

- **Adapter drivers in `src/Plugin/Flysystem/Adapter/`:**
  - `in_memory` — moved from the test fixture module into Core as a production driver
    (engine `league/flysystem-memory`). REMOTE-type classification preserved (it exercises the
    remote code paths in tests). Config keys: minimal/none.
  - `local` — new production driver (engine `league/flysystem-local`). TYPE_LOCAL, `root` config key
    (required), supportsVisibility TRUE. Real disk.
- **The plugin contract unchanged:** `AdapterDriverPluginBase`, `FlysystemAdapter` attribute,
  `AdapterDriverPluginManager`, dynamic schema `flysystem.adapter_config.[%parent.driver]`.
- **Zero driver knowledge in the entity:** `SECRET_XOR_PAIRS` deleted; secret validation derived at
  runtime from the selected driver's `getConfigKeys()` `secret` markers (see §3).
- **Core schema** (`config/schema/flysystem.schema.yml`) ships only
  `flysystem.adapter_config.in_memory` and `flysystem.adapter_config.local`.
- **Read-only enforcement lives in Core** (§7 of `architecture.md`) — it is a **wrapper around any
  available adapter**, never driver-specific: the configuration form carries a checkbox that sets the
  scheme's `writable` flag; on FALSE, `FilesystemFactory::buildAdapter()` wraps the built adapter in
  `League\Flysystem\ReadOnly\ReadOnlyFilesystemAdapter` **before** `new Filesystem($adapter)` is
  constructed (VERIFIED: `FilesystemFactory.php:421-423` + the form's writable checkbox). Works
  identically for Core drivers and submodule/contrib drivers.
  - **settings.php side (RESOLVED 2026-08-30):** the **existing `writable` flag** (bool, default TRUE,
    preserved 3.0 shape; VERIFIED `FilesystemFactory.php:375`) drives read-only. `writable: false` =
    the adapter is wrapped in `ReadOnlyFilesystemAdapter` (read-only); `writable: true` (default) =
    writable. **No new settings.php flag is added.** This resolves the earlier "additional default-
    FALSE flag" idea (withdrawn 2026-08-30 — the existing flag is the inverse of it).
- **Core composer.json** requires only: `league/flysystem`, `league/flysystem-read-only`,
  `league/flysystem-local`, `league/flysystem-memory`, `drupal/key`, `drush/drush`. The three SDKs
  leave Core's require (see §4 packaging decision).

### 2.2 What each submodule contains

Each submodule is a complete, self-contained Drupal module and its own composer package:

- `flysystem_<x>.info.yml` (its own module, enables independently).
- The driver plugin class in `src/Plugin/Flysystem/Adapter/` — plugin ID, `getConfigKeys()` (full
  config-key declaration with `secret` markers), `buildAdapter()`, `getType()`, `supportsVisibility()`,
  `buildConfigurationForm()`.
- Its own config schema fragment: `config/schema/flysystem_<x>.schema.yml` defining
  `flysystem.adapter_config.<driver_id>`.
- Its own SDK dependency in its own composer.json (`drupal/flysystem_aws`,
  `drupal/flysystem_asyncaws`, `drupal/flysystem_sftpv3` — see §4).
- Its own tests: `tests/src/Kernel` (contract) + `tests/src/Kernel/Floci*` (integration against the
  Floci emulator, sharing the Core-provided Floci infrastructure).
- **No read-only logic** — that lives in Core (§2.1) and wraps whatever adapter is selected.
- **Floci test dependency (testing emulator ONLY):** the submodules' test suites use Floci (DDEV addon
  locally, GitLab CI containers) to exercise the S3 adapters without external network or real AWS.
  Production code has zero Floci dependency. The working GitLab-CI Floci setup is discovered and
  documented by #71 (M7 spike + doc) so any adapter-plugin developer can reuse it.

Per `docs/agents/board.md` (A6 — no T#-dance exemptions), **every feature ticket below is paired
with a red-test ticket (T#)**.

---

## 3. The plugin-derived secret validation (Core fix)

**Problem:** `FlysystemFilesystem::SECRET_XOR_PAIRS` hardcodes `s3`/`aws_s3`/`sftp` secret pairs. A
contrib or submodule driver's secrets bypass the exactly-one-of validation entirely, and Core must
know every driver's secrets in advance.

**Fix:** delete the constant. `FlysystemFilesystem::validate()` resolves the selected driver via
`AdapterDriverPluginManager` and derives the XOR pairs from its `getConfigKeys()`: every config key
flagged `secret: true` pairs with its `*_key_id` counterpart (the convention already declared in
`AdapterDriverPluginBase` §docblock and the existing `_key_id` schema fields). A driver with no
`secret` keys yields no pairs. The entity holds zero driver knowledge — Core and contrib drivers are
treated identically.

Migration of the three shipped secret layouts into their drivers' `getConfigKeys()`:
- `aws_s3` / `s3`: `credentials.secret` ↔ `credentials.secret_key_id`
- `sftp`: `password` ↔ `password_key_id`, `private_key` ↔ `private_key_key_id`,
  `passphrase` ↔ `passphrase_key_id`

---

## 4. Packaging decision (**RESOLVED** — user, 2026-08-30: Option A)

The submodules ship with the Flysystem project. Two viable composer arrangements:

| Option | Composer | Effect |
|---|---|---|
| **A — per-submodule composer.json + separate packages** ✅ | Each submodule is its own `drupal/flysystem_*` composer package with its SDK in `require`; `drupal/flysystem` does **not** require them. | Bare `composer require drupal/flysystem` installs Core only; sites add the submodules they need. Strongest optionality; matches the v2 packaging the v3 drift abandoned. |
| **B — bundled submodules, SDKs in project composer.json** | Submodules live in `modules/`, SDKs stay in the project composer.json `require`. | Single package; SDKs installed even when unused (inert until the submodule is enabled). Simpler packaging, weaker optionality. |

**Decision (user, 2026-08-30): Option A.** Each submodule ships its own composer.json
(`drupal/flysystem_aws`, `drupal/flysystem_asyncaws`, `drupal/flysystem_sftpv3`) with its SDK in
`require`; `drupal/flysystem` does not require the SDKs. Ticket creation proceeds on this basis.

---

## 5. Ticket plan

### 5.1 Re-scoped existing tickets

| Ticket | Current scope | Re-scoped to | Notes |
|---|---|---|---|
| **#78** (M3) | "Shipped adapter drivers (local, s3, aws_s3, sftp)" | **Core adapter drivers (`in_memory`, `local`)** — plugin classes + config forms + Core schema fragments | s3/aws_s3/sftp removed from scope (become submodules). Add: move `in_memory` from test fixture into `src/`; new `local` driver. |
| **#89** (T78) | red tests for the four drivers | red tests for `in_memory` + `local` only | s3/aws_s3/sftp red tests move to the submodule T# tickets. |
| **#17** (M3) | Visibility strategy + `use_acl` (subclassed S3 adapters) | **Core:** scheme-derived visibility + `directory_visibility` private (normalization already in the factory/`AdapterDefinition`). **S3 `use_acl` + subclassed adapters → the S3 submodules.** | Split; the S3-specific half lands in the submodule tickets below. |
| **#19** (M3) | Mime-on-write (stored Content-Type == Drupal `filemime`) | **Core:** write path passes Drupal's guessed mime as adapter config. **S3 Content-Type test → the S3 submodules.** | Mechanism in Core; the S3 observable test lives with the S3 adapter. |
| **#23** (M3) | Checksum API (S3 ETag via HeadObject, streaming MD5 elsewhere) | **Core:** the per-scheme checksum API + streaming MD5. **S3 ETag test → the S3 submodules.** | API surface in Core; S3-specific verification in the submodule. |
| **#24** (M7, renumbered from M4) | Floci integration layer + aws_s3 endpoint override | **Core keeps no Floci infrastructure** (Floci = testing emulator only, and Core knows nothing of it — user decision 2026-08-30). The S3 Floci integration tests → the S3 submodules; the GitLab-CI Floci setup is discovered/documented by the #71 spike. **`aws_s3` endpoint override + aws_s3 Floci tests → `flysystem_aws` submodule.** | |
| **#84** (M3) | Floci ACL-disabled bucket scenario | Fold into the S3 submodules' Floci integration suites | ACL-disabled (BucketOwnerEnforced) is S3-specific; lives with the S3 adapters. |
| **#76** (M1) | AJAX driver-swap on the add form | Unchanged (Core) | Dependency on #78 now means the two Core drivers provide the observable `buildConfigurationForm`. |

### 5.2 New tickets

| Ticket | Milestone | Scope | Blocked by |
|---|---|---|---|
| **Core: Plugin-derived secret validation** (+ T#) | M3 | Delete `SECRET_XOR_PAIRS`; `FlysystemFilesystem::validate()` derives XOR pairs from the driver's `getConfigKeys()` `secret` markers | #4, #74 |
| **Submodule: `flysystem_aws`** (+ T#) | M4 flysystem_aws | `aws_s3` driver plugin + schema + form + tests (contract + Floci) | re-scoped #78, #17-split, #23-split, #19-split, #24-split |
| **Submodule: `flysystem_asyncaws`** (+ T#) | M5 flysystem_asyncaws | `s3` driver plugin + schema + form + tests (contract + Floci) | re-scoped #78, #17-split, #23-split, #19-split |
| **Submodule: `flysystem_sftpv3`** (+ T#) | M6 flysystem_sftpv3 | `sftp` driver plugin + schema + form + tests | re-scoped #78 |
| **Core: Floci infrastructure** (from #24 re-scope — superseded by the Floci-CI spike #71 at M7) | M7 | Shared Floci containers/fixtures/CI wiring consumed by the submodules | #70/#71 |

Each submodule ticket's body must record the full config-key contract (from `config-and-upgrade.md`
§3's preserved shapes — bucket/region/prefix/endpoint/… for s3; visibility/presigned_expiry/
cloudfront/… for aws_s3; host/username/root/password/private_key/… for sftp) so the preserved 3.0
configuration format survives verbatim (additive-only per `config-and-upgrade.md` §1). Each submodule
is its own composer package (`drupal/flysystem_aws`, `drupal/flysystem_asyncaws`,
`drupal/flysystem_sftpv3`) with its SDK in `require`; `drupal/flysystem` does not require the SDKs
(§4, Option A).

---

## 6. Existing-doc updates required by this plan

1. **`architecture.md`**
   - §1 Non-goals: "No support for third-party adapters beyond the four shipped ones" → Core ships
     two; three external-SDK adapters are optional submodules; third-party contrib adapters are the
     community's responsibility (unchanged).
   - §2 Support boundary: reflect the Core-two + three-optional-submodules split; `in_memory` becomes
     a shipped production driver (no longer "test-support fixture only").
   - §11 Adapter plugin contract: add that the three submodules are the reference "contrib-style"
     plugins proving the contract; the entity holds no driver knowledge (secret pairs derived from
     plugin declarations).
   - §15 Open items: resolve adapter-discovery choice as attribute + plugin manager (already chosen in
     `plan-m1.md` §2).
2. **`config-and-upgrade.md`**
   - §2: note that `s3`/`aws_s3`/`sftp` settings.php shapes are preserved verbatim but require the
     corresponding submodule enabled.
   - §3: the Key-module secret map moves from the entity constant into the driver plugins'
     `getConfigKeys()` `secret` markers; format unchanged.
3. **`testing.md`**
   - §1/§5 pain-map: S3-specific rows (visibility/ACL, mime Content-Type, checksum ETag, Floci ACL-
     disabled) now execute in the submodules' suites; Core keeps the driver-agnostic rows.
   - §4: Floci integration suites live in the submodules (shared Core infrastructure).
   - §8 M3/M4 exit criteria: reflect that the S3 adapters are submodule deliverables.

---

## 7. Ticket review record (2026-08-30, board M2+)

Per the project rule — *"if it isn't written down in a persistent format, it does NOT exist"* —
this section records the board review of all tickets from Milestone 2 forward, presented to the user
for approval. **Status: APPLIED 2026-08-30 (user approval).** The following was executed on the
GitHub board/tracker: milestones created and renumbered; new tickets filed; scope edits applied;
#35 reopened with comment-only scope change; dependency edges wired.

### 7.1 Milestones to create — and the renumbered sequence

**Milestone immutability rule (user, 2026-08-30):** the plan is agile and iterative — milestones may be
revisited and changed. The **only hard rule:** once a milestone is complete (all tickets worked,
approved, marked Done), it can **never be revisited or changed**.

The submodule milestones slot between M3 and M4, renumbering the existing M4–M6:

| Sequence | Renamed from | Content |
|---|---|---|
| M0 Setup | — | unchanged |
| M1 Foundation | — | unchanged |
| M2 Contract wrapper | — | unchanged |
| M3 Adapter hardening (Core) | — | `in_memory`/`local` drivers, read-only, Core visibility/mime/checksum/GD-ImageMagick |
| **M4 flysystem_aws** | NEW | AWS SDK v3 submodule (`aws_s3` driver) |
| **M5 flysystem_asyncaws** | NEW | AsyncAws submodule (`s3` driver) |
| **M6 flysystem_sftpv3** | NEW | SFTP v3 submodule (`sftp` driver) |
| M7 Test hardening & CI | **M4 Test hardening** | Floci CI spike (#71), Section-A, contract determinations, D12 matrix |
| M8 Migration | **M5 Migration** | migration submodule |
| M9 Release | **M6 Release** | upgrade guide, 4.0 release |

Consequence: every ticket currently on M4/M5/M6 renumbers to M7/M8/M9 respectively (e.g. #24/#71 →
M7; #28–#33 → M8; #34/#35/#36 → M9). New ticket milestone references below use the new numbering.

### 7.2 New tickets (feature + T# pairs, no T#-dance exemptions)

| Ticket | Milestone | Scope |
|---|---|---|
| Core: Plugin-derived secret validation (+ T#) | M3 | Delete `SECRET_XOR_PAIRS`; derive XOR pairs from driver `getConfigKeys()` `secret` markers. Blocked by #4, #74. |
| Submodule: `flysystem_aws` (+ T#) | M4 flysystem_aws | `aws_s3` driver, schema, form, tests, own composer.json. |
| Submodule: `flysystem_asyncaws` (+ T#) | M5 flysystem_asyncaws | `s3` driver, schema, form, tests, own composer.json. |
| Submodule: `flysystem_sftpv3` (+ T#) | M6 flysystem_sftpv3 | `sftp` driver, schema, form, tests, own composer.json. |

### 7.3 Scope edits (unworked tickets — body edited directly)

| Ticket | Change |
|---|---|
| #78 | Re-scope to Core drivers only: `in_memory` (moved from test fixture into `src/`) + `local`. Remove `s3`/`aws_s3`/`sftp`. |
| #89 (T78) | Red tests for `in_memory` + `local` only. |
| #17 | Split: Core keeps scheme-derived visibility + `directory_visibility` private; S3 `use_acl`/subclassed-adapter portion → S3 submodules. |
| #18 | Stays Core; read-only uses the **existing `writable` flag** (settings.php bool, default TRUE; `false` = read-only wrapper) — no new flag. |
| #19 | Split: Core passes Drupal's guessed mime to the adapter; S3 stored-Content-Type test → S3 submodules. |
| #23 | Split: Core checksum API + streaming MD5; S3 ETag test → S3 submodules. |
| #24 | Split: Core keeps Floci infrastructure; `aws_s3` endpoint override + S3 Floci tests → `flysystem_aws`. |
| #71 | **Spike + documentation ticket.** Figure out how to set up Floci for the GitLab CI testing pipeline (no "Floci implementation" reference document exists — must be discovered empirically), then **document the working setup** so any developer creating an adapter plugin with Floci emulator support can build it into their own testing process. Stays M7 (renumbered from M4). |
| #84 | ACL-disabled (BucketOwnerEnforced) scenario → S3 submodules' Floci suites. |
| #82, #28–#33 | Add dependency note: migration *to S3* requires the relevant submodule enabled. |
| #34 | Upgrade guide documents the submodule split, the three composer packages, and the read-only behavior via the existing `writable` flag (`false` = read-only). |
| #36 | 4.0 release includes the three submodule packages. |

### 7.4 Reopen + comment (worked, closed tickets)

| Ticket | Change |
|---|---|
| #35 | **Reopen** (M9, renumbered from M6 — not completed) — scope changes in **comments only**; original description remains intact. Annotated reference adapter becomes `in_memory`/`local` (Core); submodules are the contrib-style references. |

### 7.5 Unchanged (verified no carve-out impact)

#13–#16, #73, #80, #81, #98, #99 (M2); #20, #21, #22, #76 (M3); #26, #27, #83, #72 (M7, renumbered from M4); #25 (closed). No M0/M1 tickets are touched by this change-set.

---

## 8. Open items / decisions

1. **Packaging — RESOLVED** (Option A, per-submodule composer packages; §4).
2. **`in_memory` REMOTE classification as a production driver** — preserved for now (it is what makes
   it a good contract test vehicle); confirm acceptable for a shipped driver.
3. **Read-only flag — RESOLVED (user, 2026-08-30):** use the existing `writable` flag in
   settings.php (bool, default TRUE). `writable: false` = read-only (ReadOnlyFilesystemAdapter
   wrapper); `writable: true` (default) = writable. No new settings.php key; no precedence question —
   the earlier "additional default-FALSE read-only flag" idea was withdrawn. Entity-side checkbox sets
   the same underlying flag.
3. **Floci-check failure (2026-08-30, open)** — the local Floci round-trip check is failing
   (anonymous PUT denied under the current `FLOCI_SERVICES_S3_ENFORCE_AUTH` setting). Must be resolved
   before the submodule Floci integration suites can run locally; investigation status:
   [INVESTIGATION OPEN — pending user direction].
4. **Floci GitLab CI (#71, M7)** — the submodules' integration suites need the Floci containers in CI;
   confirm #71 covers submodule test paths.

---

## 8. Review gate

No tickets are created until the user has reviewed this plan and asked any questions. Ticket
creation, board wiring (`blocked_by` edges), and doc edits all follow the dry-run protocol in
`docs/agents/board.md`.