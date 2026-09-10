# M4 Corrections — Handoff for the Implementing Agent

Status: Draft for review, 2026-09-08. Source: `planning/m4-code-review.md` (findings C1–C3, H1–H4,
M1–M7, L1–L3) and `planning/m4-project-review.md` (findings P1–P7). Nothing in this document has been
filed, posted, or committed. Every item is a **proposal awaiting the user's go**.

## 0. How to use this document

You are being handed a review's findings, not instructions to execute. For each item below:

1. **Verify it yourself first.** Every finding carries a `Verified by` line (the exact command or
   file:line) and a **`Refuted if`** line stating what evidence would overturn it. Run the check.
   `*(verified)*` findings were executed by the reviewer; `*(reviewed)*` findings were read from source
   and not run — those are where a refutation is most likely and most valuable.
2. **If it holds:** the ticket drafts in §2 are ready to file. Do not paraphrase the discrimination
   statements — they are the red-first gate evidence (AGENTS.md rule 12).
3. **If it does not hold:** post the refuting evidence as a comment on the relevant M4 ticket and say
   so in your handoff back. A refuted finding is a good outcome, not a failure — but it must be refuted
   with pasted output, not with reasoning.
4. **Do not act on §1 or §2 without the user's explicit go for that specific item.** Present → stop →
   wait. Filing eleven ticket pairs is eleven authorizations, not one.

**Hard constraints that apply to everything here:**

- `planning/plan-m4.md` is **frozen** (milestone-immutability rule). No item below amends it.
  Corrections live in the M5+ ticket records and in `planning/plan-m5.md`.
- **Never remove or edit prior ticket notes.** All corrections are subsequent comments (rule 10).
- Every implementation ticket gets a T# partner. There is no docs exception — P1 is what the docs
  exception cost.
- **Red-first delivery gate:** no test file reaches In review without at least one leg failing on
  current code. Each T# draft below states which leg fails and on what. If you cannot make it fail,
  that is a signal the finding is wrong — go to step 4.
- Milestone targets: M5 = `flysystem_asyncaws` (#16), M7 = Test hardening & CI (#12), M8 = Migration
  (#13), M9 = Release (#14).

---

## 1. Correcting comments to post on closed M4 tickets

These are **comments only** — the tickets stay closed. Rule 11: if it is not written on the record, it
does not exist. Post verbatim; they are drafted to be self-contained for a future reader who has no
access to this document.

### 1.1 — On #234 ("Core: adapter config conflicts with bucket IAM — UI warning + logged conflict")

> **Correction from the independent M4 code review (2026-09-08) — this ticket's title overstates what
> shipped.**
>
> VERIFIED: the delivered code performs no IAM introspection. There are zero calls to
> `GetBucketPolicy`, `GetBucketPolicyStatus`, `GetBucketAcl`, or `GetBucketOwnershipControls` anywhere
> in production code:
>
> ```
> $ grep -rn "GetBucketPolicy\|GetBucketAcl\|getBucketAcl\|PolicyStatus\|ObjectOwnership" \
>     --include="*.php" src/ modules/ | grep -v tests
> (no output)
> ```
>
> What actually shipped, and it is useful:
> 1. `LoggingFilesystem::logFailure()` (`src/Flysystem/LoggingFilesystem.php:222-236`) — logs **every**
>    failed data-plane operation with the adapter's exception message. This is generic failure
>    reporting: it cannot distinguish an IAM refusal from a typo'd bucket, a network error, or a
>    missing object.
> 2. `FlysystemRequirements::runtime()` (`src/Hook/FlysystemRequirements.php:44-50`) — the
>    "base-over-private" check, comparing two Drupal config values (`visibility === 'private'` plus a
>    non-NULL `public_url_base`). It never contacts S3.
>
> Neither reads bucket IAM state, so the capability this ticket's title asserts — detecting a conflict
> between adapter config and bucket IAM — does not exist in v4 as of M4 close. `plan-m4.md` §2.1
> records the substitution accurately in parentheses; the title was never corrected, and the title is
> what a future reader greps.
>
> This matters because the issue tracker is the source of truth (AGENTS.md rule 4). Left as-is, this
> closed ticket will be cited in M9 release notes and in the drupal.org issue queue as evidence of a
> feature that is not present.
>
> DECISION NEEDED from the user, recorded here rather than in chat: either (a) file an M5+ ticket pair
> implementing real detection — a `GetBucketPolicyStatus` / `GetBucketOwnershipControls` probe on the
> connection-test path and in `hook_runtime_requirements`, comparing the bucket's actual public-access
> and ACL-enforcement state against the scheme's `default_visibility` and `use_acl` — citing this
> ticket as the one it corrects; or (b) record the descope explicitly and rename this ticket and its
> surfaces to describe failure logging plus a config-internal consistency check. Per the
> milestone-immutability rule, `plan-m4.md` is not amended either way.
>
> Cross-reference: `planning/m4-code-review.md` finding H1; `planning/m4-project-review.md` finding P4.

### 1.2 — On #235 ("T234: Write failing tests — IAM-conflict detection + UI/log reporting")

> **Correction from the independent M4 code review (2026-09-08).**
>
> This T#'s reds gate a capability the implementation (#234) does not deliver — see the correction
> comment on #234. VERIFIED: no production code reads bucket IAM state.
>
> The legs authored here assert the two mechanisms that did ship (generic failure logging, and the
> config-internal base-over-private requirements check). They are valid legs for those mechanisms. They
> do not, and cannot, pin IAM-conflict detection, because there is nothing to pin.
>
> Recorded so a future reader does not treat this T# as coverage of IAM detection. Disposition follows
> #234's decision.
>
> Cross-reference: `planning/m4-code-review.md` finding H1; `planning/m4-project-review.md` finding P4.

### 1.3 — On #244 ("M4: README settings.php reference for the aws_s3 driver")

> **Correction from the independent M4 project + code review (2026-09-08) — this ticket closed without
> a T# partner, and the documentation it shipped is contradicted by the code.**
>
> VERIFIED: #244 is the only feature ticket in milestone #15 with no T# partner and no `blocked_by`
> edge. Auditing all 59 M4 issues for `blockedBy.totalCount == 0` returns nineteen tickets — eighteen
> are T# tickets (correctly unblocked) and the nineteenth is this one. Pairing the milestone yields 29
> T#/feature pairs (58 tickets) plus #244.
>
> Two claims in the shipped README are false against the shipped code:
>
> 1. `README.md:62` and `README.md:80` present `credentials.secret_key_id` as the settings.php
>    credential shape, and `README.md:140` describes it as the "Key module reference for the secret".
>    **Nothing resolves it.** `AwsS3V3AdapterDriver::clientCredentials()` requires a literal
>    `credentials.secret`; with only `secret_key_id` set it returns NULL and the AWS SDK falls back to
>    its default provider chain — anonymous or instance-role requests, surfacing as a 403 rather than
>    as a configuration error. The `key:key` module is a hard dependency with zero consumers in
>    production code.
> 2. `README.md:139` states the secret is "never exported" to config. **It is.** No code strips
>    `credentials.secret` before the config entity is saved, and
>    `modules/flysystem_aws/config/schema/flysystem_aws.schema.yml` declares it as a persisted string.
>
> AGENTS.md rule 12 states there is no coverage-only exception to the T# gate, "even for tickets whose
> behavior seems already pinned". A T# partner for this ticket would have had to assert that the
> documented settings.php snippet builds a working adapter — an assertion that fails on current code.
> The one M4 ticket that bypassed the gate is the one whose gate would have caught two CRITICAL
> defects.
>
> Corrective work: the C1 and C3 ticket pairs (to be filed) include a leg that executes the README's
> own settings.php snippet, so documentation is verified by running what it tells the operator to do.
> The README must be corrected as part of C1/C3, not separately — a doc fix ahead of the code fix would
> just move the false claim.
>
> Cross-reference: `planning/m4-code-review.md` findings C1 and C3; `planning/m4-project-review.md`
> findings P1 and P2.

---

## 2. Ticket pairs to file

Eleven pairs. Each is `T# reds → user approval → implementation → joint close`. All target milestone
**M5 flysystem_asyncaws (#16)** unless stated, because the M5 `s3` driver inherits the same surfaces
and #105/#216 are still open — fixing these before M5's driver is written avoids porting the defects.

Labels for every implementation ticket: `code-review-issue`, plus the `seam:*` label named per item.
Labels for every T#: the same `seam:*`.

### 2.1 — C1: resolve `credentials.secret_key_id` through the Key module — CRITICAL *(verified)*

**Claim:** The Key-module credential path — the one the README documents — is never resolved, so it
silently produces anonymous S3 requests.

**Verified by:**
```
grep -rn "secret_key_id\|KeyRepository\|key.repository" --include="*.php" src/ modules/ | grep -v "/tests/"
# → 4 hits, all in AwsS3V3AdapterDriver's own key declaration and form. Zero consumers.
```
**Refuted if:** you find a `key.repository` (or equivalent Key module) service consumer that resolves
`secret_key_id` into a credential before `buildAdapter()` is called, on any code path. Paste it.

**T# ticket**
- Title: `TC1: Write failing tests — aws_s3 resolves credentials.secret_key_id through the Key module`
- Labels: `seam:adapter-plugin`
- Body: Red tests for the credential-resolution seam. Legs:
  1. A config carrying `credentials.key` + `credentials.secret_key_id` (a real `key` entity holding the
     secret) and **no** `credentials.secret` produces an `S3Client` whose resolved credentials match the
     Key entity's value.
  2. The README's verbatim settings.php snippet (`README.md:55-70`) produces a working adapter — a
     round-trip write + read against Floci.
  3. A `secret_key_id` naming a missing or empty Key entity produces a logged configuration error, not
     a silent fall-through to the SDK default provider chain.
- **Discrimination statement (red-first gate):** leg 1 fails today because `clientCredentials()`
  returns NULL whenever `credentials['secret']` is empty, so the client is built with no credentials —
  the assertion on resolved credentials cannot pass. Leg 2 fails today for the same reason (403 from
  the emulator when auth enforcement is on; `FLOCI_SERVICES_S3_ENFORCE_AUTH: "true"` is already set in
  CI). Leg 3 fails today because no error path exists — the condition is unobservable. All three prove
  behavior that does not exist; none is a green pin.

**Implementation ticket**
- Title: `C1: aws_s3 — resolve credentials.secret_key_id through the Key module`
- Labels: `code-review-issue`, `seam:adapter-plugin`
- `blocked_by`: TC1
- Body: Inject `key.repository` into the driver — or, preferred, into a small shared credential-resolver
  service so the M5 `s3` and M6 `sftp` drivers consume the same resolution and this is fixed once.
  Resolve `secret_key_id` to its Key entity value in `clientCredentials()` **before** the
  `empty($credentials['secret'])` check. Treat the pair as XOR at resolution time, mirroring the
  entity validator's save-time rule: a present `secret_key_id` whose Key entity is missing or empty is a
  logged configuration error, never a silent fall-through. Correct `README.md:62`, `:80`, `:140` to
  match what the code does once it does it.
- Note on the ticket: cites #244 (documentation shipped ahead of the capability) and #102/#103 (which
  declared the key without a consumer).

### 2.2 — C3: strip secrets from persisted config — CRITICAL *(verified)*

**Claim:** A plaintext AWS secret access key entered in the form is written to the config entity and
exported to config sync, contradicting the driver's own docblock and `README.md:139`.

**Verified by:**
```
grep -rn "secret" --include="*.php" src/
# → validation helpers (isSecretSet, secretPairsFromDriverPlugin, secretKeyPaths) and docblocks only.
#   No unset, no strip, no preSave.
```
Plus `modules/flysystem_aws/config/schema/flysystem_aws.schema.yml` declares `credentials.secret` as a
persisted `string`, and the form renders it `#type => textfield` with a `#default_value`.

**Refuted if:** you find a `preSave`, form submit handler, or config-export hook that removes the secret
from the stored entity — or a config schema declaration that excludes it from export. Paste it, plus a
saved entity's YAML showing the secret absent.

**T# ticket**
- Title: `TC3: Write failing tests — the aws_s3 secret is never persisted to the config entity`
- Labels: `seam:adapter-plugin`
- Body: Legs:
  1. Saving the aws_s3 form with a plaintext `config[credentials][secret]` produces an entity whose
     `config.credentials.secret` is absent.
  2. The saved entity's exported config array (as `Drupal\Core\Config` sees it) contains no secret
     value at any depth flagged `secret: TRUE` by the driver's `getConfigKeys()`.
  3. Re-rendering the edit form for a scheme that had a secret does not echo the secret back into the
     field's value.
- **Discrimination statement:** all three fail today. Leg 1 fails because nothing strips the value —
  it round-trips into `config.credentials.secret`. Leg 2 fails for the same root cause, asserted at the
  export boundary rather than the entity boundary (a distinct seam: it is what lands in `config/sync`).
  Leg 3 fails because the field is a `textfield` with `'#default_value' => $config['credentials']['secret'] ?? ''`.

**Implementation ticket**
- Title: `C3: Core + aws_s3 — secrets are never persisted or re-rendered`
- Labels: `code-review-issue`, `seam:adapter-plugin`
- `blocked_by`: TC3, **and C1** (§2.1) — the correct end state is that the form writes the secret into a
  Key entity and stores only the reference, which requires C1's resolver to exist first.
- Body: Add a `preSave()` on `FlysystemFilesystem` that unsets every path returned by the existing
  `secretKeyPaths()` from the stored `config` array — driven by the `secret: TRUE` markers, so `s3`
  (M5) and `sftp` (M6) are covered without further work. Remove `credentials.secret` from
  `flysystem_aws.schema.yml`. Change the form field to `#type => password` with no `#default_value`.
  Correct the driver docblock (`AwsS3V3AdapterDriver.php:307`) and `README.md:139` so the "never
  exported" claim becomes true rather than aspirational.

### 2.3 — C2: stop materializing `presigned_expiry` on public schemes; pin the URL precedence — CRITICAL *(reviewed)*

**Claim:** Every public `aws_s3` scheme saved through the admin form receives `presigned_expiry = 3600`,
so `getExternalUrl()` takes the presigned branch and CloudFront / `public_url_base` are never used.

**Verified by:** `AwsS3V3AdapterDriver.php:218-229` — the field carries
`'#default_value' => $config['presigned_expiry'] ?? 3600`, is gated only by `#states` (client-side CSS
visibility, still submitted), and has no `#access` gate and no server-side unset.
`FlysystemStreamWrapper::getExternalUrl()` tests `$presignedExpiry !== NULL` **before** computing
`$base` from `publicUrlBase` or `cloudfrontDomain`. `FlysystemFilesystem::validate()` does not block the
save: `driverSupportsTemporaryUrls()` returns TRUE for `aws_s3`
(`vendor/league/flysystem-aws-s3-v3/AwsS3V3Adapter.php:42` implements `TemporaryUrlGenerator`).

**This is the one CRITICAL marked *(reviewed)*, not *(verified)*.** The reviewer traced the
form → save → URL path in source but did not execute the save. **Verify it first** — see below.

**Refuted if:** a form save of a public scheme produces an entity whose `config.presigned_expiry` is
absent. The check:
```php
// In a Functional test, or by hand: create a public aws_s3 scheme via the admin form, save, then:
$entity = \Drupal::entityTypeManager()->getStorage('flysystem_filesystem')->load('schemetest');
var_dump($entity->get('config')['presigned_expiry'] ?? 'ABSENT');
```
If that prints `ABSENT`, the finding is refuted and §2.3 should be closed with that output pasted.
Corroborating evidence that it is *not* refuted: the two existing CloudFront URL legs both configure via
`setFlysystemSettings()` (project-review P3), i.e. the entity seam is untested, which is consistent with
the defect surviving 59 tickets.

**T# ticket**
- Title: `TC2: Write failing tests — a form-saved public aws_s3 scheme resolves URLs through CloudFront`
- Labels: `seam:url-generation`
- Body: Legs (all on the **config-entity seam**, not settings.php — that is the untested half):
  1. A public scheme saved through the admin form with `use_cloudfront` + `cloudfront.domain` and no
     presigned intent produces an entity whose `config.presigned_expiry` is absent.
  2. `getExternalUrl()` for that scheme returns the CloudFront domain URL, not a signed URL.
  3. A public scheme saved through the form with `public_url_base` set resolves through
     `public_url_base`.
  4. A **private** scheme saved through the form still round-trips `presigned_expiry` and still signs —
     the regression guard, so the fix does not remove the presigned feature where it belongs.
- **Discrimination statement:** legs 1–3 fail today because the form submits its `3600` default for
  public schemes and the presigned branch wins in `getExternalUrl()` — the returned URL is signed, not
  a CloudFront/base URL. Leg 4 is expected to pass today and after the fix; it is a permitted green pin
  under the green-pin policy because it locks the boundary the fix must not cross (private schemes keep
  presigned), and nothing else covers the private form-save seam for URL resolution. Flag it as such in
  the reds comment.

**Implementation ticket**
- Title: `C2: aws_s3 — presigned_expiry is not materialized for public schemes; URL precedence pinned`
- Labels: `code-review-issue`, `seam:url-generation`
- `blocked_by`: TC2
- Body: Do not persist `presigned_expiry` for a scheme whose `default_visibility` is not `private`.
  Either drop the `#default_value` fallback so the field submits empty unless the operator sets it, or
  unset the key in a `validateConfigurationForm()` / submit path when visibility is not private.
  `#states` is presentation and must never be the only gate on a persisted value. Then decide and
  document the precedence: `plan-m4.md` §2.1 records "presigned > base > CloudFront"; if that stands, an
  explicitly-set `public_url_base` or `use_cloudfront` on a scheme that also has `presigned_expiry`
  should raise a `hook_runtime_requirements` warning saying presigned wins, because a silent ordering is
  indistinguishable from this bug.

### 2.4 — H4 + L2: encode `CopySource`, and delete the dead `$visibility` — HIGH *(reviewed)*

**Claim:** `NoAclAwsS3Adapter::copy()` builds `CopySource` by raw concatenation. S3 expects a
URL-encoded path, so a key containing a space fails and a key containing a literal `+` copies the wrong
object. This is the `use_acl = FALSE` path, which is the **default**.

**Verified by:** `modules/flysystem_aws/src/Flysystem/NoAclAwsS3Adapter.php` — both branches:
`['CopySource' => $this->bucket . '/' . $sourceKey]` and
`new MultipartCopy($this->client, $this->bucket . '/' . $sourceKey, ...)`. The method overrides the
parent, so the parent's handling is not inherited.

**Refuted if:** the AWS SDK's `CopyObject` command encodes `CopySource` itself for this SDK version —
check `vendor/aws/aws-sdk-php/src/S3/` for a middleware doing so — or a Floci/live copy of
`dir/a file+name.txt` succeeds with matching content. The latter is the decisive test; run it.

**T# ticket**
- Title: `TH4: Write failing tests — aws_s3 copies keys containing spaces and plus signs`
- Labels: `seam:file-system`
- Body: Legs:
  1. Same-scheme `copy()` of `dir/a file.txt` (space) produces a destination whose content matches the
     source.
  2. Same-scheme `copy()` of `dir/a+file.txt` (literal plus) produces a destination whose content
     matches the source — this is the silent-wrong-object case, so assert content, not just existence.
  3. Same-scheme `move()` of a spaced key leaves no source and a correct destination.
- **Discrimination statement:** legs 1–3 exercise `NoAclAwsS3Adapter::copy()` with `use_acl = FALSE`
  (the default). Leg 1 fails today with an S3 request error on the unencoded space. Leg 2 is the
  important one: it fails on **content**, not on an exception, because `+` decodes to a space
  server-side and a different key is copied — asserting existence alone would pass and prove nothing.
  Leg 3 covers the `move()` path, which inherits `copy()`.

**Implementation ticket**
- Title: `H4: aws_s3 — URL-encode CopySource in the ACL-omitting adapter (+ remove dead $visibility)`
- Labels: `code-review-issue`, `seam:file-system`
- `blocked_by`: TH4
- Body: Encode the source key **per path segment** — `rawurlencode()` on the whole key is wrong, it
  would escape the `/` separators. Use the SDK's own helper if one is available on this version; mirror
  whatever the parent `AwsS3V3Adapter` does. Same fix in both the single-part `CopyObject` branch and the
  `MultipartCopy` branch. While in the method, delete the two `$visibility` assignments — the value is
  computed and never read (L2), which misleads the reader into thinking visibility is carried forward
  when `setVisibility()` is deliberately a no-op here. Keep the explanatory comment.

### 2.5 — H3 + P5: replace `send_chunked_body` with the real SDK control — HIGH *(verified)*

**Claim:** Two defects, one root cause. `send_chunked_body` is not an AWS SDK `S3Client` option, so
passing it does nothing; and the driver only ever sets it when truthy, so the `FALSE` value the form's
own description calls for is unrepresentable.

**Verified by:**
```
grep -rl "send_chunked_body" /Users/lisaridley/development/drupal-flysystem-4.0/vendor/
# → no output. Zero files in the entire vendor tree, including aws/aws-sdk-php.
```
Corroborating: `AwsS3V3AdapterDriver.php:62-64` sets it only under `!empty()`.
`FlociIntegrationTestBase.php:192` and `AwsS3SettingsPhpConfigTest.php:426` both set it to `FALSE` and
the legs pass — proving the flag has no effect in either direction. Project-review P5: the key has no
entry in `plan-m4.md` §1's config-key contract at all.

**Refuted if:** the option appears under a different name that the SDK aliases to it, or the SDK
validates and consumes unknown constructor keys (it does not — `ClientResolver` ignores them). A grep
hit anywhere in `vendor/aws/` refutes it outright.

**T# ticket**
- Title: `TH3: Write failing tests — the chunked-body control reaches the S3 client in both states`
- Labels: `seam:adapter-plugin`
- Body: Legs asserting the **constructed client's configuration**, not the config round-trip:
  1. With the chunked-body control off, the built `S3Client`'s configuration carries the option that
     actually suppresses `aws-chunked` streaming encoding.
  2. With it on, the client's configuration carries the opposite value — the two-way assertion the
     current one-way plumbing cannot satisfy.
- **Discrimination statement:** both legs fail today. Leg 1 fails because a FALSE value is dropped
  entirely — nothing is set, so there is no option to assert. Leg 2 fails because the option name
  currently set (`send_chunked_body`) does not exist in the SDK, so the client's resolved configuration
  never contains it. Note explicitly in the reds comment that the existing legs setting
  `send_chunked_body => FALSE` are **not** coverage — they pass regardless of the value, which is the
  defect.

**Implementation ticket**
- Title: `H3: aws_s3 — replace the inert send_chunked_body key with the real SDK control`
- Labels: `code-review-issue`, `seam:adapter-plugin`
- `blocked_by`: TH3
- Body: Identify the SDK option that actually governs the behavior. On current SDK versions the control
  that stops the `aws-chunked` streaming trailer MinIO and LocalStack reject is
  `request_checksum_calculation => 'when_required'` — **confirm this against the installed SDK version
  before relying on it**; the review did not verify the replacement, only that the current name is
  absent. Either map the existing key onto the real option or rename the key to describe what it does.
  Pass the value **unconditionally** (`$options[...] = (bool) $config[...]`), never only when truthy.
  Update the form description, the config schema, and `README.md:144`. Record on the ticket what
  consumes the key and which leg proves it (P5's rule).

### 2.6 — H2 + L1: requirements entries need `severity` and `t()` — HIGH *(verified)*

**Claim:** All three `hook_runtime_requirements` entries omit `severity`, so Drupal renders them as
informational rather than as warnings — the entire purpose of the hook. The same three build
user-facing text by PHP interpolation rather than `$this->t()`, violating `plan-m4.md` §5.

**Verified by:** `src/Hook/FlysystemRequirements.php:44-67` — the complete set of entries, each carrying
only `title` and `description`.

**Refuted if:** Drupal 11.4's status report renders a severity-less requirement as a warning. Check
`RequirementSeverity` handling in `core/modules/system/system.admin.inc` / the status-report template
and paste what you find.

**T# ticket**
- Title: `TH2: Write failing tests — flysystem misconfiguration requirements render as warnings`
- Labels: `seam:service-api`
- Body: One leg per entry (`flysystem_nobase_*`, `flysystem_baseoverprivate_*`,
  `flysystem_presigned_nosigning_*`), asserting the returned requirement carries warning severity —
  and one leg asserting the rendered `/admin/reports/status` page presents them in the warning section.
- **Discrimination statement:** every leg fails today because no entry carries a `severity` key at all,
  so each resolves to the informational default. The rendered-page leg is a distinct seam from the
  array-shape legs: it proves what the operator actually sees, which is the harm.

**Implementation ticket**
- Title: `H2: Core — misconfiguration requirements carry warning severity and translatable strings`
- Labels: `code-review-issue`, `seam:service-api`
- `blocked_by`: TH2
- Body: Add `'severity' => RequirementSeverity::Warning` to all three entries. In the same change, wrap
  every `title` and `description` in `$this->t()` with `@scheme` placeholders and add
  `StringTranslationTrait` (L1) — it is the same three array literals, so it is one commit. The
  `flysystem_nobase_` entry predates M4 and is included because the fix is indivisible.

### 2.7 — M1: pass Drupal's `filemime` at the `file_system` write sites — MEDIUM *(verified)*

**Claim:** The #19-split contract (stored `Content-Type` equals Drupal's `filemime`) is wired only
through the stream wrapper. `saveData()`, `copy()` and `move()` write with no `mimetype`, so the adapter
falls back to league's own finfo detector.

**Verified by:**
```
grep -rn "mimetype" --include="*.php" src/
# → src/StreamWrapper/FlysystemStreamWrapper.php:1114 only — one producer in the whole module.
```
`FlysystemFileSystem.php:180` (`saveData()`) calls `$filesystem->write($target, (string) $data)` with no
config; `transferContent()` calls `writeStream(..., [])` with an explicit empty config.
`AwsS3MimeOnWriteTest` exercises `file_put_contents()` only (lines 63, 107) — the wrapper seam.

**Refuted if:** league's `Filesystem` injects a `mimetype` into the operation config from its own
constructor defaults before reaching the adapter, such that the adapter receives Drupal's value.
Inspect `LoggingFilesystem`'s inherited `write()`/`writeStream()` config merge and paste it.

**T# ticket**
- Title: `TM1: Write failing tests — objects written via file_system carry Drupal's filemime`
- Labels: `seam:file-system`
- Body: One leg per unproven seam, asserting the **stored** `Content-Type` on the object:
  1. `saveData()` of CSV content to a `.csv` key stores Drupal's guessed mime.
  2. Cross-scheme `copy()` into an `aws_s3` scheme stores Drupal's guessed mime for the destination key.
  3. `move()` — same.
- **Discrimination statement:** all three fail today. Choose extensions where Drupal's guesser chain and
  league's `FinfoMimeTypeDetector` demonstrably disagree — `saveData()` is the clearest case, since
  finfo sees only a content string with no filename context and returns `text/plain` for generated CSV
  or SVG. Probe the two guessers' outputs first and pick an extension where they differ; if you cannot
  find one, say so on the ticket — a leg that passes either way is theater.

**Implementation ticket**
- Title: `M1: Core — pass the guessed mimetype at every file_system write site`
- Labels: `code-review-issue`, `seam:file-system`
- `blocked_by`: TM1
- Body: Pass `['mimetype' => ...]` from Drupal's `file.mime_type.guesser` at all three
  `FlysystemFileSystem` write sites, resolved from the destination URI (and from the destination
  filename for `saveData()`, which has no source file). One resolution helper, three call sites.

### 2.8 — M2 + M3: `moveUploadedFile()` — restore the upload guard, fix the return value — MEDIUM

**Claim:** Two defects in the same new method, filed as one ticket because they are one commit.
M2 *(verified)*: the remote fallback drops PHP's `is_uploaded_file()` guarantee, because
`parent::moveUploadedFile()` always fails for remote destinations and the fallback then `fopen`s
`$filename` unchecked. M3 *(reviewed)*: the method returns `@unlink($filename)`, so a successful upload
whose temp file cannot be deleted is reported as a failure, orphaning the object in the bucket.

**Verified by:** `src/File/FlysystemFileSystem.php`, the new `moveUploadedFile()` override — the
`@fopen((string) $filename, 'rb')` with no upload check, and the final `return @unlink((string) $filename);`.

**Refuted if (M2):** a caller-side guard makes `$filename` provably an upload temp file on every path
reaching this method. Note that core's own `FileSystem::moveUploadedFile()` relies on
`move_uploaded_file()` for exactly this, which is the guarantee being dropped.
**Refuted if (M3):** the unlink cannot fail in practice on any supported platform — argue it with the
conditions, not by assertion.

**T# ticket**
- Title: `TM2: Write failing tests — moveUploadedFile guards uploads and reports transfer success`
- Labels: `seam:file-system`
- Body: Legs:
  1. `moveUploadedFile()` with a `$filename` that is not an upload temp file returns FALSE and writes
     nothing to the destination scheme.
  2. A successful transfer whose temp-file unlink fails returns TRUE and the destination object exists
     (simulate by making the temp file's directory non-writable, or by pre-opening a lock — document
     whichever the platform allows).
- **Discrimination statement:** leg 1 fails today because no upload check exists, so the bytes are
  copied and TRUE is returned. Leg 2 fails today because the return value is the unlink result. If leg
  2 cannot be made to fail on this platform, document that as a defect class unassertable at this seam
  and ship the alternative guard (assert the destination object exists after the call regardless of
  return) — per the red-first gate's documented-reason clause.

**Implementation ticket**
- Title: `M2: Core — moveUploadedFile restores the upload guard and reports transfer success`
- Labels: `code-review-issue`, `seam:file-system`
- `blocked_by`: TM2
- Body: Guard the fallback with `is_uploaded_file($filename)`. Kernel and Functional tests that
  fabricate uploads will need the guard relaxed under `drupal_valid_test_ua()` — core takes the same
  approach in its own upload handling; do it explicitly with a comment, never by omission. Separately,
  return TRUE when the transfer succeeded and log an unlink failure as a warning, rather than
  converting it into an operation failure.

### 2.9 — M4: path-boundary containment in `resolveLocalPath()` — MEDIUM *(reviewed)*

**Claim:** The containment guard uses `str_starts_with($realpath, $directory)` — a character-prefix
test, not a path-boundary test. With root `/var/www/files`, a target of `../files-evil/x` resolves to
`/var/www/files-evil/x`, which passes.

**Verified by:** `src/StreamWrapper/FlysystemStreamWrapper.php`, in `resolveLocalPath()`. Note the
method's docblock claims it "adds the guards core does not have"; this particular guard is inherited
from core `LocalStream::getLocalPath()` unchanged, weakness included.

**Refuted if:** an earlier normalization strips `..` from the target before it reaches this check — trace
`parseUri()` and the `trim($target, '\/')` step and paste what happens to a traversing target. This is
the most likely refutation of any finding in this document; check it properly before filing.

**T# ticket**
- Title: `TM4: Write failing tests — realpath() rejects a sibling directory sharing the root prefix`
- Labels: `seam:stream-wrapper`
- Body: Legs, with a root and a sibling directory whose name extends it (`.../files` and
  `.../files-evil`):
  1. `realpath()` on a target traversing into the sibling returns FALSE.
  2. `stream_metadata()` STREAM_META_ACCESS on that target returns FALSE and does not chmod the sibling
     file — the consequence leg, since `realpath()` feeds `chmod()`.
  3. A legitimate target inside the root still resolves — the regression guard.
- **Discrimination statement:** legs 1–2 fail today because the prefix match accepts the sibling path.
  Leg 3 is a green pin, permitted because the fix could over-tighten and it covers the boundary the fix
  must not cross; flag it as such.

**Implementation ticket**
- Title: `M4: Core — realpath() containment uses a path boundary, not a string prefix`
- Labels: `code-review-issue`, `seam:stream-wrapper`
- `blocked_by`: TM4
- Body: Compare on a path boundary: `str_starts_with($realpath, rtrim($directory, '/') . '/')`, with
  `$realpath === $directory` accepted separately so the root itself resolves. Correct the docblock's
  "guards core does not have" claim to name this as one of them, now that it is.

### 2.10 — M6: filter AWS SDK exception detail before it reaches watchdog — MEDIUM *(reviewed)*

**Claim:** Four log sites interpolate `$e->getMessage()` unfiltered. AWS `S3Exception` messages embed the
error response body, which for `SignatureDoesNotMatch` includes `AWSAccessKeyId` and the canonical
`StringToSign`. Watchdog is readable by anyone with "access site reports" and is commonly shipped to
external aggregators.

**Verified by:** `src/Flysystem/LoggingFilesystem.php:229`;
`src/Flysystem/FilesystemFactory.php:486-492` and `:529-536`. The HTTP responses are correctly
sanitized — only the log carries the detail, which is the deliberate design; the gap is the assumed
trust level of watchdog.

**Refuted if:** the SDK's exception messages on this version omit the response body — trigger a
`SignatureDoesNotMatch` against Floci with a bad secret and paste the logged message. Do this before
filing; it settles the finding either way and takes one run.

**T# ticket**
- Title: `TM6: Write failing tests — logged adapter failures carry no credential material`
- Labels: `seam:integrations`
- Body: One leg: a failed operation caused by a bad secret produces a watchdog entry containing neither
  the access key ID nor a `StringToSign` fragment, while still naming the scheme, driver, operation and
  a usable reason.
- **Discrimination statement:** fails today if and only if the SDK message carries that material —
  which is exactly the check under "Refuted if". Run that probe first; if the message is already clean,
  close this item as refuted rather than authoring a leg that passes on current code.

**Implementation ticket**
- Title: `M6: Core — filter SDK exception detail out of watchdog entries`
- Labels: `code-review-issue`, `seam:integrations`
- `blocked_by`: TM6
- Body: Log `$e::class` plus a filtered message for SDK exceptions — strip `<StringToSign>` and
  `<AWSAccessKeyId>` elements, or truncate to the error code and message. Keep full detail behind a
  debug setting if support needs it. Applies to all four sites.

### 2.11 — M5: dedupe standing-misconfiguration logging — MEDIUM *(verified)*

**Claim:** Three surfaces log the same standing condition repeatedly with no dedupe:
`FilesystemFactory::getAdapter()` once per request; `LoggingFilesystem::logFailure()` once per attempted
operation against the `MisconfiguredFilesystemAdapter` (every one of which throws); and
`FlysystemFilesystemListBuilder::reportMisconfiguration()` once per row per collection-page load.

**Verified by:** `src/Flysystem/FilesystemFactory.php:341-349`;
`src/Flysystem/LoggingFilesystem.php:222-236` (invoked from all ten wrapped data-plane methods);
`src/Entity/FlysystemFilesystemListBuilder.php` — `reportMisconfiguration()` is called from
`buildRow()`, which also adds a messenger warning per row.

**Refuted if:** Drupal's logger backend already collapses identical entries within a request. It does
not, but check the site's configured channel before asserting.

**T# ticket**
- Title: `TM5: Write failing tests — a standing misconfiguration logs once per request`
- Labels: `seam:service-api`
- Body: Legs:
  1. N operations against a misconfigured scheme in one request produce one watchdog warning, not N.
  2. A collection page listing M misconfigured schemes adds M messenger warnings once — not M per
     row-build — and writes no watchdog entry per render.
- **Discrimination statement:** both fail today by count. Assert exact counts, not presence: presence
  passes on current code and proves nothing.

**Implementation ticket**
- Title: `M5: Core — dedupe standing-misconfiguration reporting per request`
- Labels: `code-review-issue`, `seam:service-api`
- `blocked_by`: TM5
- Body: Track already-reported scheme keys per request in `LoggingFilesystem` and in the list builder so
  a standing condition logs once. Move the list builder's reporting out of `buildRow()` into `render()`,
  aggregating one message across all rows — logging from a render-build method makes volume scale with
  rendering rather than with events.

---

## 3. Decision items — not tickets

These need the user's judgment, not an implementation. Present each, stop, wait. Do **not** file a
ticket for any of them unilaterally (gap protocol: called out on the record → discussed → scoped →
worked only on approval).

| Item | Finding | The decision |
|---|---|---|
| **IAM detection** | H1 / P4 | Implement real detection (`GetBucketPolicyStatus` / `GetBucketOwnershipControls` probe on the connection-test path and in `hook_runtime_requirements`, compared against `default_visibility` and `use_acl`), or record the descope and rename #234's surfaces. §1.1's comment poses this; the answer determines whether a twelfth pair gets filed. Label the ticket `needs-human` until answered. |
| **Test-connection SSRF** | L3 | `testConnectionCallback()` builds an adapter from raw `getUserInput()` with `'#limit_validation_errors' => []` and probes an arbitrary endpoint. Admin-gated, response not reflected — blind only. Accept it as an administrative-trust capability and document it, or validate the endpoint (scheme allowlist, reject loopback and link-local). Either is defensible; leaving it undecided is not. |
| **Bulk-mutation cache-tag cost** | M7 | Every owned-scheme mutation calls `invalidateTags()`, so an M8 migration pays one `cachetags` write per file (times path depth in tags). Not a defect — a scaling decision for M8: batch/deferred invalidation the migration path can wrap a run in, or coarser tag granularity. **Get a number first:** a benchmark leg timing 1,000 sequential `saveData()` calls with and without stat-cache invalidation. Target milestone M8 (#13). |
| **`visibility` vs `default_visibility`** | P6 | `plan-m4.md` §1 and `AdapterDefinition`'s docblock say aws_s3 uses `visibility`; the driver and its schema declare only `default_visibility`. The runtime fallback absorbs it for settings.php, but the submodule schema has no `visibility` key — so a v3→v4 migration carrying `visibility` into a config entity fails schema validation while the same value in settings.php works. Settle the canonical name against `config-and-upgrade.md` §2, correct the docblock either way, and add an accepted alias to the schema if real v3 sites have that shape. Record where M8's tickets will find it. |
| **Stale title prefixes** | P7 | #84 (`M3:`), #182 (`M2:`), #184 (`M3:`), #230/#232 (bare `Core:`) sit in milestone #15. Cosmetic, but it degrades milestone-scoped board reads. Rename opportunistically during M5 board planning with a comment noting the rename, or leave. No ticket. |

---

## 4. `plan-m5.md` amendments

Two process amendments, both generalizations of findings above. M5's #105 and #216 are still open, so
these can be applied before M5's tickets are written — which is the point. Proposed insertion into
`plan-m5.md` §5 (Constraints):

> - **Every config-key line names its consuming code path and its proving leg**, not just the key name.
>   A key list is a declaration, not a contract: "`key X` is read by `Y` and proven by leg `Z`" is a
>   contract. M4's `credentials.secret_key_id` was declared in the driver, the schema, the form, and the
>   README, and consumed nowhere — because no ticket asked for a consumer (M4 review C1 / P2).
>   `send_chunked_body` was declared and consumed by an option the SDK does not have (H3 / P5).
> - **Any config key settable from both settings.php and the admin form requires a proving leg per
>   seam.** The two paths diverge — the form materializes `#default_value`s that settings.php never
>   supplies — so a single leg proves half the feature. M4's CloudFront URL resolution had two legs,
>   both on the settings.php seam; the entity seam was untested, and that is exactly where the defect
>   was (M4 review C2 / P3).

Also worth adding to the M5 pre-flight, before #105/#216 are worked: **audit the `s3` driver's planned
config-key list against C1, C3 and H3 first.** The asyncaws driver inherits the same credential surface
and the same chunked-body question. Fixing them once in a shared resolver (§2.1) is cheaper than
porting three defects and then correcting both.

---

## 5. Suggested filing order

Dependency-ordered, deepest first. Each step is a separate authorization.

1. **§1.1, §1.2, §1.3** — the three correcting comments. No code, no tickets, and they stop false
   claims standing in the source of truth. Do these first.
2. **§3, IAM decision** — poses the only question that changes what else gets filed.
3. **§2.1 (C1)** → **§2.2 (C3)**. C3 is `blocked_by` C1; C1's resolver is also what M5's `s3` driver
   needs, so it is the deepest unstarted work.
4. **§2.3 (C2)** — independent of C1/C3. **Run the "Refuted if" check before filing** — it is the one
   CRITICAL marked *(reviewed)*.
5. **§2.4 (H4+L2), §2.5 (H3), §2.6 (H2+L1)** — independent of each other and of the above.
6. **§2.9 (M4), §2.10 (M6)** — run each "Refuted if" probe first; both are *(reviewed)* and M6's probe
   settles it in one run.
7. **§2.7 (M1), §2.8 (M2+M3), §2.11 (M5)**.
8. **§4** — the `plan-m5.md` amendments, before M5's #105/#216 are worked.
9. **§3, remaining decisions** — L3, M7 (with a benchmark number), P6, P7.

## 6. Guardrails

- **`planning/plan-m4.md` is frozen.** Nothing here amends it. If you find yourself editing it, stop.
- **No ticket is worked without being in "In progress" on the board.** Filing a ticket is not
  authorization to work it.
- **Every pair is `T# reds → In review → user approval → implementation → joint close.`** No
  straight-to-Done, no batching deliveries.
- **Do not approve your own work.** Approval comes from the user only.
- **Two findings are marked *(reviewed)*, not *(verified)*: C2 and M4** (plus M3, M6, H4 among the
  lower severities). Each carries a "Refuted if" check. Running those checks is the first task, not an
  optional preliminary — and a refutation, pasted with output, is a legitimate and useful outcome.
- **Assert nothing you have not run.** Every claim you add to these tickets needs pasted output, same
  standard the review held itself to.
