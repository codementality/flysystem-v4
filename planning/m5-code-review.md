# M5 (flysystem_asyncaws / s3 driver + M4 corrections) — Independent Code Review

Status: Review, 2026-09-10. Scope: the M5 milestone code in the module repo
(`web/modules/custom/flysystem`, branch `4.0.x`), commits `3f3d8d9..a03fd83` (62 files, +7,477/-107),
judged against `planning/plan-m5.md` (§1 boundary, §3 standing constraints, §4 test plan, §5 exit
criterion), `planning/architecture.md` §4–§7/§11, and `planning/m4-code-review.md` (the corrections
this milestone was meant to land). Companion: `planning/m5-project-review.md` (the ticket axis).

## Executive summary

**The M4 corrections landed and are real — C1, C2, C3, H2, H3, M1, M2, M4, M6 all verify as fixed, and
the new `s3` driver is materially better built than its `aws_s3` predecessor — but two of the fixes
collide with each other, and the collision is a CRITICAL neither ticket's tests could see.** C3's
`preSave()` now strips the literal secret from stored config; the new bucket-IAM probe (#270) reads
*only* that literal secret. The result is that the security feature built to close M4's H1 authenticates
as nobody on every site configured the way the same milestone made canonical, and silently reports "no
conflicts" forever. Separately, C1's credential resolver introduced a `throw` on the adapter-build path
that `getAdapter()` does not guard, re-opening the WSOD boundary architecture §5 exists to hold.

The pattern has shifted, and that is worth naming: M4's defects were *declared-but-unconsumed* config
keys. M5's are *cross-ticket integration* — each ticket is correct in isolation, and the seam between
two of them is where the defect lives. That is a harder class to catch, and it is the predictable next
class once per-ticket discipline is working.

| Gate | Result |
|---|---|
| `ddev phpcs` (canonical `.ddev/commands/web/phpcs.xml.dist`) | **PASS** — empty output, exit 0 |
| `ddev phpstan` (canonical `.ddev/commands/web/phpstan.neon`) | **PASS** — `[OK] No errors`, exit 0 |
| `ddev phpunit` | **NOT RUN** — rule 8 scopes local phpunit to changed files; no test file was changed by this review |
| `ddev floci-check` | **NOT RUN** — no code change to verify against the emulator |

As in M4: **every finding below passes both static gates.** They are contract and integration defects.

## Findings — by severity

- **CRITICAL — C1.** Credential resolution throws from `buildAdapter()`, `getAdapter()` does not guard
  it, and `getExternalUrl()`'s presigned branch is outside its own try/catch — a deleted Key entity
  becomes a WSOD.
- **CRITICAL — C2.** The bucket-IAM probe reads only the literal `credentials.secret` that C3's
  `preSave()` strips, and never resolves `secret_key_id` — so IAM detection is unauthenticated and
  silently reports no conflicts on every correctly-configured site.
- **HIGH — H1.** `hook_runtime_requirements` issues up to three blocking AWS API calls per `aws_s3`
  scheme on every status-report load, with no caching, no memoization and no timeout override.
- **HIGH — H2.** `MisconfiguredFilesystemAdapter` surfaces scheme names and missing config-key names to
  **anonymous** users through the messenger.
- **HIGH — H3.** The `secret_key_id` branch preempts `use_provider_key_management`, so a lingering key
  reference silently overrides the operator's provider-chain choice — or throws.
- **HIGH — H4.** The `s3` driver's presigned capability is real and proven, but unreachable through its
  own key set, schema, and form — while the stream wrapper honors `presigned_expiry` from settings.php.
- **MEDIUM — M1.** `ExceptionMessageScrub` filters XML elements only; query-string credentials
  (`X-Amz-Credential`, `X-Amz-Signature`) survive into watchdog.
- **MEDIUM — M2.** `BucketIamProbeFactory` re-implements credential construction instead of reusing the
  driver's resolver — the root cause of C2 and a standing drift risk for M6.
- **MEDIUM — M3.** `detectConflicts()` swallows every `Throwable` into `[]`, so an unreachable bucket is
  indistinguishable from a clean one and the operator gets no signal that detection did not run.
- **LOW — L1.** The `s3` driver inverts AsyncAws's own `sendChunkedBody` default, so MinIO and Floci
  users must actively disable a setting the SDK disables by default.

---

## Findings detail

### C1. Credential resolution throws from `buildAdapter()`, and `getExternalUrl()` does not guard it — a deleted Key entity becomes a WSOD — CRITICAL *(verified)*

**What:** The C1 fix (#248) added two `throw new \InvalidArgumentException` statements to
`clientCredentials()` in both drivers — one for an unresolvable `secret_key_id`, one for the
`use_provider_key_management` contradiction. `FilesystemFactory::getAdapter()` calls `buildAdapter()`
unguarded, and `FlysystemStreamWrapper::getExternalUrl()` calls `getFilesystem()` in its presigned
branch **outside** the try/catch that wraps the rest of the method. A config error therefore propagates
through `getExternalUrl()` into `FileUrlGenerator` — the exact WSOD path the surrounding comment says
must never happen.

**Evidence:** `modules/flysystem_aws/src/Plugin/Flysystem/Adapter/AwsS3V3AdapterDriver.php:528` and
`:540` (and the identical pair in `S3AdapterDriver.php`) throw. `src/Flysystem/FilesystemFactory.php`,
`getAdapter()` — the docblock promises the opposite of what the last line does:

```php
// ... never a thrown exception from getAdapter()/getFilesystem().
$missing = $this->missingRequiredConfigKeys($definition);
if ($missing !== []) { ... return new MisconfiguredFilesystemAdapter(...); }
return $this->adapters[$scheme] = $this->buildAdapter($definition);   // ← unguarded
```

`credentials` is not a *required* key, so `missingRequiredConfigKeys()` returns `[]` and the
`MisconfiguredFilesystemAdapter` path is never taken. `src/StreamWrapper/FlysystemStreamWrapper.php`
— the method's try/catch closes after the service lookups, and line 562 is outside it:

```php
catch (\Throwable $e) { return ''; }        // ← guard ends here
...
if ($presignedExpiry !== NULL) {
  $filesystem = $factory->getFilesystem($scheme);   // ← throws out of getExternalUrl()
```

Blast radius is bounded, and worth stating precisely: `stream_open()` (line 1331) and
`openReadStream()` (line 1422) **are** guarded and degrade correctly, and
`FlysystemFileSystem::operatorForUri()` converts the throw into `InvalidStreamWrapperException`. The
unguarded path is `getExternalUrl()`'s presigned branch.

**Impact:** A site using the now-canonical credential shape (Key module reference) whose Key entity is
deleted, renamed, or has its value cleared — a routine operational event — turns every page rendering a
file from that scheme into a white screen, rather than a broken image plus a logged config error. The
`use_provider_key_management` throw is reachable the same way. This regresses the boundary #232
established and that `getAdapter()`'s own docblock still advertises.

**Fix:**
- Wrap the `buildAdapter()` call in `getAdapter()`: catch `\Throwable`, log it, and return
  `MisconfiguredFilesystemAdapter` — extend that class to carry a reason string as well as missing keys,
  so the onscreen and logged text stays specific.
- Move `getFilesystem()` inside `getExternalUrl()`'s guarded region, or wrap the presigned branch in its
  own try/catch that calls `reportFailure()` and returns `''`, matching every other failure path in that
  method.
- Keep the throws in the drivers — they are the right signal at that layer. The defect is the missing
  boundary above them, not the throw itself.

### C2. The bucket-IAM probe reads only the literal secret that C3 strips, so IAM detection is unauthenticated and silently reports nothing — CRITICAL *(verified)*

**What:** `BucketIamProbeFactory::create()` builds its `S3Client` from `credentials.key` and
`credentials.secret` only. It never resolves `credentials.secret_key_id`. In the same milestone,
`FlysystemFilesystem::preSave()` (C3, #250) began stripping every `secret: TRUE` path — including
`credentials.secret` — from the stored config entity. The two changes are individually correct and
mutually exclusive: after C3, a form-configured site has no literal secret for the probe to find.

**Evidence:** `modules/flysystem_aws/src/Iam/BucketIamProbeFactory.php`:

```php
$credentials = $config['credentials'] ?? NULL;
if (is_array($credentials) && !empty($credentials['key']) && !empty($credentials['secret'])) {
  $options['credentials'] = [...];
}
return new AwsSdkBucketIamProbe(new S3Client($options));
```

No `secret_key_id` handling anywhere in the component:
```
$ grep -rn "getIamConflicts\|secret_key_id" --include="*.php" modules/flysystem_aws/src/Iam/
(no secret_key_id hits)
```
`src/Entity/FlysystemFilesystem.php:313-323` is the stripper:
```php
public function preSave(EntityStorageInterface $storage): void {
  ...
  foreach ($this->secretKeyPaths() as $path) { $this->unsetConfigValue($config, $path); }
```
And `AwsSdkBucketIamProbe::detectConflicts()` catches every `\Throwable` and returns `[]`, so the
resulting 403 is invisible. The probe's tests do not catch this because they replace the factory
wholesale: `BucketIamConflictDetectionTest.php:353` `overrideProbeFactory(MockHandler $mock)` — every leg
drives canned payloads through a mock client, so real credential construction is never exercised.

**Impact:** The feature built to correct M4's H1 does not function on any site that follows the
credential path M5 made canonical. `GetBucketPolicyStatus` returns 403, the catch swallows it,
`detectConflicts()` returns `[]`, and `/admin/reports/status` shows a clean bill of health whether the
bucket is correctly configured or wide open to the world. An operator is worse off than before #270:
they now have positive evidence of safety that is manufactured. This is M4's C1 defect class recurring
in the very component built to fix M4's H1 — a declared credential path that a new consumer does not
consume.

**Fix:**
- Have `BucketIamProbeFactory` obtain credentials from the driver's `clientCredentials()` resolver
  rather than re-reading raw config — see M2, which is the same fix stated as a refactor.
- Distinguish "no conflicts" from "could not determine" in the return contract (see M3); a 403 from the
  probe must not render as a clean result.
- Add a leg that exercises the **real** factory with a `secret_key_id`-only config and asserts the
  constructed client carries resolved credentials. The existing mock-the-factory legs are correct for
  verdict logic and structurally cannot cover construction — say so on the ticket.

### H1. Bucket-IAM probing runs up to three blocking AWS calls per scheme on every status-report load — HIGH *(verified)*

**What:** `hook_runtime_requirements` calls `getIamConflictsForDriver()` for every configured scheme.
For `aws_s3` that reaches `AwsSdkBucketIamProbe::detectConflicts()`, which issues `GetBucketPolicyStatus`,
then `GetBucketOwnershipControls`, then (when the first two are inconclusive) `GetBucketAcl`. There is no
result cache, no per-request memoization, no SDK timeout or retry override, and a **new `S3Client` is
constructed on every call**.

**Evidence:** `src/Hook/FlysystemRequirements.php` — inside the per-scheme loop:
`$conflicts = $this->filesystemFactory->getIamConflictsForDriver(...)`.
`src/Flysystem/FilesystemFactory.php`, `getIamConflictsForDriver()` — creates a plugin instance and calls
through with no caching. `modules/flysystem_aws/src/Iam/BucketIamProbeFactory.php` — `return new
AwsSdkBucketIamProbe(new S3Client($options));`. `AwsSdkBucketIamProbe::detectConflicts()` — the three
calls, in order.

**Impact:** `hook_runtime_requirements` runs on every load of `/admin/reports/status`, and Drupal also
invokes runtime requirements during cron and on the update path. Three synchronous round trips per scheme
is the good case. The bad case is an unreachable or misconfigured endpoint, where each call burns the AWS
SDK's default connect timeout and retry budget before failing — with several schemes configured, the
status report can exceed the PHP execution limit or the gateway timeout, which is a self-inflicted outage
on the page an operator visits *because* something is wrong. Note the interaction with C2: today the calls
mostly fail fast with a 403, which masks how expensive this becomes once C2 is fixed and the calls actually
do work.

**Fix:**
- Cache the verdict per scheme, keyed on the config hash, in a cache bin with a sane TTL (hours, not
  seconds — bucket IAM does not change often), invalidated when the scheme's config entity is saved.
- Memoize within the request as a floor, so a single page never probes the same bucket twice.
- Set an explicit low `http` timeout and `retries => 0` on the probe's client — this is an advisory check
  and must never be the slowest thing on the page.
- Consider moving the probe off the runtime-requirements path entirely and onto the connection-test button
  plus a cron-warmed cache, so the interactive page reads a stored verdict.

### H2. Misconfiguration warnings are shown to anonymous users, disclosing scheme and config-key names — HIGH *(verified)*

**What:** #280 added an onscreen messenger warning to `MisconfiguredFilesystemAdapter::fail()`. There is
no permission check and no role gate: the message renders for whoever is on the page, including
unauthenticated visitors.

**Evidence:** `src/Flysystem/MisconfiguredFilesystemAdapter.php`:

```php
if (!$this->reported) {
  $this->reported = TRUE;
  $this->messenger->addWarning(new TranslatableMarkup(
    'The @scheme scheme is misconfigured (missing: @keys). Check the logs for details.',
    ['@scheme' => $this->scheme, '@keys' => implode('", "', $this->missingKeys)],
  ));
}
```

`fail()` is invoked from every operation on the adapter, and the adapter is returned by
`getAdapter()` on any front-end request that touches the scheme.

**Impact:** A public page rendering a file from a misconfigured scheme shows anonymous visitors the
internal scheme name and exactly which configuration keys are absent — for example "The publicmedia
scheme is misconfigured (missing: bucket, region)." That is internal configuration state disclosed to
unauthenticated users, and it tells an attacker which storage backend is in play and that it is
half-configured. The per-instance dedupe (#268) correctly limits volume; it does not limit audience.
The once-per-request guard also means the disclosure lands on whichever request happens to be first,
which will frequently be an anonymous one.

**Fix:** Gate the messenger call on a permission — `administer flysystem` (or `access site reports`) —
and keep the watchdog entry unconditional. An anonymous visitor should see a broken image and nothing
else; the operator sees the warning. Add a leg asserting an anonymous request produces no message while
an admin request does.

### H3. The `secret_key_id` branch preempts `use_provider_key_management` — HIGH *(reviewed)*

**What:** `clientCredentials()` resolves `secret_key_id` **first**, before consulting
`use_provider_key_management`. A config carrying both a key reference and `use_provider_key_management =
TRUE` uses the static credentials and ignores the operator's explicit choice — or, if the reference no
longer resolves, throws (see C1).

**Evidence:** `AwsS3V3AdapterDriver.php` / `S3AdapterDriver.php`, `clientCredentials()` — the
`if ($keyId !== '')` block returns or throws before `$useProvider` is read. The config reaches that state
easily: the form's credentials fieldset is gated by `#states` (client-side visibility only), so the
`secret_key_id` field is still submitted and persisted when the operator checks "use provider key
management". Marked *(reviewed)*: the ordering is certain from source; I did not execute the
check-the-box-and-save sequence.

**Impact:** Checking "use provider key management" does not take effect on any scheme that previously had
a Key reference — the site keeps using static credentials while the UI says otherwise. This is the same
root cause as M4's C2 (a `#states`-hidden field persisting a value the server-side logic then honors),
recurring on a different field in the same form after C2 fixed it for `presigned_expiry`.

**Fix:** Read `use_provider_key_management` first and return `NULL` immediately when it is TRUE, before
any credential resolution. Separately, unset the credentials sub-tree on save when provider key management
is on — the same server-side gating C2 established for `presigned_expiry`, applied to the field beside it.

### H4. The `s3` driver's presigned capability is real, proven, and unreachable through its own configuration surface — HIGH *(verified)*

**What:** #216's probe leg measured that the AsyncAws adapter implements `TemporaryUrlGenerator` and signs
without any presigned config key. The driver declares no `presigned_expiry` key, the config schema does not
allow it, and the form does not offer it — yet `FlysystemStreamWrapper::getExternalUrl()` reads
`$config['presigned_expiry']` generically from the definition, so a settings.php scheme *can* enable it and
it *will* work.

**Evidence:** `AsyncAwsSettingsPhpConfigTest.php:222-240` — the probe leg, asserting the adapter signs with
no presigned key configured. `S3AdapterDriver::getConfigKeys()` — no `presigned_expiry` entry.
```
$ grep -n "presigned" modules/flysystem_asyncaws/config/schema/flysystem_asyncaws.schema.yml
(no output — not declared)
```
`plan-m5.md` §4 states the intent ("CloudFront: NO preserved key exists for `s3` — no CloudFront scope")
but says nothing about presigned, and §1's key list omits it.

**Impact:** Three inconsistencies at once. A capability the module has is unavailable to operators using the
supported path (the admin form). The two configuration seams disagree: settings.php reaches it, config
entities cannot — and a config entity that somehow carries the key fails config-schema validation, which is
the M8 migration hazard P6 flagged for `visibility` in M4, recurring here. And the probe that discovered this
recorded the finding without a ticket resolving it, so the milestone closed with a known open question.

**Fix:** Decide, and make all three seams agree. Either declare `presigned_expiry` on the `s3` driver (key +
schema + form field, matching `aws_s3` including C2's public-scheme gating), or explicitly reject it for `s3`
— entity validation plus a `hook_runtime_requirements` warning when a settings.php `s3` scheme sets it. The
current middle state is the worst of the three.

### M1. `ExceptionMessageScrub` filters XML elements only; query-string credentials survive — MEDIUM *(reviewed)*

**What:** The M6 fix scrubs `<AWSAccessKeyId>` and `<StringToSign>` elements from exception messages.
Credential material also appears in AWS errors as **query parameters** — `X-Amz-Credential` (which embeds the
access key ID) and `X-Amz-Signature` — whenever the message quotes a signed request URI. The regex does not
match those.

**Evidence:** `src/Flysystem/ExceptionMessageScrub.php`:
```php
return (string) preg_replace('/<(AWSAccessKeyId|StringToSign)>.*?<\/\1>/s', '[removed]', $message);
```
Element-anchored, so a URI-form credential passes through. The `s3` driver's proven signing capability
(H4's probe) makes presigned URIs appearing in error paths a realistic case. Marked *(reviewed)*: I did not
capture an SDK message containing a signed URI.

**Impact:** The mitigation is partial in a way its docblock does not acknowledge ("a single shared filter, so
no call site can drift back to verbatim logging" is true of call sites, not of message shapes). An access key
ID reaching watchdog is credential metadata disclosure to anyone with "access site reports" and to any log
aggregator downstream.

**Fix:** Add query-parameter patterns to the scrub (`X-Amz-Credential`, `X-Amz-Signature`, `X-Amz-Security-Token`),
and add a leg per pattern using a captured message shape rather than a synthetic one. Consider inverting the
approach — allowlist the error code and reason, drop the rest — since a denylist over vendor-formatted strings
needs revisiting every SDK upgrade.

### M2. `BucketIamProbeFactory` re-implements credential construction instead of reusing the driver's resolver — MEDIUM *(verified)*

**What:** The factory builds an `S3Client` with its own copy of the endpoint, path-style, region and
credential logic, duplicating what `AwsS3V3AdapterDriver::buildAdapter()`/`clientCredentials()` already do.
The copy is already behind: it lacks `secret_key_id` resolution (C2), the `use_provider_key_management` rule,
and the `send_chunked_body` handling.

**Evidence:** `modules/flysystem_aws/src/Iam/BucketIamProbeFactory.php:31-49` versus
`AwsS3V3AdapterDriver::buildAdapter()` and `clientCredentials()` — two constructions of the same client from
the same config, one of them a subset.

**Impact:** C2 is the first divergence; it will not be the last. M6 adds a third driver, and any future
credential change must be made in two places with nothing enforcing the pairing. This is the structural cause
worth fixing rather than patching.

**Fix:** Give the driver a single `buildClient(array $config): S3Client` used by both `buildAdapter()` and the
probe factory, so credentials, endpoint and options resolve once. The probe factory then depends on the driver
(or on a shared client-builder service), not on raw config.

### M3. `detectConflicts()` cannot distinguish "no conflicts" from "could not check" — MEDIUM *(verified)*

**What:** The method returns `array` and catches every `\Throwable` into `[]`. A 403, an unreachable endpoint,
a nonexistent bucket, and a genuinely clean bucket all produce the same empty result, and the requirements hook
renders all four as no warning at all.

**Evidence:** `modules/flysystem_aws/src/Iam/AwsSdkBucketIamProbe.php`:
```php
catch (\Throwable) {
  return [];
}
```
The inner helpers correctly return `NULL` for "unreadable" — that three-state care is then flattened at the
boundary. `src/Hook/FlysystemRequirements.php` treats `[]` as clean.

**Impact:** For a check whose purpose is security posture, silence must not be indistinguishable from safety.
An operator who deliberately grants the probe's IAM permissions and one who forgot see the same clean status
report. It also means C2 produced no visible symptom, which is why C2 survived the milestone.

**Fix:** Return a value object (or a `['conflicts' => [], 'determined' => bool]` shape) that carries whether the
probe completed, and add a distinct informational requirements entry — "IAM conflict detection could not run for
@scheme; grant s3:GetBucketPolicyStatus / s3:GetBucketOwnershipControls or ignore" — when it did not. Keep it
below warning severity so it does not cry wolf.

### L1. The `s3` driver inverts AsyncAws's own `sendChunkedBody` default — LOW *(verified)*

**What:** AsyncAws defaults `sendChunkedBody` to `'false'`. The driver declares `'default' => TRUE` and
transmits unconditionally, so the shipped default is chunked-on — the opposite of the SDK's, and the value that
does not work against MinIO, LocalStack or Floci.

**Evidence:** `vendor/async-aws/core/src/Configuration.php:94` — `self::OPTION_SEND_CHUNKED_BODY => 'false'` in
the defaults. `S3AdapterDriver::buildAdapter()` — `'sendChunkedBody' => (bool) ($config['send_chunked_body'] ?? TRUE)`.
The transmission itself is correct in both directions: `Configuration::create()` casts to string (`'1'` / `''`)
and `S3Client` reads it through `filter_var(..., FILTER_VALIDATE_BOOLEAN)`, so `FALSE` genuinely arrives — H3's
M4 defect does not recur here.

**Impact:** Minor and arguably deliberate (AWS proper benefits from chunked uploads). It means every
S3-compatible-endpoint user must know to uncheck a box, and it silently diverges from the SDK default a
developer would expect. Worth a decision and a documented rationale, not a code change on its own.

**Fix:** Either flip the declared default to `FALSE` (matching the SDK and the S3-compatible case) or keep it and
say so explicitly in the form description and README — "on by default; turn off for any non-AWS endpoint."

---

## What this review got right

Bounding the findings. Several things in M5 are notably stronger than M4, and the improvements are structural
rather than incidental:

- **Every M4 correction verifies as genuinely fixed, not theater.** C3's `preSave()` really strips secrets. C2's
  presigned gating is real. H2's requirements entries now carry `RequirementSeverity::Warning` and are wrapped in
  `$this->t()`. H3's chunked-body control maps onto a real, SDK-validated option. M4's `MisconfiguredFilesystemAdapter`
  and list-builder log flooding is deduped. I went looking for fixes that satisfied the letter of the finding and
  found none.
- **The `s3` driver is structurally better than `aws_s3`.** AsyncAws validates its option names and throws
  `InvalidArgument` on unknown keys, so M4's H3 defect class is impossible here — and the driver's option names
  (`sendChunkedBody`, `pathStyleEndpoint`, `accessKeyId`, `accessKeySecret`) all verify against
  `Configuration::AVAILABLE_OPTIONS`. Credentials resolve through the Key module from day one rather than being
  retrofitted.
- **`NoAclAsyncAwsS3Adapter` mirrors upstream instead of reinventing it.** Its `CopySource` uses
  `rawurlencode($bucket . '/' . $key)` — byte-identical to the stock `AsyncAwsS3Adapter::copy()`. That is the
  discipline whose absence produced M4's H4, and the docblock's "preserved, not reinvented" claim checks out
  against vendor source.
- **`plan-m5.md` §1's anti-#102-hole guard was honored.** All three claimed halves are actually pinned:
  `testUseAclSwitchResolvesAdapterClass()`, `testWrittenObjectsCarryDrupalMime()`, `testChecksumEqualsEtag()`. M4's
  pattern of claiming a half and proving it elsewhere-or-nowhere did not recur.
- **The IAM probe's verdict logic is careful and honest.** Verdicts derive from parsed response shapes and
  structured absence, never from SDK error-message substrings — the explicit H1 prohibition, respected. Excluding
  `PublicAccessBlock` because none of the in-scope APIs distinguishes "denying" from "unknown", and recording that
  on the ticket rather than shipping a guess, is exactly right.
- **The L3 endpoint validation is better than what I asked for.** It rejects rather than warns (a warning-that-probes
  still sends the request), covers loopback as well as link-local, and — best of it — documents its own residual:
  "no DNS resolution happens at validation time (TOCTOU + lookup cost), so a hostile hostname resolving into a
  protected range is a known residual." Naming the gap you are not closing is the standard.
- **The Floci per-class key-prefix rule (`plan-m5.md` §3) is a real diagnosis.** Two classes sharing a bucket prefix
  read each other's objects and pass locally against stale data, then fail in CI. Catching that and converting it into
  a mandatory constraint is the kind of fix that prevents a whole category of false-green.

## Verification

Run from `web/modules/custom/flysystem` unless noted:

```bash
# Gate table (project root)
ddev phpcs      # → empty output, exit 0
ddev phpstan    # → "[OK] No errors", exit 0

# C1 — throws added to the adapter-build path
grep -n "throw new" modules/flysystem_aws/src/Plugin/Flysystem/Adapter/AwsS3V3AdapterDriver.php   # → :528, :540
sed -n '/public function getAdapter/,/^  }$/p' src/Flysystem/FilesystemFactory.php                # → buildAdapter() unguarded
sed -n '540,575p' src/StreamWrapper/FlysystemStreamWrapper.php                                    # → getFilesystem() outside the catch

# C2 — the probe never resolves secret_key_id; C3 strips the literal secret
grep -rn "secret_key_id" --include="*.php" modules/flysystem_aws/src/Iam/    # → no output
grep -n -A10 "public function preSave" src/Entity/FlysystemFilesystem.php    # → unsets every secretKeyPaths() entry
grep -n "MockHandler\|overrideProbeFactory" \
  modules/flysystem_aws/tests/src/Kernel/BucketIamConflictDetectionTest.php  # → factory replaced in every leg

# H1 — three uncached calls per scheme, new client per call
sed -n '/public function getIamConflictsForDriver/,/^  }$/p' src/Flysystem/FilesystemFactory.php  # → no cache
sed -n '31,50p' modules/flysystem_aws/src/Iam/BucketIamProbeFactory.php                           # → new S3Client per call

# H2 — messenger warning with no permission gate
git diff 3f3d8d9..HEAD -- src/Flysystem/MisconfiguredFilesystemAdapter.php   # → addWarning(), no access check

# H4 — capability present, key absent from driver and schema
grep -n "presigned" modules/flysystem_asyncaws/config/schema/flysystem_asyncaws.schema.yml   # → no output
sed -n '222,240p' modules/flysystem_asyncaws/tests/src/Kernel/AsyncAwsSettingsPhpConfigTest.php  # → the probe leg

# L1 — SDK default vs driver default; transmission verified correct
grep -n "SEND_CHUNKED_BODY" /Users/lisaridley/development/drupal-flysystem-4.0/vendor/async-aws/core/src/Configuration.php
# → :57 available, :94 defaults to 'false'
grep -n "sendChunkedBody" /Users/lisaridley/development/drupal-flysystem-4.0/vendor/async-aws/s3/src/S3Client.php
# → :3946 filter_var(..., FILTER_VALIDATE_BOOLEAN)

# Scope
git diff --stat 3f3d8d9..HEAD | tail -1    # → 62 files changed, 7477 insertions(+), 107 deletions(-)
```

H3, M1 are `*(reviewed)*` — each carries its uncertainty in the finding body.

## Disposition

All items are new M5R / M6 ticket pairs (`plan-m5.md` records milestone **18, M5R Retrospective review
issues**, as the landing place for exactly this). `planning/plan-m5.md` is frozen once M5 closes; nothing
here amends it.

**Before M6 starts — M6 adds a third driver and will inherit these:**
1. **C2 + M2** — one pair. The probe must resolve credentials through the driver's resolver; fixing the
   duplication is the fix. Highest priority: a security feature that reports manufactured safety is worse
   than no feature.
2. **C1** — guard `buildAdapter()` in `getAdapter()`, and move `getFilesystem()` inside `getExternalUrl()`'s
   catch.
3. **H3** — read `use_provider_key_management` before resolving credentials; unset the credentials sub-tree
   on save when it is on.
4. **H2** — permission-gate the onscreen misconfiguration warning.

**Same milestone, not blocking M6:**
5. **H1** — cache and memoize the IAM verdict; set an explicit timeout and zero retries on the probe client.
6. **M3** — distinguish "could not determine" from "no conflicts" in the probe's return contract. Pairs
   naturally with H1 (both touch the probe boundary) but is a separate defect.
7. **M1** — extend the scrub to query-parameter credentials.
8. **H4** — decide presigned for `s3`, then make driver, schema, form and wrapper agree.

**Decision item, not a ticket:**
9. **L1** — flip the `sendChunkedBody` default to match the SDK, or keep it and document the rationale.
   Either is defensible; record which.
