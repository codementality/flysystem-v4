# M4 (flysystem_aws / aws_s3) — Independent Code Review

Status: Review, 2026-09-08. Scope: the M4 milestone code in the module repo
(`web/modules/custom/flysystem`, branch `4.0.x`), commits `473c882..3f3d8d9` (75 files, +10,873/-294),
judged against `planning/plan-m4.md` (§1 boundary, §5 constraints, §6 test plan, §8 exit criterion),
`planning/architecture.md` §4–§7/§11, `planning/config-and-upgrade.md` §2–§3, and the shipped
`README.md` (#244). Companion document: `planning/m4-project-review.md` (the ticket-to-plan
reconciliation) — see "Companion: the project review" at the end for the cross-reference table.

## Executive summary

**M4's exit criterion is met on the happy path and not met on the credential and public-URL paths:
the `aws_s3` driver is discovered, builds, and round-trips against Floci, but the two
configurations the shipped README tells operators to use — Key-module credentials, and a public
bucket fronted by CloudFront or `public_url_base` — do not work as documented.** Three CRITICAL
defects sit in the submodule's configuration surface, all of the same class: config keys that are
declared, formed, schema'd, documented, and never actually consumed. The Core-side M4 work
(streaming, stat truth, private-download scheme resolution, misconfiguration reporting) is
substantially sound; its defects are MEDIUM and below.

| Gate | Result |
|---|---|
| `ddev phpcs` (canonical `.ddev/commands/web/phpcs.xml.dist`) | **PASS** — empty output, exit 0 |
| `ddev phpstan` (canonical `.ddev/commands/web/phpstan.neon`) | **PASS** — `[OK] No errors`, exit 0 |
| `ddev phpunit` | **NOT RUN** — full-suite runtime is CI's leg (AGENTS.md rule 8 scopes local phpunit to changed files); no M4 test file was changed by this review |
| `ddev floci-check` | **NOT RUN** — no code change to verify against the emulator |

The gate table is why the findings below matter: **every one of them passes phpcs and phpstan.**
These are contract defects, not style defects, and the static gates cannot see them.

## Findings — by severity

- **CRITICAL — C1.** `credentials.secret_key_id` is never resolved; the README's recommended
  credential shape yields anonymous S3 requests.
- **CRITICAL — C2.** Every public `aws_s3` scheme saved through the admin form gets
  `presigned_expiry = 3600`, so public file URLs become expiring signed URLs and CloudFront /
  `public_url_base` are silently never used.
- **CRITICAL — C3.** A plaintext AWS secret access key entered in the form is persisted into the
  config entity and exported to config sync, contradicting the module's own documentation.
- **HIGH — H1.** #234 ships no IAM-conflict detection: nothing in the codebase reads bucket policy,
  ACL, or ownership state.
- **HIGH — H2.** All three `hook_runtime_requirements` entries omit `severity`, so every
  misconfiguration report renders as informational rather than as a warning.
- **HIGH — H3.** `send_chunked_body` is not an AWS SDK `S3Client` option, and `FALSE` can never be
  transmitted — the flag is inert in both directions.
- **HIGH — H4.** `NoAclAwsS3Adapter::copy()` does not URL-encode `CopySource`, so copying a key
  containing a space or `+` copies the wrong object or fails.
- **MEDIUM — M1.** Mime-on-write is wired only through the stream wrapper; `saveData()`, `copy()`
  and `move()` store league's finfo guess instead of Drupal's `filemime`.
- **MEDIUM — M2.** The `moveUploadedFile()` remote fallback drops PHP's `is_uploaded_file()`
  guarantee.
- **MEDIUM — M3.** `moveUploadedFile()` reports failure after a successful upload when the temp-file
  unlink fails, orphaning the object in the bucket.
- **MEDIUM — M4.** `realpath()`'s containment check is a raw string prefix match, so a sibling
  directory sharing the root's name prefix escapes the root.
- **MEDIUM — M5.** A persistent misconfiguration produces unbounded watchdog warnings — one per
  failed operation, plus one per listing row per page load.
- **MEDIUM — M6.** AWS SDK exception messages are logged verbatim, carrying the access key ID and
  canonical `StringToSign` to any user with "access site reports".
- **MEDIUM — M7 (performance).** Every owned-scheme mutation invalidates cache tags, so a bulk
  migration pays one `cachetags` write per file.
- **LOW — L1.** Requirements titles and descriptions are raw interpolated strings, not `$this->t()`.
- **LOW — L2.** `NoAclAwsS3Adapter::copy()` computes a `$visibility` value it never uses.
- **LOW — L3.** The test-connection AJAX callback builds an adapter from raw user input with
  validation explicitly disabled — an admin-gated blind SSRF.

---

## Findings detail

### C1. `credentials.secret_key_id` is declared, formed, schema'd, documented — and never read — so the README's recommended credential path issues anonymous S3 requests — CRITICAL *(verified)*

**What:** The driver declares `credentials.secret_key_id`, the form marks it `#required` whenever
provider key management is off, the config schema types it, `README.md:62` and `README.md:80` present
it as the settings.php shape, and `README.md:140` describes it as the "Key module reference for the
secret" — but no production code anywhere resolves it into a credential. `clientCredentials()`
requires a literal `credentials.secret`, so an operator who follows the documentation (set
`secret_key_id`, leave `secret` empty) gets `NULL` credentials and the SDK's default provider chain.

**Evidence:** `modules/flysystem_aws/src/Plugin/Flysystem/Adapter/AwsS3V3AdapterDriver.php:397-405`:

```php
$credentials = $config['credentials'] ?? NULL;
if (!is_array($credentials) || empty($credentials['key']) || empty($credentials['secret'])) {
  return NULL;
}
```

The Key module is a hard dependency in both `flysystem_aws.info.yml` (`key:key`) and
`composer.json` (`drupal/key: ^1.22`), yet it is never used. Verified by exhaustive grep over
production code:

```
$ grep -rn "secret_key_id\|KeyRepository\|key.repository" --include="*.php" src/ modules/ | grep -v "/tests/"
modules/flysystem_aws/src/Plugin/Flysystem/Adapter/AwsS3V3AdapterDriver.php:156:          'secret_key_id' => [
modules/flysystem_aws/src/Plugin/Flysystem/Adapter/AwsS3V3AdapterDriver.php:281:    $form['credentials']['secret_key_id'] = [
modules/flysystem_aws/src/Plugin/Flysystem/Adapter/AwsS3V3AdapterDriver.php:286:      '#default_value' => $config['credentials']['secret_key_id'] ?? '',
modules/flysystem_aws/src/Plugin/Flysystem/Adapter/AwsS3V3AdapterDriver.php:300:          ':input[name="config[credentials][secret_key_id]"]' => ['empty' => TRUE],
```

Four hits, all in the driver's own key declaration and form. Zero consumers. No `key.repository`
service reference exists in the module.

**Impact:** Every site that configures credentials the documented way silently authenticates as
whatever the SDK's default chain finds — the instance role, ambient environment variables, or
nothing. On a developer machine or a non-AWS host that means anonymous requests and a blanket 403 on
every read and write. The failure surfaces as a permission error from S3, never as a configuration
error, so the operator has no signal pointing at the credential they entered. This is the defect
class the milestone's own retrospective §2.1 names: "plan words posed as coverage" — the key exists
in every layer except the one that uses it.

**Fix:**
- Inject `key.repository` into the driver (or a small credential-resolver service, so the `s3` and
  `sftp` submodules can share it) and resolve `credentials.secret_key_id` to the Key entity's value
  in `clientCredentials()`, before the `empty($credentials['secret'])` check.
- Treat the pair as XOR at resolution time as the entity validator already does at save time: a
  present `secret_key_id` whose Key entity is missing or empty must produce a logged configuration
  error, never a silent fall-through to the provider chain.
- Add a Kernel leg that configures `secret_key_id` only, and asserts the built `S3Client` carries the
  resolved credentials — it fails on current code.

### C2. Every public `aws_s3` scheme saved through the admin form gets `presigned_expiry = 3600`, so its public URLs become expiring signed URLs and CloudFront is never used — CRITICAL *(reviewed)*

**What:** `presigned_expiry` declares `'default' => 3600` and the form renders it as a `number` field
with `'#default_value' => $config['presigned_expiry'] ?? 3600`, gated only by `#states` (client-side
CSS visibility). A hidden `#states` field is still in the DOM and still submitted, and nothing unsets
it server-side — so saving a **public** scheme's form persists `presigned_expiry = 3600`.
`getExternalUrl()` then tests `presigned_expiry` **before** `public_url_base` and CloudFront and
returns from the presigned branch, so both are dead for every form-configured public scheme.

**Evidence:** `modules/flysystem_aws/src/Plugin/Flysystem/Adapter/AwsS3V3AdapterDriver.php:218-229`
renders the field with a `#states` visibility condition and no `#access` gate, no server-side unset,
and a hard-coded fallback of `3600`. `src/StreamWrapper/FlysystemStreamWrapper.php` orders the
branches presigned-first:

```php
if ($presignedExpiry !== NULL) {
  ...
  return $filesystem->temporaryUrl($key, $expiresAt);
}
$base = $publicUrlBase === NULL ? '' : rtrim($publicUrlBase, '/');
if ($base === '' && $cloudfrontDomain !== NULL) { ... }
```

`src/Entity/FlysystemFilesystem.php:216` does not stop the save: `$hasPresigned` is TRUE and
`driverSupportsTemporaryUrls()` returns TRUE for `aws_s3` (`AwsS3V3Adapter` implements
`TemporaryUrlGenerator`, `vendor/league/flysystem-aws-s3-v3/AwsS3V3Adapter.php:42`), so no violation
fires. `AwsS3ConfigFormSaveTest::testSavePersistsFullConfigShape()` performs a real form save of a
public scheme and asserts eight keys — `presigned_expiry` is not among them, so the injected value is
unasserted in either direction. Marked *(reviewed)*: I traced the form/save/URL path in source but did
not execute the save.

**Impact:** The module's headline use case — a public S3 bucket behind CloudFront — is silently
broken whenever the scheme is configured through the UI rather than settings.php. Every file URL
becomes a unique, SigV4-signed, one-hour URL, which (a) defeats CDN and Drupal page-cache reuse
because the query string changes per render, (b) produces broken images an hour after any cached
render array or cached HTML page is written, and (c) makes the CloudFront distribution the operator
configured and paid for entirely unused, with no warning anywhere. The `use_cloudfront` checkbox
appears to work — the value round-trips into config — while having no effect.

**Fix:**
- Do not materialize `presigned_expiry` for a public scheme. Either drop the `#default_value`
  fallback so the field submits empty unless the operator sets it, or unset the key in the driver's
  submit path (and in a `validateConfigurationForm()`) when `default_visibility !== 'private'`.
  `#states` is presentation and must never be the only gate on a persisted value.
- Decide and pin the precedence explicitly. `plan-m4.md` §2.1 records "presigned > base > CloudFront";
  if that is the intent, an explicitly-set `public_url_base` or `use_cloudfront` on a public scheme
  should at minimum raise a requirements warning that presigned wins, because the current silent
  ordering is indistinguishable from a bug.
- Add a Functional leg that saves a public scheme through the form with `use_cloudfront` + a domain,
  and asserts `getExternalUrl()` returns the CloudFront URL. It fails on current code.

### C3. A plaintext AWS secret access key entered in the form is persisted into the config entity and exported to config sync — CRITICAL *(verified)*

**What:** The `secret: TRUE` marker on `credentials.secret` is consumed only by the entity's
XOR-validation helpers. Nothing strips the secret from the entity before save, the config schema
types it as a plain persisted `string`, and the form renders it as `#type => textfield` — so the
secret is written to `flysystem.filesystem.<scheme>.yml`, appears in `config/sync` exports and in any
config diff, and is echoed back in cleartext on every subsequent edit-form render. The driver's own
docblock states the opposite: "The secret is never exported to config"
(`AwsS3V3AdapterDriver.php:307`), and so does `README.md:139` ("never exported").

**Evidence:** Every `secret` reference in Core production code is validation-only — there is no strip,
no `unset`, no pre-save hook:

```
$ grep -rn "secret" --include="*.php" src/
src/Form/FlysystemFilesystemForm.php:549,550   (comments about the XOR rule)
src/Entity/FlysystemFilesystem.php:265-358     (isSecretSet / secretPairsFromDriverPlugin /
                                                secretKeyPaths — all validation)
src/Plugin/Flysystem/Adapter/AdapterDriverPluginBase.php:16,71  (docblocks)
```

`modules/flysystem_aws/config/schema/flysystem_aws.schema.yml` declares
`credentials.secret: {type: string}` as a persisted mapping key. `AwsS3ConfigFormSaveTest` contains
no assertion that the saved entity omits `credentials.secret` — grep for `secret` in that file returns
only two docblock lines (24, 236).

**Impact:** A long-lived AWS secret access key lands in version-controlled configuration. Anyone with
repository read access, anyone who can run a config export, and anyone who can view the scheme's edit
form obtains live S3 credentials. `config-and-upgrade.md`'s preserved-shape contract is satisfied in
letter and violated in intent: the shape is preserved, the secret handling the shape presumes is
absent. This is the direct consequence of C1 — the Key-module path being non-functional is exactly
what pushes an operator to type the secret into the form instead.

**Fix:**
- Strip every `secretKeyPaths()` value from the entity's `config` array before save (a `preSave()`
  on `FlysystemFilesystem`, driven by the existing `secret: TRUE` markers so it covers `s3` and
  `sftp` in M5/M6 for free), and remove `credentials.secret` from the persisted config schema.
- Render the field as `#type => password` with no `#default_value`, so an existing secret is never
  echoed back.
- Once C1 is fixed, the form's secret field should write the value into a Key entity and store only
  the reference — the shape the README already documents.
- Add a leg asserting that a form save with a plaintext secret produces an entity whose
  `config.credentials.secret` is absent. It fails on current code.

### H1. #234 ships no IAM-conflict detection — nothing reads bucket policy, ACL, or ownership state — HIGH *(verified)*

**What:** Commit `b599b12` is titled "Core: adapter config conflicts with bucket IAM — UI warning +
logged conflict", and `plan-m4.md` §2.1 records #234/#235 as "IAM-conflict detection (LoggingFilesystem
reactive catch + base-over-private hook check)". Neither mechanism inspects IAM. `LoggingFilesystem`
logs *any* failed data-plane operation with the exception message — it cannot distinguish an IAM
refusal from a typo'd bucket name, a network error, or a missing object. The "base-over-private hook
check" compares two Drupal config values (`visibility === 'private'` and a non-NULL `public_url_base`)
and never contacts S3.

**Evidence:** No bucket-state introspection exists anywhere in production code:

```
$ grep -rn "GetBucketPolicy\|GetBucketAcl\|getBucketAcl\|PolicyStatus\|ObjectOwnership" \
    --include="*.php" src/ modules/ | grep -v tests
(no output)
```

`src/Flysystem/LoggingFilesystem.php:222-236` logs `$e->getMessage()` for every operation with no
classification. `src/Hook/FlysystemRequirements.php:44-50` is the "base-over-private" check — pure
config comparison.

**Impact:** The ticket's stated objective is unmet while the ticket is closed. An operator whose
bucket policy actually contradicts their scheme configuration (a private scheme on a
public-read bucket, a public scheme on a bucket that denies public access, `use_acl = TRUE` against
BucketOwnerEnforced) gets no warning at configuration time and, at runtime, a generic
"operation failed" line indistinguishable from a dozen unrelated causes. The milestone's own
retrospective §2.1 names this failure mode — "no ticket owned the runtime wiring and no test pinned
it" — and it recurred here under a ticket that appeared to own it.

**Fix:** This is a scope correction, not a patch. Either:
- File an M5+ ticket pair that implements real detection — a `GetBucketPolicyStatus` /
  `GetBucketOwnershipControls` probe on the connection-test path and in `hook_runtime_requirements`,
  comparing the bucket's actual public-access and ACL-enforcement state against the scheme's
  `default_visibility` and `use_acl` — noting that it corrects #234; or
- Amend #234's record to state plainly that what shipped is failure logging plus a config-internal
  consistency check, and rename the surfaces accordingly so no future reader believes IAM state is
  being read. Do not leave the ticket title asserting a capability the code does not have.

### H2. Every `hook_runtime_requirements` entry omits `severity`, so no misconfiguration report renders as a warning — HIGH *(verified)*

**What:** All three requirement entries supply only `title` and `description`. Drupal's status report
treats a missing `severity` as `REQUIREMENT_INFO`, which renders in the informational section rather
than as a warning. Two of the three entries are M4 additions whose ticket contracts (#232, #234) call
for a "UI warning".

**Evidence:** `src/Hook/FlysystemRequirements.php:44-67` — the complete set of entries, none carrying
a `severity` key:

```php
$requirements['flysystem_baseoverprivate_' . $scheme] = [
  'title' => "Flysystem scheme $scheme sets a public URL base it can never use",
  'description' => "...",
];
```

**Impact:** The one surface designed to catch a settings.php misconfiguration that bypasses entity
validation (the C9/#136 rationale in the file's own docblock) does not visually distinguish itself
from routine status information. An operator scanning `/admin/reports/status` for problems sees no
warning, which is the entire purpose of the hook. The `flysystem_nobase_` entry inherits this from M3,
so the fix covers all three.

**Fix:** Add `'severity' => RequirementSeverity::Warning` (Drupal 11.4 enum; `REQUIREMENT_WARNING`
on older cores) to all three entries, and add a leg asserting the rendered status report marks them
as warnings.

### H3. `send_chunked_body` is not an AWS SDK option, and `FALSE` can never be transmitted — HIGH *(verified)*

**What:** Two defects with one root cause — the key is plumbed as though the SDK consumed it, and the
plumbing is one-way. `send_chunked_body` does not exist anywhere in `aws/aws-sdk-php`, so passing it
into the `S3Client` constructor is a no-op the SDK silently ignores. Separately, the driver only ever
sets it when truthy, so the `FALSE` value the form's own description says is required for
MinIO/Floci is unrepresentable.

**Evidence:** Absent from the entire vendor tree:

```
$ grep -rl "send_chunked_body" /Users/lisaridley/development/drupal-flysystem-4.0/vendor/
(no output — zero files)
```

`AwsS3V3AdapterDriver.php:62-64` shows the one-way plumbing:

```php
if (!empty($config['send_chunked_body'])) {
  $options['send_chunked_body'] = TRUE;
}
```

The form description at line 216 states "Required for MinIO and the Floci test emulator
(`send_chunked_body` FALSE)", and `FlociIntegrationTestBase.php:192` and
`AwsS3SettingsPhpConfigTest.php:426` both set it to `FALSE` — a value the driver drops on the floor.
The Floci legs pass anyway, which proves the flag has no effect in either direction.

**Impact:** A declared, formed, schema'd, README-documented, and test-exercised configuration key does
nothing. Operators on MinIO or LocalStack who hit a chunked-encoding rejection will set this flag,
observe no change, and have no way to discover why. The tests setting it to `FALSE` create false
confidence that the MinIO path is covered.

**Fix:** Identify the real SDK control for the behavior — on current SDK versions the option that
stops the `aws-chunked` streaming trailer that MinIO and LocalStack reject is
`request_checksum_calculation => 'when_required'` — and either map `send_chunked_body: FALSE` onto it
or replace the key with one named after what it actually does. Pass the resolved value
unconditionally (`$options[...] = (bool) $config[...]`), never only when truthy, so `FALSE` is
transmissible. Pin it with a leg that inspects the constructed client's configuration, not just the
config round-trip.

### H4. `NoAclAwsS3Adapter::copy()` does not URL-encode `CopySource`, so copying a key with a space or `+` copies the wrong object or fails — HIGH *(reviewed)*

**What:** S3's `CopySource` parameter is a URL-encoded path. The subclass builds it by raw string
concatenation, so any key containing a character with URL meaning is misinterpreted by S3: a space
breaks the request, and a literal `+` is decoded as a space, silently copying a different object (or
404ing).

**Evidence:** `modules/flysystem_aws/src/Flysystem/NoAclAwsS3Adapter.php` — both the single-part and
multipart branches:

```php
+ ['CopySource' => $this->bucket . '/' . $sourceKey]
...
$copy = new MultipartCopy($this->client, $this->bucket . '/' . $sourceKey, [...]);
```

This is a subclass of a method the parent implements differently, so the parent's handling is not
inherited. Marked *(reviewed)*: read from source against the S3 `CopyObject` contract; not executed
against a live bucket.

**Impact:** `use_acl = FALSE` is the **default**, so this is the copy path every modern-bucket site
takes. Drupal generates keys with spaces routinely — uploaded filenames pass through
`file_munge_filename()`, which does not remove spaces. Every `file_system->copy()` /
`move()` of such a file within one `aws_s3` scheme (the native same-adapter branch, which is the
common case) either fails or copies the wrong bytes. Image-style derivative generation and media
duplication are the likely first casualties.

**Fix:** URL-encode the source key path segments before concatenation —
`$this->bucket . '/' . rawurlencode($sourceKey)` is wrong for the `/` separators; encode per segment,
or use the SDK's own helper as the parent path does. Add a leg that copies `dir/a file+name.txt`
within one `aws_s3` scheme and asserts the destination content matches — it fails on current code.

### M1. Mime-on-write is wired only through the stream wrapper, so `saveData()`, `copy()` and `move()` store league's finfo guess instead of Drupal's `filemime` — MEDIUM *(verified)*

**What:** The #19-split contract is that a stored object's `Content-Type` equals Drupal's `filemime`.
Only one call site passes it. Every write that goes through the decorated `file_system` service
instead of the stream wrapper writes with an empty operation config, so the adapter falls back to
league's own `FinfoMimeTypeDetector`.

**Evidence:** One `mimetype` producer in the whole module:

```
$ grep -rn "mimetype" --include="*.php" src/
src/StreamWrapper/FlysystemStreamWrapper.php:1114:  ['mimetype' => $this->guessMimeType($this->uri ?? $this->writeTarget)],
```

`src/File/FlysystemFileSystem.php:180` — `saveData()`: `$filesystem->write($target, (string) $data);`
(no config). `transferContent()`: `$filesystem->writeStream($destination_target, $sourceHandle, []);`
(explicit empty config). `AwsS3MimeOnWriteTest` exercises `file_put_contents()` only (lines 63, 107)
— the wrapper seam — so the decorated-`file_system` seam is unasserted.

**Impact:** Objects written by `copy()`, `move()`, and `saveData()` carry a `Content-Type` derived
from league's finfo rather than Drupal's guesser chain, which modules alter and which handles
extension-driven cases finfo gets wrong. `saveData()` is the worst case: finfo sees only a content
string, so a generated CSV or SVG can be stored as `text/plain`, and S3 serves that `Content-Type` to
browsers verbatim. The divergence is invisible until someone inspects object metadata.

**Fix:** Pass `['mimetype' => ...]` from Drupal's `file.mime_type.guesser` at all three
`FlysystemFileSystem` write sites, resolved from the destination URI (and from the destination
filename for `saveData()`). Extend `AwsS3MimeOnWriteTest` with a leg per seam — `saveData()` and a
cross-scheme `copy()` — asserting the stored `Content-Type`; both fail on current code.

### M2. The `moveUploadedFile()` remote fallback drops PHP's `is_uploaded_file()` guarantee — MEDIUM *(verified)*

**What:** `parent::moveUploadedFile()` uses PHP's `move_uploaded_file()`, which refuses any path that
was not an HTTP upload temp file. For remote destinations the parent always fails (by design — remote
wrappers are `STREAM_IS_URL`), and the M4 fallback then copies from `$filename` with a plain `fopen`
and no upload check.

**Evidence:** `src/File/FlysystemFileSystem.php`, the new `moveUploadedFile()` override:

```php
if (parent::moveUploadedFile($filename, $uri)) { return TRUE; }
if (!$this->isFlysystemUri((string) $uri) || $this->realpath((string) $uri) !== FALSE) { return FALSE; }
$source = @fopen((string) $filename, 'rb');
```

**Impact:** For every remote-scheme upload — i.e. all of them, since remote is the point of this
module — the safety property that the source is genuinely an upload temp file is gone. Any caller that
can influence `$filename` gains arbitrary local-file read into the destination bucket. In core's own
upload flow `$filename` comes from `$_FILES[...]['tmp_name']` and is not attacker-controlled, so this
is a defense-in-depth regression rather than a live exploit — but it silently removes a guard the
local path keeps, on the path that is now the default.

**Fix:** Guard the fallback with `is_uploaded_file($filename)`. Kernel tests that fabricate uploads
will need the guard relaxed under `drupal_valid_test_ua()` (core takes the same approach in its own
upload handling) — do it explicitly, with a comment, rather than by omission.

### M3. `moveUploadedFile()` reports failure after a successful upload when the temp-file unlink fails — MEDIUM *(reviewed)*

**What:** The fallback's return value is the result of deleting the source temp file, not the result
of transferring the bytes. If the copy succeeds and `unlink()` fails, the method returns FALSE.

**Evidence:** `src/File/FlysystemFileSystem.php`, last line of the fallback:
`return @unlink((string) $filename);`. Marked *(reviewed)*: read from source; not reproduced (it needs
an undeletable temp file).

**Impact:** The caller treats the upload as failed and reports an error to the user, while the object
is already in the bucket. The result is an orphaned object no file entity references, plus a
user-visible failure for an operation that succeeded. Restrictive temp-directory permissions or an
open handle on the temp file are enough to trigger it.

**Fix:** Return TRUE when the transfer succeeded, and log an unlink failure as a warning rather than
converting it into an operation failure.

### M4. `realpath()`'s containment check is a raw string prefix match, so a sibling directory sharing the root's prefix escapes the root — MEDIUM *(reviewed)*

**What:** The containment guard compares the resolved path to the root with `str_starts_with`, which
is a character-prefix test, not a path-boundary test. With root `/var/www/files`, a target of
`../files-evil/x` resolves to `/var/www/files-evil/x`, which passes.

**Evidence:** `src/StreamWrapper/FlysystemStreamWrapper.php`, in `resolveLocalPath()`:

```php
$directory = realpath($root);
if ($directory === FALSE || !str_starts_with($realpath, $directory)) {
  return FALSE;
}
```

The method's own docblock claims it "adds the guards core does not have"; this particular guard is
inherited from core `LocalStream::getLocalPath()` unchanged, including the weakness. Marked
*(reviewed)*: the string semantics are certain, but I did not construct the sibling directory to
demonstrate it.

**Impact:** `realpath()` is the resolution feeding `chmod()` (`applyMetadataMode`), `touch()`
(`applyMetadataTouch`), `flock()` (`stream_lock`), and the image-toolkit staging path. A target that
escapes the configured root reaches all four. Exploitation needs a sibling directory whose name
extends the root's name and a caller that passes a traversing target, so the practical risk is low —
but this is the security boundary of a LOCAL scheme, and it does not hold as written.

**Fix:** Compare on a path boundary: `str_starts_with($realpath, rtrim($directory, '/') . '/')`, with
`$realpath === $directory` accepted separately for the root itself. Add a leg asserting a
sibling-prefix target returns FALSE.

### M5. A persistent misconfiguration produces unbounded watchdog warnings — MEDIUM *(verified)*

**What:** Three surfaces log the same standing condition repeatedly with no dedupe or rate limit:
`FilesystemFactory::getAdapter()` logs once per request when it returns the
`MisconfiguredFilesystemAdapter`; `LoggingFilesystem::logFailure()` then logs again for every
operation attempted against it (each of which throws); and
`FlysystemFilesystemListBuilder::reportMisconfiguration()` logs once per row on every load of the
collection page.

**Evidence:** `src/Flysystem/FilesystemFactory.php:341-349` (per-request warning);
`src/Flysystem/LoggingFilesystem.php:222-236` (per-operation warning, invoked from all ten wrapped
data-plane methods); `src/Entity/FlysystemFilesystemListBuilder.php` — `reportMisconfiguration()` is
called from `buildRow()`, which runs per entity per page build, and both adds a messenger warning and
writes a watchdog entry.

**Impact:** One misconfigured scheme on a page rendering fifty images produces fifty-plus warning rows
per request, which fills the `watchdog` table and buries the diagnostics an operator needs. On the
admin listing, the same warning is added to the messenger once per misconfigured row, so a site with
several broken schemes shows a wall of duplicate messages. Logging from `buildRow()` is also a side
effect in a render-build method, which makes the volume scale with rendering rather than with events.

**Fix:** Dedupe per request — a static/instance set of already-reported scheme keys in
`LoggingFilesystem` and in the list builder, so a standing condition logs once. Move the list
builder's reporting out of `buildRow()` into `render()` (or `load()`), aggregating one message across
all rows.

### M6. AWS SDK exception messages are logged verbatim, carrying the access key ID and canonical `StringToSign` — MEDIUM *(reviewed)*

**What:** Four log sites interpolate `$e->getMessage()` unfiltered. AWS `S3Exception` messages embed
the full error response body, which for `SignatureDoesNotMatch` includes `AWSAccessKeyId` and the
canonical `StringToSign` (the signed request, including headers and query parameters).

**Evidence:** `src/Flysystem/LoggingFilesystem.php:229` (`'@reason' => $e->getMessage()`);
`src/Flysystem/FilesystemFactory.php:486-492` (`testConnection`) and `529-536`
(`testConnectionForDriver`). The response messages themselves are correctly sanitized — only the log
carries the detail — which is the deliberate design; the gap is that watchdog is a lower trust
boundary than the code assumes. Marked *(reviewed)*: the SDK's error-message composition is not
reproduced here.

**Impact:** Watchdog is readable by any user with "access site reports", a permission commonly granted
beyond the site owner, and is frequently shipped to external log aggregators. The access key ID is
not the secret, and the `StringToSign` is not reversible to the secret — so this is credential
metadata disclosure and request-shape disclosure to a wider audience than intended, not a key leak.

**Fix:** Log `$e::class` plus a truncated, filtered message for SDK exceptions, or strip the
`<StringToSign>` and `<AWSAccessKeyId>` elements before logging. Keep the full detail behind a debug
setting if it is needed for support.

### M7. Every owned-scheme mutation invalidates cache tags, so a bulk migration pays one `cachetags` write per file — MEDIUM (performance) *(reviewed)*

**What:** `FlysystemFileSystem::invalidate()` is called on every mutation — one to three times per
`copy()`/`move()`, once per `saveData()`/`delete()`/`rmdir()` — and each call reaches
`StatCache::invalidate()`, which builds one ancestor tag per path segment and calls
`invalidateTags()`.

**Evidence:** `src/File/FlysystemFileSystem.php` — `invalidate()` calls
`$this->statCache->invalidate($uri)`; `src/Cache/StatCache.php` — `invalidate()` builds
`ancestorTags($uri)` (one tag per path depth level) and calls `$this->cache->invalidateTags($tags)`.
Marked *(reviewed)*: this is a scaling analysis of the write path, not a measured benchmark.

**Impact:** Cache-tag invalidation is not a local operation — it writes to the `cachetags` table and
invalidates matching entries across every cache bin. The M8 migration submodule moves files in bulk;
at one invalidation per file (times path depth in tags) a 100,000-file migration performs 100,000
tag-invalidation round trips, each rippling through the render and page caches. Correctness is fine;
throughput is the concern, and M8 is where it will surface.

**Fix:** Not a defect to patch now — a design item to settle before M8. Options: a batch/deferred
invalidation mode the migration path can wrap around a run (collect tags, invalidate once at the
end), or a coarser tag granularity (per scheme plus per directory, not per full ancestor chain).
Worth a benchmark leg that times 1,000 sequential `saveData()` calls with and without stat-cache
invalidation, so the decision has a number behind it.

### L1. Requirements titles and descriptions are raw interpolated strings, not `$this->t()` — LOW *(verified)*

**What:** All three requirement entries build user-facing text by PHP string interpolation, so none is
translatable. `plan-m4.md` §5 requires "English user-facing strings in `$this->t()`".

**Evidence:** `src/Hook/FlysystemRequirements.php:46-47`, `55-56`, `63-64` — e.g.
`'title' => "Flysystem scheme $scheme cannot resolve external URLs"`.

**Impact:** Untranslatable status-report text. The `flysystem_nobase_` entry predates M4; the two new
entries repeat the pattern.

**Fix:** Wrap in `$this->t()` with `@scheme` placeholders (add `StringTranslationTrait`). Fixing this
alongside H2 is one change to the same three array literals.

### L2. `NoAclAwsS3Adapter::copy()` computes a `$visibility` value it never uses — LOW *(verified)*

**What:** `copy()` resolves a visibility from the operation config and the scheme default, then never
reads the variable. It is dead code that reads as visibility retention which, by this adapter's
design, cannot happen.

**Evidence:** `modules/flysystem_aws/src/Flysystem/NoAclAwsS3Adapter.php` — `$visibility` is assigned
in two branches and never referenced again in the method.

**Impact:** None functionally — `setVisibility()` is deliberately a no-op here. The harm is to the
reader: it implies the copy carries visibility forward.

**Fix:** Delete the two assignments and keep the explanatory comment.

### L3. The test-connection AJAX callback builds an adapter from raw user input with validation explicitly disabled — LOW *(verified)*

**What:** `testConnectionCallback()` reads `$form_state->getUserInput()` — unvalidated raw POST — and
passes it into `buildAdapter()`, which constructs an `S3Client` with an arbitrary `endpoint`, then
performs a live `fileExists()` against it. The button carries `'#limit_validation_errors' => []`, so
no validation runs first.

**Evidence:** `src/Form/FlysystemFilesystemForm.php`, `testConnectionCallback()`:
`$config = isset($input['config']) && is_array($input['config']) ? $input['config'] : [];` then
`$this->filesystemFactory->testConnectionForDriver($driver, $config);`.

**Impact:** An authenticated user with the flysystem administration permission can make the site issue
outbound HTTP requests to any host and port. This is blind SSRF — the response is not reflected, only
a generic success/failure — and configuring an arbitrary endpoint is the feature's whole purpose, so
the finding is about the missing boundary, not the capability. The correctly sanitized failure
message is what keeps this at LOW.

**Fix:** Accept it as intended behavior and document it as an administrative-trust capability, or
validate the submitted endpoint (scheme allowlist, reject link-local and loopback ranges) before the
probe. Either way, record the decision rather than leaving it implicit.

---

## What this review got right

Bounding the findings above — the following are solid, and several are notably better than the M3
baseline:

- **Both static gates are genuinely clean.** `phpcs` (canonical config) and `phpstan` level 8 pass
  with no exclusions added for the new code. Every finding here is a contract defect the gates
  structurally cannot catch, which is the correct division of labor.
- **The Floci harness is honest test infrastructure.** `FlociIntegrationTestBase` fails rather than
  skips when the emulator is absent, and asserts bucket existence rather than provisioning it —
  so a leg cannot pass over a broken environment. The CI job's inline provisioning with the
  no-`$` constraint (so GitLab expands nothing and the committed lines are byte-for-byte what runs)
  is a careful solution to a real problem.
- **The private-download rewrite (#182) is a clear improvement.** Carrying the owning scheme in the
  URL replaced a per-request probe of every private scheme with exactly one resolution, eliminating
  both the first-match-wins ambiguity and the N round trips. `hook_file_download` access checks and
  the deny-by-default on zero claims are correctly preserved on both the adapter and core paths.
- **The `transferContent()` streaming rewrite (H2/#178) is correct end to end.** Source and
  destination handles, `finally`-based cleanup on every path, and no whole-file buffering — peak
  memory no longer scales with file size, and `copy()`/`move()` now return the URI that actually
  holds the content (C2/#176).
- **`url_stat()` truth (C1/#172) is thorough.** Returning FALSE for a missing object, refusing to
  write the negative into the persistent cache, *and* purging pre-fix fabricated type-0 entries on
  read is the complete fix, not just the forward-looking half.
- **The `uid`/`gid` and read-only write-bit corrections (#160) fix a real, environment-dependent
  defect** — the hardcoded uid 0 that made `is_writable()` lie to every non-root process, which CI's
  root execution had masked. Diagnosing that from a local-only failure was the right catch.
- **`MisconfiguredFilesystemAdapter` is the right shape.** Never throwing a config error from the
  resolution path, while failing loudly at the point of use, honors architecture §5 boundary 3
  precisely.
- **`NoAclAwsS3Adapter` preserves multipart parity rather than reinventing it** — the threshold,
  the option plumbing, and the unknown-size-goes-multipart rule all mirror the SDK. The subclass's
  docblock explaining *why* every private parent field is re-held is the kind of note that saves a
  future reader an hour.

## Verification

Commands run for this review, from `web/modules/custom/flysystem` unless noted:

```bash
# Gate table (run from the project root)
ddev phpcs                       # → empty output, exit 0
ddev phpstan                     # → "[OK] No errors", exit 0

# C1 — no consumer of secret_key_id, no Key module usage in production code
grep -rn "secret_key_id\|KeyRepository\|key.repository" --include="*.php" src/ modules/ \
  | grep -v "/tests/"
# → 4 hits, all in AwsS3V3AdapterDriver's own key declaration and form

# C3 — no secret stripping anywhere in Core production code
grep -rn "secret" --include="*.php" src/
# → validation helpers and docblocks only; no unset/strip/preSave

# H1 — no bucket IAM introspection anywhere in production code
grep -rn "GetBucketPolicy\|GetBucketAcl\|getBucketAcl\|PolicyStatus\|ObjectOwnership" \
  --include="*.php" src/ modules/ | grep -v tests
# → no output

# H2 — no severity key on any requirements entry
cat src/Hook/FlysystemRequirements.php   # → three entries, title + description only

# H3 — send_chunked_body absent from the entire vendor tree
grep -rl "send_chunked_body" /Users/lisaridley/development/drupal-flysystem-4.0/vendor/
# → no output (zero files)

# M1 — one mimetype producer in the module
grep -rn "mimetype" --include="*.php" src/
# → FlysystemStreamWrapper.php:1114 only

# Scope of the reviewed change set
git -C web/modules/custom/flysystem diff --stat 65a9ad8..HEAD | tail -1
# → 75 files changed, 10873 insertions(+), 294 deletions(-)
```

Reproducing C2 and H4 requires legs that do not yet exist; both are specified in their `**Fix:**`
blocks and both fail on current code.

## Disposition

Every item below is a **new M5+ ticket pair** (T# reds first, then implementation), each citing the
M4 ticket it corrects. `plan-m4.md` is frozen under the milestone-immutability rule, so nothing here
amends it — corrections live in the later milestone, per the governance note precedent set by the M3
review.

**Before any further submodule work (the M5 `s3` driver will inherit all three):**
1. **C1** — resolve `secret_key_id` through `key.repository`. Blocks C3's final shape.
2. **C3** — strip secrets from persisted config; `#type => password`; drop `credentials.secret` from
   the config schema. Depends on C1.
3. **C2** — stop materializing `presigned_expiry` on public schemes; pin the URL precedence with a
   leg.

**Same milestone, not blocking the above:**
4. **H4** — encode `CopySource` in `NoAclAwsS3Adapter::copy()`. Independent, small, and on the
   default code path.
5. **H3** — replace `send_chunked_body` with the real SDK control and make it two-way.
6. **H2 + L1** — one change to the same three requirement literals: add `severity`, wrap in
   `$this->t()`.
7. **M1** — pass `mimetype` at the three `FlysystemFileSystem` write sites.
8. **M2 + M3** — `moveUploadedFile()`: restore the upload guard, and stop returning the unlink
   result as the operation result. One ticket, two sub-bullets.
9. **M4** — path-boundary containment check in `resolveLocalPath()`.
10. **M6** — filter SDK exception detail before it reaches watchdog.
11. **M5** — per-request dedupe for standing-misconfiguration logging; move the list builder's
    reporting out of `buildRow()`.
12. **L2** — delete the dead `$visibility` assignments.

**Scope corrections, needing your decision rather than a patch:**
13. **H1** — either file real IAM-conflict detection as an M5+ pair, or amend #234's record and
    rename its surfaces to describe what actually shipped. Do not leave the closed ticket asserting
    a capability the code does not have.
14. **L3** — record the test-connection SSRF surface as an accepted administrative-trust capability,
    or add endpoint validation. Either is defensible; leaving it undecided is not.

**Deferred to M8 planning, with a number attached first:**
15. **M7** — benchmark stat-cache tag invalidation under bulk mutation and decide on batching or
    coarser tags before the migration submodule is built.

---

## Companion: the project review (part 1)

The ticket-to-plan reconciliation is in **`planning/m4-project-review.md`**. Its headline: milestone #15
is 0 open / 59 closed, no ticket closed with an open blocker, and 29 of 30 feature tickets carry a T#
partner — but three findings there are the tracker-side explanation for three findings here:

| Project finding | Code finding | The link |
|---|---|---|
| **P1** — #244 (README) is the only feature ticket with no T# partner | **C1**, **C3** | The one ticket that bypassed the T# gate is the one that shipped the false credential documentation. |
| **P2** — no ticket ever owned *resolving* `secret_key_id`; plan §1 was satisfiable by declaration alone | **C1** | The key is declared in every layer because that is all any ticket asked for. |
| **P3** — both CloudFront URL legs use the settings.php seam; the entity/form seam has no leg | **C2** | Settings.php never materializes `presigned_expiry`, so the presigned-first branch is invisible to the only legs that exist. |
| **P4** — #234 closed on a title asserting IAM detection | **H1** | The claim stands in the tracker, which is rule 4's source of truth. |
| **P5** — `send_chunked_body` has no plan §1 entry | **H3** | An unplanned key that does nothing, documented as functional. |

The pattern across all five: plan sentences that a declaration could satisfy, closed by tickets written
to the declaration reading. The dispositions in both documents are aligned — the corrective pairs listed
here are the ones scoped in the project review's §Disposition.
