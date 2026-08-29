# Flysystem v4 — M1 Independent Code Review

Status: **Review**, 2026-08-29. Reviewer: independent agent review at the user's request (AGENTS.md §2 — the implementing agent is never the reviewer of its own work).

Scope: `web/modules/custom/flysystem` at branch `4.0.x`, commit `f56a38f`. 2,881 lines of PHP plus YAML. Reviewed against `planning/plan-m1.md`, `planning/architecture.md` (§3, §5, §11, §12), `planning/testing.md` (§2, §3, §6), `planning/config-and-upgrade.md` (§2–§3), and `planning/feature-evaluation-log.md` (Item 5).

Review emphasis, per the requester: **security, performance, and code smells** (duplicated code, poorly structured control flow), alongside M1 spec compliance.

## Verdict

**NEEDS WORK — M1 should not be signed off.**

One deliverable of Milestone 1 (ticket #6, scheme registration) is not implemented, and its ticket is closed. The test written to cover it cannot fail for the reason the ticket exists. Four security findings and three performance findings follow.

M1 ticket states at review time: #5 closed, #6 closed, #7 closed, #74 closed, #75 closed, #77 closed, #79 closed; #73 and #76 open.

---

## 1. Blocker — ticket #6 is not implemented

### 1.1 No scheme is ever registered with PHP's stream layer

**What the spec requires.** `architecture.md` §3.3 and `plan-m1.md` Slice 5: schemes are tagged DI services (`stream_wrapper` tag + `scheme` attribute) collected by core's `StreamWrapperClassesPass` for settings.php schemes at container build; config-entity schemes register at runtime through the decorated manager, "which keeps core's manager in sync."

**What exists.** None of it. The module contains no tagged `stream_wrapper` services, no `ServiceProvider`, no compiler pass, and no call to `stream_wrapper_register()` anywhere.

- `FlysystemStreamWrapperManager::registerWrapper()` — `src/StreamWrapper/FlysystemStreamWrapperManager.php:118` — delegates straight to `$this->inner`.
- `FlysystemStreamWrapperManager::register()` — `:158` — delegates straight to `$this->inner`.
- Core's `StreamWrapperManager::register()` (`web/core/lib/Drupal/Core/StreamWrapper/StreamWrapperManager.php:148`) iterates `$this->wrapperClasses`, which is populated **only** from compile-time tagged services. No flysystem scheme is in it, so none reaches `stream_wrapper_register()` at `:180`/`:183`.

**Impact.** PHP's stream layer never learns the scheme. Every native call fails: `fopen('media://x')`, `file_exists()`, `is_dir()`, `move_uploaded_file()`. This is exactly the defect class `architecture.md` §3.1 exists to prevent (Drupal issue #3616485 — "the wrapper must self-bootstrap because PHP instantiates wrappers directly for native calls"). The wrapper self-bootstraps correctly; it is simply never reachable, because PHP was never told the scheme exists.

**Secondary impact.** `getWrappers()`, `getNames()`, and `getDescriptions()` (`:69`, `:76`, `:83`) delegate wholesale to the inner manager, so flysystem-owned schemes are invisible to every core consumer that enumerates wrappers. `testing.md` §2 seam 2 names `getWrappers` explicitly as part of the contract, and `architecture.md` §4.2 makes GD's staging decision depend on `getWrappers(LOCAL)` — that will silently misbehave in M3.

**Fix.** Implement the registration path (both sources), and have `getWrappers()`/`getNames()`/`getDescriptions()` merge owned schemes over the inner result.

### 1.2 The #6 test passes without the feature

`tests/src/Kernel/SchemeRegistrationTest.php` asserts only `isValidScheme()`. The decorator implements that (`FlysystemStreamWrapperManager.php:58`) as `class_exists($this->getClass($scheme))` — which is TRUE for any owned scheme purely because `FlysystemStreamWrapper::class` exists. **The assertion cannot fail for the reason the ticket exists.**

The test's own docblock concedes the gap (`SchemeRegistrationTest.php:22-26`):

> `getNames()`/`getWrappers()` are NOT asserted: core's manager instantiates every registered wrapper there, and a core wrapper throws on an empty URI in the kernel-test environment … **#6 should verify those two methods separately once schemes are registered.**

That deferral was never filed as a ticket, and #6 was closed regardless. A replacement test must observe registration directly — `stream_get_wrappers()` containing the scheme, or a native `file_put_contents()`/`file_exists()` round trip through the scheme.

---

## 2. Security

### 2.1 `testConnection()` reports success without contacting anything — HIGH

`src/Flysystem/FilesystemFactory.php:131-147` returns `['status' => 'success']` when `buildAdapter()` merely constructs an object. The S3 (AsyncAws and AWS SDK v3) and SFTP adapter constructors perform **zero I/O**. A scheme with a wrong bucket, invalid credentials, or an unreachable endpoint therefore reports success to the operator.

This is both a correctness defect and a trust defect: the admin UI will affirm that a misconfigured private bucket is healthy. `architecture.md` §11 lists the connection test as one of the four things the plugin declaration feeds; it must actually probe. Use a bounded real operation — `fileExists()` on a sentinel key, or `listContents` limited to one result — and map failures through the exception strategy.

### 2.2 Raw exception messages become exportable configuration — HIGH

`FilesystemFactory.php:136-141` places `$e->getMessage()` into the returned `message`, which is destined for the entity's `connection_status_message`. That field is in `config_export` (`src/Entity/FlysystemFilesystem.php:53-62`), so it is written into `flysystem.filesystem.<scheme>.yml` and, in the normal Drupal workflow, committed to version control.

Adapter and SDK exception messages routinely embed endpoint URLs, bucket names, request IDs, SFTP usernames and remote paths, and in some AWS SDK error paths a presigned query string. Persisting them into exportable config is an information-disclosure path.

This also bypasses `architecture.md` §5 boundary 3 ("one clean line from `operation()`/`location()`/`reason()`") and uses the exact method `feature-evaluation-log.md` Item 5 warns against:

> Messages are mostly actionable sentences; caveat: `UnableToMoveFile`/`UnableToListContents` **embed the previous low-level exception's message** (use accessors, not `getMessage()`).

**Fix.** Persist a sanitized status code plus a short, non-reflective summary; log full detail via watchdog.

### 2.3 Secrets are storable in plaintext in exported config — HIGH (latent)

`config/schema/flysystem.schema.yml` declares plaintext secret keys as ordinary strings, beside their Key-module counterparts:

- `:53` `credentials.secret` (s3), `:93` `credentials.secret` (aws_s3)
- `:113` `password`, `:121` `private_key`, `:126` `passphrase` (sftp)

Config entities export to YAML and are routinely committed. Nothing validates "exactly one of `password` / `password_key_id`", nothing warns the operator, and no form marks these `#type => 'password'`.

Not yet exploitable — the driver config sub-forms are ticket #78 and unwritten — which makes this the right moment to fix the contract, before those forms land. Options, in order of preference:

1. Drop the plaintext keys from the **config-entity** schema entirely; require `*_key_id` there. `settings.php` is not exported and can keep plaintext (that is the preserved 3.0 contract in `config-and-upgrade.md` §2).
2. If plaintext must remain, add a validation constraint enforcing the XOR, render with `#type => 'password'`, and state the exposure in the field description.

**Pushback (2026-08-29):** Option 1 (drop plaintext from the config-entity schema) conflicts with the preservation contract (`config-and-upgrade.md` §1 — structures are additive-only; §3 lists the plaintext keys beside their `*_key_id` resolution). **Decision (user, 2026-08-29): XOR-Validation (option 2)** — add a validation constraint enforcing exactly-one-of `*_key_id`/plaintext, render `#type => 'password'`, and state the exposure in the field description. Plaintext-drop remains documented as the stricter alternative.

### 2.4 `setUri()` throws on the container-free path — MEDIUM

`src/StreamWrapper/FlysystemStreamWrapper.php:104-109` throws `\InvalidArgumentException` on a malformed URI, and `getViaUri()` reaches it through `create()` (`FlysystemStreamWrapperManager.php:110`). `architecture.md` §5 boundary 1 is unambiguous: the wrapper never throws — it returns the primitive contract value and `trigger_error()`s. A caller passing `public:/x` gets an uncaught exception where core returns FALSE.

---

## 3. Performance

### 3.1 An entity load on every stream-manager call — MEDIUM

`FlysystemStreamWrapperManager::isOwnedScheme()` (`:185-188`) calls `FilesystemFactory::schemeExists()` (`FilesystemFactory.php:57-63`), which checks settings (cheap) and then `getStorage()->load($scheme)` — an entity load. `isOwnedScheme()` is called by `getClass()`, `isValidScheme()`, `getViaScheme()`, and `getViaUri()`.

`getViaUri()` runs on essentially every file operation in Drupal, and neither class memoizes anything. **Fix:** resolve the owned-scheme set once per request in the factory (an array built from both sources), invalidated on `flysystem_filesystem` save/delete.

### 3.2 A new wrapper object per resolution call — MEDIUM (latent)

`getViaScheme()` (`:93`) and `getViaUri()` (`:107`) each construct a fresh `FlysystemStreamWrapper` via `create()`. Core caches wrapper instances. Cheap today because the wrapper is a stub — but once it holds a resolved adapter or `Filesystem`, constructing one per call becomes a serious regression. Fix the shape now, while it is free, rather than after M2 fills the wrapper in.

**Pushback (2026-08-29):** Agree with the direction, with a caveat — the fix must match core's actual wrapper-instance handling: verify `StreamWrapperManager`'s caching behavior at implementation time rather than assuming it caches (or does not).

### 3.3 `getConfiguredSchemes()` hydrates every entity — LOW

`FilesystemFactory.php:71-77` calls `loadMultiple()` and then reads only `id()`. An entity query, or `config.factory->listAll('flysystem.filesystem.')`, returns ids without hydrating entities.

---

## 4. Correctness and contract

### 4.1 `getName()` returns a machine scheme, not a UI label

`FlysystemStreamWrapper.php:90-92` returns the parsed scheme, and `''` when no URI is set. `StreamWrapperInterface::getName()` is documented "for use in the UI", and `getNames()` builds admin-facing lists from it; core wrappers return strings like "Public files". The config entity already carries a `label` that should feed this.

**Pushback (2026-08-29):** Agreed this is the eventual contract, but the timing is M2, not M1 — the stub cannot return the entity label until the wrapper's static bootstrap resolves the scheme definition (the M2 wrapper hardening, #8–#16). At M1 the scheme string is the honest self-sufficient value. Tracked as part of the M2 wrapper work, not a standalone M1 ticket.

### 4.2 `dirname()` returns FALSE where a string is implied

`FlysystemStreamWrapper.php:158-160`. Correctly `@todo`-marked for M2 and permitted by `plan-m1.md` §4 ("the wrapper can be a thin stub"), but it is the one stub whose wrong *type* can propagate into path building rather than failing closed. Worth an explicit note on the M2 ticket (#15).

**Pushback (2026-08-29):** No standalone ticket — the review itself permits the M1 stub. The note is added to #15 (M2 local-path contract), where the hardened implementation lives.

---

## 5. Code smells

### 5.1 The scheme-name rule is encoded three times, its message five times

The literal *"The scheme name is not valid: it may contain only lowercase letters, numbers, and hyphens."* appears in:

- `src/Entity/FlysystemFilesystem.php:145` and `:146` (message and messageTemplate)
- `src/Form/FlysystemFilesystemForm.php:85` (`#machine_name['error']`)
- `src/Form/FlysystemFilesystemForm.php:171` (`validateForm()`)
- `config/schema/flysystem.schema.yml` (Regex `message`)

The *pattern* is independently encoded three times: `FlysystemFilesystem::SCHEME_NAME_PATTERN` (`:72`), the schema `Regex.pattern`, and the form's `replace_pattern` (`:83`). Five copies of one sentence and three copies of one rule, all of which must stay in sync by hand.

**Fix.** Put the message on the entity as a const beside the pattern and reference it from the form. Schema YAML cannot reference PHP, so add a comment pointing at the const.

### 5.2 `validateForm()` discards every violation's own message

`FlysystemFilesystemForm.php:168-173` loops all violations and substitutes one hardcoded string regardless of which constraint fired. The docblock explains the motive (the entity's violation messages are plain strings, not translatable), but the remedy is a translatable message per constraint — not a blanket override. As written, the moment a second constraint is added it will report the *wrong error against the right field*.

### 5.3 Smaller items

- **Snake_case property.** `AdapterDefinition.php:31` — `private readonly ?string $public_url_base`. Drupal standard is lowerCamelCase; the other three promoted parameters comply.
- **Config passed twice, authority unstated.** `FilesystemFactory.php:210-211` passes `$definition->getConfig()` both to `createInstance()` (as plugin configuration) and to `buildAdapter()`. Redundant, and ambiguous about which is authoritative.
- **Required key read without validation.** `FilesystemFactory.php:172` — `(string) $source['driver']` with no `isset`. `config-and-upgrade.md` §2 marks `driver` required; a settings.php entry missing it emits an undefined-key warning, yields `''`, and surfaces later as a confusing `PluginNotFoundException`. Validate and throw a clear message.
- **Uncalled surface.** `FlysystemFilesystemConstraintViolationList::hasField()` has no callers. (`AdapterDefinition::getVisibility()`/`isWritable()` are also uncalled, but those have known M2/M3 consumers and are fine.)
  - **Pushback (2026-08-29):** `hasField()` is NOT uncalled — it is exercised by `tests/src/Kernel/FlysystemFilesystemEntityTest.php:143` (`$violations->hasField('id')`). It is the deliberate test surface of the #74 entity-validation API; retained.
- **`flysystem.module`** contains only a file docblock. Harmless; D12 prefers OO hooks anyway.

---

## 6. What is done well

- `declare(strict_types=1)` throughout; full type hints; constructor DI with no `\Drupal::service()` in any class — `plan-m1.md` §4 satisfied.
- The wrapper skeleton (`#79`) genuinely implements the full `StreamWrapperInterface` surface with `@todo`s pointing at the correct M2 tickets. This closes the gap flagged as A1 in `planning/independent-plan-review.md` and is disciplined work.
- Delegation-by-default in the decorator is the right shape: unconfigured schemes are untouched, and `DecoratedStreamWrapperManagerTest::testUnconfiguredSchemesDelegateToCore()` pins it.
- The scheme-name rule is enforced in depth — entity validator, schema Regex, and form element — even though the duplication above should be consolidated.
- `composer.json` correctly pins `php: >=8.4` per `plan-m1.md` §1, resolving the doc contradiction noted in the plan review.
- Test docblocks are unusually candid about what is and is not asserted. That honesty is what made finding 1.2 detectable — the practice is worth keeping.

---

## 7. QA gate — green, and orthogonal to these findings

**This review did not run `ddev phpunit`, `ddev phpcs`, or `ddev phpstan`** — it was conducted read-only, and those commands write to the database and caches. Every finding above is derived from reading the module and Drupal core, not from a test run.

The QA gate itself is **not** open: the user confirmed (2026-08-29) that the `AGENTS.md` §8 sequence is run locally after every ticket and again on commit/push to GitLab, and that it was run before this review was requested.

That green result and these findings are fully consistent, because **none of the findings above is the kind of defect this toolchain can detect**:

| Finding | Why QA cannot catch it |
|---|---|
| 1.1 no scheme registration | PHPStan/PHPCS analyze code that exists; they cannot flag a `stream_wrapper_register()` call that was never written. No test exercises a native stream op. |
| 1.2 tautological test | PHPUnit reports a passing assertion. It has no notion of whether the assertion could ever have failed. |
| 2.1 connection test reports success without I/O | The code is type-correct and returns a valid array. The defect is semantic. |
| 2.2 exception messages into exported config | A data-flow/disclosure concern spanning PHP and config export; no rule models it. |
| 2.3 plaintext secrets in schema | Valid config schema. The risk is what operators may put in it. |
| 3.1–3.3 performance | Entity loads and per-call object construction are legal, idiomatic code. |
| 5.1–5.2 duplication, discarded violation messages | PHPCS checks formatting and naming, not semantic duplication across PHP and YAML. |

This is the argument for the independent gate in `AGENTS.md` §2: a green pipeline establishes that the code is well-formed and that its tests pass, not that the code does what the design requires. The one finding QA *could* have surfaced — 1.1 — is precisely the one whose test was written so it would not (1.2).

---

## 8. Recommended actions before M2 begins

1. **Reopen #6.** Implement scheme registration for both configuration sources; make `getWrappers()`/`getNames()`/`getDescriptions()` include owned schemes.
2. **Replace the #6 test** with one that observes registration directly (`stream_get_wrappers()`, or a native `file_put_contents()`/`file_exists()` round trip through a configured scheme). File the `getNames()`/`getWrappers()` coverage the current docblock defers.
3. **Fix 2.1 and 2.2** — a real connection probe, and a sanitized `connection_status_message`. Both sit in `FilesystemFactory`, which M2's write path and URL policy build directly on.
4. **Decide 2.3 now** — whether plaintext secrets are permitted in the config-entity schema — before #78 writes the driver config forms against the current shape.
5. **Fix 3.1 and 3.2** while they are cheap, for the same reason: M2 makes the wrapper expensive to construct.
6. **Consolidate 5.1 and 5.2** — one message const, per-constraint messages.
7. **Run the AGENTS.md §8 QA sequence** and attach the output.

Items 1 and 2 are M1 completion work. Items 3–7 are best done before M2 starts, because M2 (#8–#16) builds on exactly these seams.
