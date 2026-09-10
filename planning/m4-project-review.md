# M4 (flysystem_aws / aws_s3) — Independent Project Review

Status: Review, 2026-09-08. Scope: GitHub milestone #15 ("M4 flysystem_aws"), all 59 closed issues in
`codementality/flysystem-v4`, their `blockedBy` edges, and the four parked threads, judged against
`planning/plan-m4.md` (§1 boundary, §2.1 done-table, §4 slices, §8 exit criterion), `AGENTS.md` rule 12
(TDD two-ticket dance), and `M4_RETROSPECTIVE.md`. Companion document: `planning/m4-code-review.md`
(the code axis). Findings here are prefixed `P`; findings in the code review are referenced by their
own IDs (C1, C2, H1…).

## Executive summary

**M4's ticket record is complete and internally consistent on every mechanic the board enforces — 59
of 59 closed, zero tickets closed with an open blocker, 29 of 30 feature tickets carrying a T# partner
— but the plan-to-ticket mapping has gaps in both directions, and the single ticket that skipped the
T# gate is the one that shipped documentation the code contradicts.** The board did not fail; the
board is not the instrument that would have caught these. Every gap below is a case where a plan
sentence was satisfiable without the behavior it describes working, and the ticket that "covered" it
was closed on the weaker reading.

| Check | Result |
|---|---|
| Milestone #15 open / closed | **0 open / 59 closed** — matches `plan-m4.md` §2's claim |
| Tickets closed with an open `blocked_by` | **0 of 59** — the #61 failure class did not recur |
| Feature tickets with a T# partner (rule 12) | **29 of 30** — only #244 lacks one |
| Parked threads present with correct milestones | **4 of 4** (#243 → M9; #245/#246, #216, #105 → M5) |
| Plan §1 scope items with an owning ticket | **All** — but two are owned in name only (P2, P3) |
| Shipped config keys with a plan §1 entry | **6 of 9** (P4) |

## Findings — by severity

- **HIGH — P1.** #244 (README) is the only M4 feature ticket with no T# partner and no `blocked_by`
  edge — and it is the ticket that shipped the credential documentation the code contradicts.
- **HIGH — P2.** No ticket ever owned making `credentials.secret_key_id` functional; plan §1's
  "full preserved config-key set" was satisfiable by declaration alone.
- **HIGH — P3.** CloudFront's proving legs cover only the settings.php seam; the config-entity /
  admin-form seam has neither an owning ticket nor a leg.
- **HIGH — P4.** #234 was closed on a title asserting IAM-conflict detection the delivered code does
  not implement.
- **MEDIUM — P5.** Three shipped config keys have no entry in plan §1's config-key contract — scope
  added during execution with no plan amendment.
- **MEDIUM — P6.** Plan §1 and a Core docblock name the aws_s3 visibility key `visibility`; the
  shipped driver and its config schema declare only `default_visibility`.
- **LOW — P7.** Four M4 tickets carry stale `M2:`/`M3:` title prefixes, making milestone-scoped board
  reads ambiguous.

---

## Findings detail

### P1. #244 is the only M4 feature ticket with no T# partner and no `blocked_by` edge — and it shipped the documentation the code contradicts — HIGH *(verified)*

**What:** `AGENTS.md` rule 12 states "EVERY feature ticket gets a T# red-test ticket… There is NO
'coverage-only' or 'go straight to Done' exception." Every M4 feature ticket has one — except #244
("M4: README settings.php reference for the aws_s3 driver"). It also carries zero dependency edges, so
nothing gated it at all. It is the last commit in the milestone (`3f3d8d9`).

**Evidence:** The zero-edge audit across all 59 M4 issues returns nineteen tickets, eighteen of which
are T# tickets (correctly unblocked) and one of which is not:

```
$ # for each M4 issue: report those with blockedBy.totalCount == 0
#171 T172: … #173 T174: … #175 T176: … #177 T178: … #179 T180: …
#181 T182: … #183 T184: … #185 T186: … #187 T188: … #189 TH4A: …
#191 TH4B: … #193 TH4C: … #223 T222: … #231 T230: … #239 T237: …
#240 T236: … #241 T84:  … #242 T238: …
#244 M4: README settings.php reference for the aws_s3 driver (public, private, presigned, CloudFront)
```

Pairing the 59 issues yields 29 T#/feature pairs (58 tickets) plus #244 — arithmetically confirming
#244 is the sole unpaired one.

**Impact:** This is not a bookkeeping complaint. The README that #244 shipped documents
`credentials.secret_key_id` as the settings.php credential shape (`README.md:62`, `README.md:80`,
`README.md:140`) and states the secret is "never exported" (`README.md:139`). Both claims are false
against the shipped code — see code-review **C1** and **C3**. A T# partner for #244 would have had to
assert that the documented settings.php shape produces a working adapter, and that assertion fails on
current code. The one ticket that bypassed the gate is the one whose gate would have caught two
CRITICAL defects. Rule 12's "no exception, not even for tickets whose behavior seems already pinned"
was written for precisely this.

**Fix:**
- Record on #244 that it closed without a T# partner, and why that matters here (the documented
  credential path does not work).
- The corrective ticket pair for C1 must include a leg that asserts the **README's exact settings.php
  snippet** builds a working adapter — i.e. documentation is verified by executing what it tells the
  operator to do, not by review.
- Going forward, treat a documentation ticket as testable: its T# asserts the documented configuration
  works. Do not carve out a docs exception to rule 12; that is the exception that produced this.

### P2. No ticket ever owned making `credentials.secret_key_id` functional — plan §1 was satisfiable by declaration alone — HIGH *(verified)*

**What:** `plan-m4.md` §1 specifies "the full preserved config-key set (`bucket`, `region`, `prefix`,
`visibility`, `presigned_expiry`, `cloudfront.domain`, `credentials.key/secret/secret_key_id` with
`secret` markers, `use_acl`)". Every ticket that touched credentials — #102/#103 (driver contract),
#213/#214 (settings.php config), #220/#221 (form save) — satisfies that sentence by *declaring* the
keys: they appear in `getConfigKeys()`, in the config schema, in the form, and they round-trip through
save. None of them, and no other M4 ticket, owns *resolving* `secret_key_id` into a credential.

**Evidence:** Ticket titles across the milestone name discovery, declaration, form rendering, save
shape, and precedence — never credential resolution. The `key:key` module is a hard dependency of
`flysystem_aws` with zero consumers in production code (code-review **C1**, verified by grep).
`#103`'s contract scope per plan §4 Slice 1 is "`getConfigKeys()` declares the full preserved
config-key contract with correct `secret` markers" — declaration, explicitly.

**Impact:** The plan's phrasing made a declaration contract indistinguishable from a functional
contract, and the tickets were written to, reviewed against, and closed on the declaration reading.
The result is code-review C1: the documented credential path silently authenticates as nobody. This is
the same failure the retrospective §2.1 names for CloudFront — "the plan listed it; no ticket owned the
runtime wiring and no test pinned it" — recurring on a different key, in the same milestone, after the
lesson was written down.

**Fix:**
- The C1 corrective pair must be scoped as *resolution*, not declaration: its T# asserts that a config
  carrying only `secret_key_id` produces an `S3Client` with resolved credentials.
- Amend the M5/M6 plan documents (`plan-m5.md`, and M6's when written) so every config-key line states
  the consuming code path, not just the key name. A key list is not a contract; "key X is read by Y and
  proven by leg Z" is.
- Audit the M5 `s3` driver's key list against this rule *before* its tickets are written — it inherits
  the same credential surface, and #105/#216 are still open.

### P3. CloudFront's proving legs cover only the settings.php seam; the config-entity / admin-form seam has neither ticket nor leg — HIGH *(verified)*

**What:** CloudFront URL resolution has an owning ticket (#213, per plan §2.1: "incl. presigned +
CloudFront URL wiring in Core `getExternalUrl()`") and two proving legs. Both legs configure the scheme
exclusively through settings.php. The config-entity path — a scheme created through the admin form, which
is the path the form's own `use_cloudfront` checkbox and `cloudfront.domain` field exist to serve — has
no CloudFront URL leg, and #213's title scopes it to settings.php by name.

**Evidence:** Both CloudFront URL legs build the definition via `setFlysystemSettings()`:

```
modules/flysystem_aws/tests/src/Kernel/FlociIntegrationTest.php:178
  testCloudFrontDomainResolvesUrlThroughCloudFrontDomain()  → setFlysystemSettings([...])
modules/flysystem_aws/tests/src/Kernel/AwsS3SettingsPhpConfigTest.php:227
  testCloudFrontDomainResolvesUrlThroughCloudFrontDomain()  → setFlysystemSettings([...])
```

The only entity-path CloudFront coverage is form *rendering* — `AwsS3ConfigFormRenderTest.php:254`
asserts the `config[use_cloudfront]` toggle exists — and the save-shape round-trip. No leg asserts a
form-saved CloudFront scheme produces a CloudFront URL.

**Impact:** This is the exact gap code-review **C2** occupies, and it explains why C2 survived a
milestone with 59 closed tickets. On the settings.php path there is no form, so nothing injects
`presigned_expiry`, so CloudFront resolves and the legs pass. On the entity path the form submits its
`presigned_expiry` default of 3600, `getExternalUrl()` takes the presigned branch first, and CloudFront
is never reached — untested in both directions. The retrospective's own rule ("every plan scope item
must name its owning ticket AND its proving leg") was satisfied for CloudFront-via-settings.php and
never applied to CloudFront-via-entity, because the plan treats CloudFront as one scope item rather
than two seams.

**Fix:**
- The C2 corrective pair's T# covers the entity seam specifically: save a public scheme through the
  form with `use_cloudfront` + a domain, assert `getExternalUrl()` returns the CloudFront URL. It fails
  on current code.
- Adopt a standing rule for the remaining submodule milestones: any config key that both settings.php
  and the admin form can set requires a leg per seam. The two paths diverge — the form materializes
  defaults settings.php does not — so one leg proves half the feature.

### P4. #234 was closed on a title asserting IAM-conflict detection the delivered code does not implement — HIGH *(verified)*

**What:** #234 is titled "Core: adapter config conflicts with bucket IAM — UI warning + logged
conflict", with T# partner #235 "IAM-conflict detection + UI/log reporting". Both are closed. The
delivered code detects no IAM state: it logs every failed operation generically, and adds a
requirements entry comparing two Drupal config values. See code-review **H1** (verified: zero
`GetBucketPolicy` / `GetBucketAcl` / `ObjectOwnership` calls anywhere).

**Evidence:** #234's edges are correctly wired and closed (`blocked_by` #224 CLOSED, #235 CLOSED), so
the board mechanics are clean — the defect is entirely in what the ticket claims versus what it
delivered. `plan-m4.md` §2.1 records the substitution honestly in parentheses ("LoggingFilesystem
reactive catch + base-over-private hook check"), but the ticket title — the artifact a future reader
greps — was never corrected.

**Impact:** The issue tracker is rule 4's source of truth. A closed ticket titled "conflicts with
bucket IAM" is a standing false claim that the capability exists: it will be cited in M9 release notes,
in the drupal.org issue queue, and by anyone auditing what v4 does that v3 did not. `plan-m4.md` is now
frozen, so the ticket record is the only place this can be corrected.

**Fix:** Post a correcting comment on #234 and #235 (never edit or remove prior notes, per rule 10)
restating what shipped and what did not, and either file the real detection as an M5+ pair citing #234
or record the decision to descope it. Per rule 11 this must live on the ticket, not only in this
document.

### P5. Three shipped config keys have no entry in plan §1's config-key contract — MEDIUM *(verified)*

**What:** The shipped driver declares nine config keys beyond the definition-level fields. Plan §1
names six of them. `send_chunked_body`, `use_provider_key_management`, and `use_cloudfront` were added
during execution with no plan amendment recorded.

**Evidence:** Plan §1's list: `bucket`, `region`, `prefix`, `visibility`, `presigned_expiry`,
`cloudfront.domain`, `credentials.key/secret/secret_key_id`, `use_acl` — plus `endpoint` /
`path_style_endpoint` covered separately as the #3618527 override. Shipped in
`AwsS3V3AdapterDriver::getConfigKeys()` and absent from that list: `send_chunked_body`,
`use_provider_key_management`, `use_cloudfront`. Plan §9's "scope folded in during execution" record
lists the CloudFront URL branch but names none of these three keys.

**Impact:** `send_chunked_body` is inert in both directions (code-review **H3**) — an unplanned key
that does nothing, documented in the README as functional. `use_cloudfront` is the flag whose
interaction with `presigned_expiry` produces C2. `use_provider_key_management` gates the credential
surface whose primary path does not work (C1). All three unplanned keys are implicated in a
CRITICAL or HIGH code finding, which is the pattern: keys added mid-execution got a form field and a
schema entry but never a scope line stating what consumes them.

**Fix:** For each of the three, record on the owning ticket what consumes the key and which leg proves
it — or, for `send_chunked_body`, that nothing does (H3's corrective pair). Add the "every new config
key needs a named consumer and a proving leg" rule to `plan-m5.md` before M5's tickets are written.

### P6. Plan §1 and a Core docblock name the aws_s3 visibility key `visibility`; the driver and its schema declare only `default_visibility` — MEDIUM *(verified)*

**What:** Three sources disagree. Plan §1 lists `visibility` in the aws_s3 key set.
`AdapterDefinition::getVisibility()`'s docblock states "the s3 driver uses `default_visibility` while
aws_s3 uses `visibility`" — the reverse of what shipped. The driver declares only
`default_visibility`, and so does `flysystem_aws.schema.yml`.

**Evidence:** `src/Flysystem/AdapterDefinition.php:80-87`:

```php
 * where the s3 driver uses "default_visibility" while aws_s3 uses
 * "visibility". Falls back to 'public' when neither is set.
return (string) ($this->config['visibility'] ?? $this->config['default_visibility'] ?? 'public');
```

The runtime fallback reads either key, so settings.php works with both names.

**Impact:** No functional defect on the settings.php path — the fallback absorbs it. The exposure is
the config-entity path in M8: `flysystem_aws.schema.yml` declares no `visibility` key, so a v3→v4
migration that carries a v3 entity's `visibility` into a v4 config entity fails config schema
validation, while the same value in settings.php works. That asymmetry will surface as a migration bug
long after the naming decision is forgotten.

**Fix:** Settle the canonical name against `config-and-upgrade.md` §2's preserved shape, correct the
`AdapterDefinition` docblock either way, and — if `visibility` is a shape a real v3 site can have — add
it to the submodule's config schema as an accepted alias. Record the decision where M8's migration
tickets will find it.

### P7. Four M4 tickets carry stale `M2:` / `M3:` title prefixes — LOW *(verified)*

**What:** #84 ("M3: Floci ACL-disabled bucket scenario"), #182 ("M2: Core — private download…"),
#184 ("M3: Core — presigned_expiry…") and #232/#230 (bare "Core:" with no milestone prefix) all sit in
milestone #15 with titles naming a different milestone or none.

**Evidence:** The milestone #15 issue listing shows the prefixes; all four are `CLOSED` in milestone
#15.

**Impact:** Cosmetic, but it degrades exactly the workflow the retrospective §3 adopted —
"milestone-scoped board work", where a reader scans titles to see what belongs to the current
milestone. A `M3:` prefix on an M4 ticket makes that scan wrong. It also makes the M3-review-derived
corrections harder to distinguish from original M3 work.

**Fix:** Low priority; if titles are renamed, do it as part of M5 planning's board pass and note the
rename in a comment. Not worth a dedicated ticket.

## What this review got right

Bounding the findings — the board mechanics held, and two failure classes the retrospective flagged did
**not** recur:

- **Zero tickets closed with an open blocker, across all 59.** The retrospective §2.2 records #61
  ("green confused with complete") as a milestone failure; the full-milestone audit shows it did not
  happen again. This is the check most likely to fail under delivery pressure, and it held.
- **29 of 30 feature tickets carry a T# partner.** Rule 12's two-ticket dance was applied consistently,
  including to the Core corrections (#171–#194) where every one of the ten fixes has its own T#. The
  single exception (P1) is a documentation ticket, which is the most defensible place to slip — and,
  per P1, still cost two CRITICAL findings.
- **The milestone's own numbers are accurate.** `plan-m4.md` §2 claims "0 open, 59 closed in milestone
  #15"; the API confirms exactly that. After the retrospective §2.5 entry on "unverified numbers stated
  as fact", the one number this document asserts checks out.
- **All four parked threads exist, in the right milestones, with the content claimed.** #243 (ACL
  enforcement E2E) in M9; #245/#246 (asyncaws ACL scenario) and #216, #105 (M5 spec amendments) in M5.
  Nothing was dropped on close-out — the retrospective §4's "owned, not dropped" claim is true.
- **The dependency graph in plan §3 matches the real edges.** Spot-checked #102, #61, #84, #213, #232,
  #234: every documented `blocked_by` relationship is present in the tracker and closed. The graph was
  maintained, not narrated.

## Verification

```bash
# Milestone counts
gh api repos/codementality/flysystem-v4/milestones --paginate \
  -q '.[] | "\(.number)|\(.title)|open=\(.open_issues)|closed=\(.closed_issues)"'
# → 15|M4 flysystem_aws|open=0|closed=59

# The 59 issues, sorted
gh issue list -R codementality/flysystem-v4 --milestone "M4 flysystem_aws" \
  --state all --limit 100 --json number,title,state \
  -q '.[] | "\(.number)|\(.state)|\(.title)"' | sort -t'|' -k1 -n
# → 59 rows, all CLOSED

# Closed-with-open-blocker audit (all 59, via GraphQL blockedBy)
# for each: report blockedBy nodes whose state != CLOSED
# → no output: every blocker of every M4 ticket is closed

# Zero-edge audit (all 59, blockedBy.totalCount == 0)
# → 19 tickets: 18 T# tickets + #244 (the only unpaired feature ticket)

# Parked threads
gh issue list -R codementality/flysystem-v4 --state all --limit 300 \
  --json number,title,state,milestone \
  -q '.[] | select(.number==243 or .number==245 or .number==246 or .number==105 or .number==216)
      | "#\(.number)|\(.state)|\(.milestone.title)|\(.title)"'
# → #243 OPEN M9 Release; #245/#246/#216/#105 OPEN M5 flysystem_asyncaws

# P3 — CloudFront legs use the settings.php seam only
grep -rn "use_cloudfront" --include="*.php" modules/flysystem_aws/tests/
# → both URL legs call setFlysystemSettings(); entity-path coverage is form-render + save-shape only
```

Findings P2, P4, P5 and P6 are cross-verified in `planning/m4-code-review.md` (C1, H1, H3, and the
`AdapterDefinition` docblock read respectively).

## Disposition

Answering the two questions as asked:

**1(a) — Do the tickets worked cover all of the plan-m4 planning?** Formally yes: every plan §1 and §4
scope item has an owning ticket, and plan §2.1's done-table is accurate. Substantively no in two
places: `credentials.secret_key_id` (**P2**) and CloudFront on the entity seam (**P3**) are owned in
name by tickets whose scope, as written and as tested, does not reach the behavior the plan describes.
Three shipped keys have no plan entry at all (**P5**).

**1(b) — Are there identifiable gaps in the work completed?** Yes, five, all cross-referenced to the
code review: the non-functional credential path (P2 / C1), the entity-path public-URL resolution
(P3 / C2), absent IAM detection under a ticket claiming it (P4 / H1), an inert config key (P5 / H3),
and a naming disagreement that will surface as an M8 migration bug (P6).

**Actions, by priority.** All ticket work is M5+; `plan-m4.md` is frozen.

1. **P4** — correcting comments on #234/#235 restating what shipped. Rule 11: the record, not chat.
   Do this first; it is the only finding that leaves a false claim standing in the source of truth.
2. **P1** — record on #244 that it closed without a T# partner, and fold "the README's own snippet must
   execute" into the C1 corrective pair's T#.
3. **P2, P3** — scope the C1 and C2 corrective pairs per the `**Fix:**` blocks above: resolution not
   declaration, and one leg per configuration seam.
4. **P5** — name the consumer and proving leg for `send_chunked_body`,
   `use_provider_key_management`, and `use_cloudfront` on their owning tickets; H3's pair covers the
   first.
5. **P6** — settle the `visibility` / `default_visibility` name against `config-and-upgrade.md` §2 and
   record it where M8's tickets will find it.
6. **P7** — title prefixes, opportunistically during M5 board planning. No ticket.

**Two process amendments for `plan-m5.md`, before M5's tickets are written** — both are generalizations
of findings above, and M5's #105/#216 are still open, so there is time to apply them:

- Every config-key line states its consuming code path and its proving leg, not just the key name
  (from P2, P5).
- Any config key settable from both settings.php and the admin form requires a leg per seam; the form
  materializes defaults settings.php does not, so one leg proves half the feature (from P3).
