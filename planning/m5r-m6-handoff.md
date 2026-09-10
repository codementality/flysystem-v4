# M5R + M6 — Handoff

Draft, 2026-09-10. Nothing filed, posted, or committed. Every item awaits the user's go.

Full reasoning lives in `planning/m5-code-review.md` and `planning/m5-project-review.md`. This document is
the action list only.

- **Section A — M5R** → milestone **18**. Source: the M5 reviews. `plan-m5.md` is **frozen** — corrections go
  on ticket records only.
- **Section B — M6** → milestone **17**. Source: a review of `plan-m6.md`. That document is **live and
  unstarted** — edit it directly.

**Rules for every item below:** T# reds → In review → user approval → implementation → joint close. No docs
exception. Run the `Refute:` check before filing. Paste output; assert nothing unrun.

---

# SECTION A — M5R (milestone 18)

## A.0 — Correcting comments (do these first: no code, stops false claims in the tracker)

- **A.0.1 → #270** — IAM detection does not function under the credential model shipped in the same milestone.
  - Probe reads `credentials.key`/`secret` only; never `secret_key_id`.
  - #250's `preSave()` strips `credentials.secret` from stored config → probe client is unauthenticated.
  - 403 → `detectConflicts()` catches → `[]` → status report shows "no conflicts" regardless of bucket state.
  - Worse than no feature: manufactured evidence of safety.
  - Also record (rule 11): #269's legs replace the factory with `MockHandler` and cannot cover credential
    construction. Testability policy requires a mocked leg to name its unmocked counterpart; that did not happen.
  - Refs: code review C2/M2/M3, project review P1.

- **A.0.2 → #216 and #215** — the probe's finding never left the test docblock.
  - Probe measured: AsyncAws signs with no `presigned_expiry` key configured.
  - Consequence: driver declares no key, schema rejects it, form omits it — but the wrapper honors it from
    settings.php. Reachable from one seam, rejected by the other, absent from plan §1.
  - GAP PROTOCOL stopped at step zero: a docblock is not the persistent record.
  - Refs: code review H4, project review P2/P5.

## A.1 — IAM probe resolves credentials through the driver — CRITICAL *(verified)* — **blocks M6**

- **Refute:** form-saved scheme still has `config.credentials.secret` →
  `var_dump($e->get('config')['credentials']['secret'] ?? 'ABSENT');`
- **T# `TA1`** (`seam:adapter-plugin`) — against the **real** factory, not the mock override:
  - Leg 1: `key` + valid `secret_key_id`, no literal secret → probe client carries resolved credentials. *Fails
    today: factory never reads `secret_key_id`.*
  - Leg 2: unresolvable credentials → result marked **undetermined**, not empty conflicts. *Fails today: no
    undetermined state exists.*
  - Leg 3: existing mock-driven verdict legs still pass. *Green pin — locks the boundary the refactor must not
    cross. Flag as such.*
- **Impl `A1`** (`blocked_by` TA1):
  - Add `buildClient(array $config): S3Client` to the driver; used by **both** `buildAdapter()` and
    `BucketIamProbeFactory`. One resolution point (fixes M2).
  - Change `detectConflicts()` to return `['conflicts' => [], 'determined' => bool]` or a value object (fixes M3).
  - Add an **informational** (not warning) requirements entry when undetermined: "grant
    s3:GetBucketPolicyStatus and s3:GetBucketOwnershipControls, or ignore."

## A.2 — Guard the adapter-build path — CRITICAL *(verified)* — **blocks M6**

- **Refute:** something catches `InvalidArgumentException` between `getExternalUrl()` and `FileUrlGenerator`.
  (Scope note: `stream_open()` and `openReadStream()` **are** already guarded.)
- **T# `TA2`** (`seam:stream-wrapper`):
  - Leg 1: unresolvable `secret_key_id` → `getAdapter()` returns `MisconfiguredFilesystemAdapter` + logs, does
    not throw. *Fails today: uncaught throw.*
  - Leg 2: presigned scheme in that state → `getExternalUrl()` returns `''` and reports. *Fails today.*
  - Leg 3: working scheme still builds its real adapter. *Green pin.*
- **Impl `A2`** (`blocked_by` TA2):
  - Wrap `buildAdapter()` in `getAdapter()` with a `\Throwable` catch → log → return
    `MisconfiguredFilesystemAdapter`.
  - Extend that class to carry a reason string alongside missing keys.
  - Move `getFilesystem()` inside `getExternalUrl()`'s guarded region, or wrap the presigned branch.
  - **Keep the driver throws** — right signal, wrong missing boundary above them.

## A.3 — `use_provider_key_management` read before credentials resolve — HIGH *(reviewed)* — **blocks M6**

- **Refute:** run the sequence — fill credentials → check the box → save → inspect the entity. Settles in one pass.
- **T# `TA3`** (`seam:adapter-plugin`):
  - Leg 1: flag TRUE + valid `secret_key_id` → client built with no static credentials. *Fails today: key-id
    branch preempts the flag.*
  - Leg 2: saving with the box checked leaves no `credentials.secret_key_id` stored. *Fails today: `#states` is
    client-side only.*
  - Leg 3: flag off + valid reference → resolution still works. *Green pin over #248.*
- **Impl `A3`** (`blocked_by` TA3):
  - Read the flag first; return `NULL` immediately when TRUE. **Both drivers.**
  - Unset the credentials sub-tree on save when the flag is on — same server-side gating #252 used for
    `presigned_expiry`.

## A.4 — Permission-gate the onscreen misconfiguration warning — HIGH *(verified)* — **blocks M6**

- **Refute:** an outer layer suppresses messenger output for anonymous users. (It does not.)
- **T# `TA4`** (`seam:service-api`):
  - Leg 1: anonymous request triggering the failure → **no** messenger message. *Fails today: unconditional.*
  - Leg 2: same request still writes watchdog. *Guards against fixing this by deleting reporting.*
  - Leg 3: admin request still sees the message. *Green pin over #280.*
- **Impl `A4`** (`blocked_by` TA4): gate on `administer flysystem` (or `access site reports`); watchdog stays
  unconditional.
- *Record: this ticket came from my M4 handoff §2.11, which specified the dedupe and never said "gate by
  permission." Partly the review's gap.*

## A.5 — Cache and bound the IAM probe — HIGH *(verified)*

- **Refute:** Drupal 11.4 caches `hook_runtime_requirements` upstream. Check the status-report controller.
- **Note:** today these calls mostly 403 fast, masking cost. Fixing A.1 makes them work — and slow.
- **T# `TA5`** (`seam:integrations`) — assert **counts**, not presence:
  - Leg 1: two `runtime()` calls, same scheme → probe API calls issued **once**.
  - Leg 2: saving the config entity invalidates the cached verdict.
  - Leg 3: probe client built with explicit low timeout and zero retries.
- **Impl `A5`** (`blocked_by` TA5):
  - Cache verdict per scheme, keyed on config hash, hours-scale TTL, invalidated on entity save.
  - Memoize within the request as a floor.
  - Explicit low `http` timeout + `retries => 0`.
  - **Decide and record:** keep the probe on the requirements path, or move it to the connection-test button plus
    a cron-warmed cache.

## A.6 — Presigned for `s3`: decide, then align the seams — HIGH *(verified)*

- **Refute:** entity validation already rejects `presigned_expiry` for `s3`. (Unlikely —
  `driverSupportsTemporaryUrls()` returns TRUE for `s3`.)
- **Decision required before authoring the T#:**
  - **(a) Support it** — declare the key + schema + form field, matching `aws_s3` including #252's public-scheme
    gating. Amend `plan-m6.md` to record the scope change.
  - **(b) Reject it** — entity validation refuses it; requirements warning when a settings.php `s3` scheme sets it.
- **T# `TA6`** (`seam:url-generation`): one leg per seam (settings.php, config entity) asserting the **same**
  outcome, plus a config-schema validation leg.
  - Under (a) the entity-seam legs red; under (b) the settings.php leg reds. Either way at least one fails today.

## A.7 — Scrub query-string credentials from logs — MEDIUM *(reviewed)*

- **Refute — run this first:** trigger a failure against Floci with a bad secret on a presigned path; paste the
  logged message. If it never quotes a signed URI, close the item.
- **T# `TA7`** (`seam:integrations`): one leg per pattern — `X-Amz-Credential`, `X-Amz-Signature`,
  `X-Amz-Security-Token` — using a **captured** message shape, not a synthetic one. *All fail today: the regex is
  XML-element-anchored.*
- **Impl `A7`** (`blocked_by` TA7): add the query-parameter patterns. **Consider inverting to an allowlist** (keep
  error code + reason, drop the rest) — a denylist over vendor strings needs revisiting every SDK upgrade. Record
  which and why.

## A.8 — `sendChunkedBody` default — LOW, decision only *(verified)*

- SDK default is `'false'`; driver declares `TRUE` → shipped default is the value that fails on MinIO/LocalStack/Floci.
- Transmission itself is correct both ways — M4's H3 does **not** recur.
- **Decide:** flip the default to `FALSE`, or keep `TRUE` and say so in the form description and README ("on by
  default; turn off for any non-AWS endpoint").
- File a small pair only if the default changes.

## A.9 — Milestone 18 entry criteria — LOW

- Add to the milestone description:
  - CRITICAL/HIGH that M6 would inherit → M5R, blocks M6's start.
  - MEDIUM/LOW → M6 or later by judgment.
  - Needs an absent capability → M9, reason recorded on the ticket.

## A.10 — Milestone integration pass — add to `plan-m6.md` §3

- M5 proved per-ticket discipline works (45 tickets, 21/21 paired, zero open blockers). Every remaining defect is
  *between* tickets, which no per-ticket gate sees.
- Proposed constraint:
  > **Milestone integration pass (required before a milestone may close).** List every config key, service and
  > seam that more than one pair in this milestone touched. For each, name one leg exercising the **combination**,
  > not the pairs separately. The milestone closes only when that list is empty or every entry has its leg.
- For M5 that list was one line — `credentials.*` (#248, #250, #270, #276) — and it would have caught the only
  CRITICAL.

---

# SECTION B — M6 plan gaps (milestone 17)

`plan-m6.md` is live and M6 is unstarted. **These are edits to that document**, made before the first ticket is
worked. B.1 and B.2 also need new pairs that do not exist among M6's current fourteen tickets.

## B.1 — `host_fingerprint` has no consumer and no leg — CRITICAL *(verified)*

- League **fails open**: `SftpConnectionProvider.php:111-114` — `if (!$this->hostFingerprint) { return; }`. No
  fingerprint configured ⇒ no host-key verification at all.
- §1 lists the key; §4 names no leg; nothing states fail-closed policy.
- This is M4's C1 pattern (declared everywhere, consumed nowhere) aimed at the one key where non-consumption is a
  MITM exposure, not a config annoyance.
- **Refute:** phpseclib validates the host key upstream. (`SFTP::login()` does not, by default.)
- **Amend `plan-m6.md`:**
  - §1 key line: "`host_fingerprint` — read by `SftpV3AdapterDriver::buildAdapter()` into
    `SftpConnectionProvider`'s `hostFingerprint`; proven by a mismatched-fingerprint leg asserting
    `UnableToEstablishAuthenticityOfHost`."
  - §1/§4: record the fail-closed decision. **Recommended:** absent fingerprint → `hook_runtime_requirements`
    **warning** (not hard failure — that breaks every v3 site on upgrade); form marks the field strongly
    recommended with the reason.
- **New pair `T-B1 / B1`** — authored with #106/#107:
  - Leg 1: matching fingerprint connects.
  - Leg 2: mismatched fingerprint throws.
  - Leg 3: absent fingerprint connects **and** raises the requirements warning.
  - All three are genuine forward reds (no driver exists yet).

## B.2 — Core forces `directory_visibility` private for every driver → 0700 on SFTP — HIGH *(reviewed)*

- `FilesystemFactory.php:413` — `Config::OPTION_DIRECTORY_VISIBILITY => Visibility::PRIVATE`, no driver branch.
- `PortableVisibilityConverter.php:16` — `directoryPrivate = 0700`.
- Rationale is S3-specific (#3616482: S3's default directory ACL is public). Does not transfer to POSIX.
- Effect on an SFTP root served via `public_url_base`: every created directory is owner-only, web server (different
  uid) cannot traverse, **every public file 403s** — while files are 0644 and look correct. Presents as "uploads
  work, images broken."
- First case where a Core decision made for one driver actively harms another.
- **Refute:** the league SFTP adapter overrides directory permissions independently. Check
  `SftpAdapter::createDirectory()` and its converter wiring.
- **Amend `plan-m6.md`:** §1 scope line — "resolve the Core-level forced `directory_visibility` for POSIX-backed
  drivers." §4 — leg asserting a public sftp scheme's directories are traversable by a non-owner.
- **New pair `T-B2 / B2`:**
  - Driver declares its directory-visibility policy (method on `AdapterDriverPluginBase`, defaulting to current
    forced-private; `sftp` overrides to follow scheme visibility).
  - **Regression guard required:** leg pinning that `aws_s3` and `s3` still force private — that is a live security
    control.

## B.3 — §1's key list names no consumers or legs — HIGH *(verified)*

- §3 carries the rule ("every config-key line names its consuming code path and its proving leg"); §1 of the same
  document is a bare enumeration.
- Exact precondition that produced M4's C1 and H3 — in a plan written *after* the rule was adopted to prevent it.
- Highest-risk keys on non-consumption: `host_fingerprint` (B.1), `use_agent` (silent fallback = C1's shape), the
  three `*_key_id` secrets (C1's shape, tripled).
- **Refute:** consumers are named on #106/#107's ticket bodies → then the fix is to reference the tickets from §1.
- **Amend `plan-m6.md` §1** before #107 is worked: one line per key, naming consumer + proving leg. Where the
  consumer is "league passes it through to phpseclib," say that and name the pass-through leg. **A key that cannot
  name a leg is not ready to be declared.**

## B.4 — M5R gate is prose only, no edge — MEDIUM *(verified)*

- §5 says M5R precedes M6. §2.1 shows #107/#211/#212 with no blockers; §2.2 starts with them.
- A.1–A.4 change the exact code #106 will pattern itself on (credential resolver, adapter-build boundary,
  provider-KMS ordering). Writing #106 first inherits three known defects into a third driver — how M4's defects
  reached M5's probe factory.
- **Actions:**
  - Add A.1–A.4 impl tickets as `blocked_by` on **#106 only** — not #107/#211/#212 (reds and the service container
    are genuinely independent).
  - Correct §2.2's work order to show #106 gated on M5R.
  - Move **#212 Backlog → Ready** — no blockers, and the plan's own hygiene note already says so.

## B.5 — No stated behavior when the SFTP host is unreachable — MEDIUM *(reviewed)*

- §1 lists `timeout` and `max_tries`; §3/§4 silent on render-path behavior.
- Bounded already by `FilesystemFactory`'s per-request adapter memo (one connection attempt per scheme per
  request) — so **not** M5's H1.
- Residual: an unreachable host stalls the first operation for `timeout × max_tries` on every request, including
  anonymous renders, with no stated ceiling.
- **Refute:** league's `SftpConnectionProvider` sets a low default timeout → drops to LOW.
- **Amend `plan-m6.md` §1/§4:** state shipped defaults and rationale (render-path budget in low single-digit
  seconds, not the library default) + one leg asserting degradation within budget. **Fold into #217/#218** — no
  new pair.

## B.6 — `public_url_base` mandatory for public `sftp`, unstated — LOW *(verified)*

- No driver-native URL, no presigned fallback. §1 omits the key entirely; §4 mentions it as though it were one of
  two options.
- Runtime is already correct — the generic C9/#136 requirements entry catches it. Gap is documentary.
- **Amend §1:** one sentence — "a public `sftp` scheme requires `public_url_base`; there is no driver-native URL
  and no presigned fallback." No ticket.

---

# Filing order

Each step is a separate authorization.

1. **A.0.1, A.0.2** — correcting comments.
2. **A.6 + A.8 decisions** — both change what gets filed.
3. **B.1, B.2, B.3, B.5, B.6** — edit `plan-m6.md`. Cheapest moment these are ever fixable.
4. **B.4** — wire M5R → #106 edges; fix §2.2; move #212 to Ready.
5. **A.1 → A.2 → A.3 → A.4** — the M6-blocking pairs, in that order (A.1 first).
6. **B.1 and B.2 new pairs** — alongside #106/#107, once the plan amendments land.
7. **A.5, A.7, A.9, A.10.**
8. **A.6 implementation** once its decision is recorded.

# Guardrails

- `plan-m4.md` and `plan-m5.md` are **frozen**. `plan-m6.md` is **not** — Section B's fixes belong in that document.
- No ticket is worked without being in "In progress." Filing ≠ authorization to work.
- Never approve your own work.
- **`*(reviewed)*`, not verified: A.3, A.7, B.2, B.5.** Run their `Refute:` checks first — A.7's probe and A.3's
  save-sequence each settle in one pass and may close the item.
- Paste output. Assert nothing unrun.
