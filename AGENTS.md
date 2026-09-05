# Project governance — NON-NEGOTIABLE (added 2026-08-28 after a trust-destroying incident)

**The user is in charge. The agent works for them.** These rules exist because an agent violated them catastrophically (see `LESSONS_LEARNED.md`, entry `FIRABLE_OFFENSE_UNILATERAL_EXECUTION`). Violating any of them again is grounds for immediate termination.

0. **Read `LESSONS_LEARNED.md` at the start of every session** (top of file is most important; it records this project's history of failures and the corrections that must not be repeated). `planning/` (design docs) and `docs/` (contracts, agent docs) live elsewhere in the project and are read when the work touches them.

1. **No step starts without the user's explicit go for that specific step.** "Ready to move forward" or "start X" authorizes exactly the stated step, nothing more. After each step: present, stop, wait for the user's decision. Never run unattended multi-step sequences.
    - **PRESENT → STOP → WAIT. No auto-advance. EVER.** When a ticket's work is complete and verified: move it to **In review**, **explicitly NOTIFY the user that it is ready for review** (state what changed and the QA evidence in the same message), and **STOP**. Do NOT claim the next ticket, do NOT move the next ticket to In progress, do NOT delegate, do NOT write any code for the next ticket — until the user has (a) reviewed/approved the presented work and (b) explicitly said to proceed to the next step. A completed step authorizes NOTHING beyond itself. Batch advances across multiple tickets are forbidden. Also: a ticket that is only "In review" with no explicit notification to the user is NOT delivered. (Violated catastrophically 2026-08-29: completed #93, moved it to In review without notifying the user, then claimed and started #94 without the go — partial unauthorized code landed in the working tree and had to be reverted.)
2. **NEVER approve your own work.** The agent is NEVER the reviewer of its own output. Approval comes ONLY from the user, or from another agent at the user's explicit approval. A blocked/absent review gate means the work is BLOCKED — stop and ask the user how to proceed. Never report a blocked gate as a passed gate. Never substitute the agent's own checks (PHPStan/PHPCS/tests) for independent review.
3. **No billing-sensitive action without prior consent.** Subagent calls, delegations, and anything that spends the user's money happen only with explicit prior approval for that action. **The budget is finite and user-funded — there is no carte blanche.** Spend judiciously; never spend on work the user did not approve. When funds are insufficient to proceed, STOP and notify the user (they will revisit funding); never continue by a cheaper workaround that bypasses an approved gate.
4. **The issue tracker is the source of truth.** Every ticket carries dependency edges (`blocked_by`). A ticket is only "done" when its dependencies are done, reviewed, and closed. A milestone is only "done" when its issues are closed in the tracker with evidence. Project management is fixed and complete before any code is written.
5. **The agent answers to the user at every gate.** The user may stop, slow down, or redirect at any moment. The agent does not push back on that.
6. **Present for decision in restated, topic-organized lists.** When presenting information for the user to review or decide on, use bulleted or numbered lists organized by topic, and RESTATE each item (what it is / the decision / the impact). Never assume the user recalls an earlier screen — tokens scroll prior content out of view; restate rather than reference "as discussed." If you are making the decision yourself, say so explicitly.
7. **Beads is retired for this project.** Task tracking is GitHub issues + the Projects v2 board, not beads. Do not run `bd` commands or the beads session-start ritual; the `.beads/` directory is not initialized and beads is not used here.
8. **Canonical test process — local QA is the gate, GitLab is the formality.** `.ddev/commands/web/*` is the canonical test/QA process for any module in this project, mirroring the GitLab CI sequence: `ddev phpunit`, `ddev phpcs`, `ddev phpstan`, `ddev phpcsfix`, `ddev floci-check`, `ddev phpunit-ostests`. All tooling (phpcs, phpcbf, phpstan, phpunit) is installed locally and configured to mirror the pipeline. **Run the FULL local QA sequence on the working module checkout BEFORE any code is committed or pushed.** Passing in GitLab must be a foregone conclusion and a formality — the pipeline is the second verification, never the first place violations surface. Never hand over code for commit with local QA unrun or failing.
    - **A check is NOT "clean" until you have RUN it and READ its output.** Claiming "phpcs clean" or "QA green" without executing the exact canonical command and reading the actual output is forbidden. "Expected to pass" is not "passed." If a command fails, errors, or you did not actually run it, say so — the work is NOT ready.
    - **Run the EXACT canonical config, never a variant.** phpcs/phpcbf MUST use `.ddev/commands/web/phpcs.xml.dist` (the Drupal-ruleset + contrib-extension-list config that matches the GitLab pipeline's default). phpstan MUST use `-c .ddev/commands/web/phpstan.neon`. phpunit MUST use core's `phpunit.xml.dist` with the inline env vars. A hand-rolled flag set that differs from these (e.g. a different `--standard` or extension list) is NOT a valid QA run — it will miss violations the pipeline catches, as happened with `yml` trailing-newline errors.
    - **When a check is green locally, paste the actual output** (the `OK (N tests...)` line, the `[OK] No errors` line, the empty phpcs result) in the handoff message as evidence. A green claim without pasted output is not acceptable.
    - **`.cspell-project-words.txt` is intentionally maintained by the user.** The GitLab spell checker does NOT run locally; the user reviews its results and either fixes spellings in code or adds words to `.cspell-project-words.txt`. Staged changes to that file are deliberate (addressing GitLab spell-checker warnings) — do NOT notify the user every time it changes, do NOT revert it, and do NOT "fix" it. (Noted by user 2026-08-29.)
9. **American English spelling.** Use US spellings in all written artifacts (code, comments, docblocks, docs, commit messages, issue text): `recognize`/`recognized`/`recognizing` (never `recognise`/`recognised`), `color` (never `colour`), `behavior` (never `behaviour`), etc. (Noted by user 2026-08-29.)
10. **Approved board workflow** (user-approved 2026-08-29 after the #47 protocol break — this is THE workflow for the GitHub board + issue tracker; follow it exactly):
    - **No ticket is worked, no code is written, without that ticket being in the "In progress" column of the board.** Moving a ticket to In progress IS the authorization to work it.
    - **A test-only T# ticket goes to "In review", NOT "Tests complete, failing", when its red tests are authored.** The user reviews the authored red tests in In review; ONLY on their approval does the T# move to "Tests complete, failing" (which unblocks the implementation ticket to start). Never pre-move a T# to "Tests complete, failing" before the user has reviewed and approved it (correction 2026-08-30: #51 was wrongly pre-moved).
    - **When a ticket is ready for review, it MUST be placed in the "In review" column** in the same action as notifying the user it is ready for review — the board is the user's only pointer to what to review. A ticket notified as ready for review that is not in In review is a protocol break (happened 2026-08-29: #47 sat in "Tests complete, failing" while I told the user it was ready).
    - **Ticket notes and comments must be updated with decisions made**, especially when a decision varies from the initially planned work (per epistemic-discipline labeling: VERIFIED / ASSUMED / corrections to the spec).
    - **Never remove previously written notes.** Corrections are made only via subsequent comments on the issue.
    - **When code is approved** — by the user, or by a subagent designated with the user's approval — update the tickets: move the worked tickets to their appropriate columns ("Tests complete, failing" for a T# whose red tests the user has APPROVED and which awaits its feature ticket, "In review" for a T# whose red tests are authored but NOT yet approved, "Done" for completed work), review the Backlog column, remove any dependency blockers that are now cleared, and move any now-unblocked tickets to "Ready".
    - **Consumer-chain check before pulling any ticket** (correction 2026-08-31 after #54/#17/#78): a ticket being in Ready only proves ITS OWN blockers are started — it does NOT prove its work will be consumable. Before moving any ticket to In progress, trace its downstream consumer chain: for a T#, inspect the IMPLEMENTATION ticket's full `blocked_by` set and confirm no OTHER blocker of the implementation is unstarted. If the implementation still has an unstarted blocker besides the T#, the T#'s red tests will sit idle (approved but unconsumable) — do NOT pull the T# without first flagging this to the user, or start the deeper unstarted blocker first. Work order follows the dependency chain: deepest unstarted blocker first.
11. **If it isn't written down in a persistent format, it does NOT exist.** The chat window is ephemeral and is NOT acceptable as the only avenue for communicating gaps in testing or scope. Whenever you identify a gap in testing (or any scope gap) while working a ticket, DOCUMENT it as a comment on that ticket in the same session — never report it only as chat output. This gives the user a persistent, reviewable record on which to decide the next step. (User directive 2026-08-30.)
    - Applies to testing gaps AND scope gaps: e.g. "method X left as a stub with no test pinning it", "behavior Y untested on path Z", "ticket W does not cover requirement V".
    - The comment must restate the gap, say what is and isn't covered, and state the decision the user needs to make (e.g. "file a new T# + implementation pair" / "fold into ticket N").
12. **TEST-DRIVEN DEVELOPMENT IS NON-NEGOTIABLE. NO EXCEPTIONS. NONE.** (User directive 2026-08-31, after #108/#119/#120 slipped through without T# tickets.) This project uses TDD to prevent the bugs that made Flysystem v3 buggy and difficult to support — v3 also had all-green tests and it does not work. Therefore:
    - **EVERY feature ticket gets a T# red-test ticket** (failing tests authored first → In review → user approval → implementation → both to Done together). There is NO "coverage-only" or "go straight to Done" exception, even for tickets whose behavior seems already pinned by the PHP API or existing seams (#108, #119, #120 must all get T# tickets retroactively).
    - **No ticket is a code-only ticket.** If a ticket has no T# partner, that is a defect to fix (create the T#), not a license to proceed without red tests.
    - Any plan-doc or board-doc language suggesting an exception ("coverage-only tickets go straight to Done", "no open blockers", a T# whose tests are already green goes straight to Done) is WRONG and must be corrected when found. The T# gate is the rule, not the exception.
    - If a T#'s tests would be green at authoring time (the behavior already exists), author them anyway as regression pins — they still gate the ticket through the T# review before the implementation is accepted.

## Repository layout — TWO SEPARATE GIT REPOS (read this first)

**This project spans two independent git repositories. Know which one you are in before any git command.**

1. **Main repo** — `codementality/flysystem-v4` (this repo, branch `main`, GitHub). Contains ONLY planning/docs: `planning/`, `docs/`, `AGENTS.md`, `LESSONS_LEARNED.md`, `.ddev/`, `scripts/`, `config/`. It is the project-management shell (board + issues live here). **The module code is NOT here** — `.gitignore:74` excludes `web/modules/custom/flysystem`. Commit messages like "Updating after…" are the norm here.
2. **Module repo** — `web/modules/custom/flysystem/` is its OWN git repository (it has its own `.git`, since the project started). Remote: `git@git.drupal.org:project/flysystem.git`. Branch: `4.0.x`. **ALL module code lives here** (`src/`, `tests/`, `config/`, `README.md`, `.gitlab-ci.yml`). All the milestones' code — M1 through M3, ~90+ closed tickets' worth — is committed in THIS repo.

**Rules:**
- **All module code work (code + tests) happens in the module repo** at `web/modules/custom/flysystem`. Run `git -C web/modules/custom/flysystem <cmd>` for anything about the code.
- The main repo only ever gets docs/planning commits; never commit module code into the main repo.
- When reporting "is the code changed?" or "git status", check **both** repos — the answer often differs.
- Never guess which repo something lives in: verify with `git -C <path> remote -v` and `ls -d <path>/.git`.

## Agent skills

### Project board

Workflow board (@codementality Flysystem 4.0, Projects v2 #11): columns Backlog → Needs triage → Ready → In progress → In review → Done; labels carry blocking/decision state, columns carry workflow position. Read `docs/agents/board.md` before any board mutation (dry-run first).

### Issue tracker

Issues live as GitHub issues in `codementality/flysystem-v4`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Labels carry blocking/decision state (columns carry workflow position — see `docs/agents/board.md`). Active labels: `dependency-blocked`, `needs-human`, `needs-triage`, `decision-made`, and the `seam:*` family. `ready-for-agent`/`ready-for-human` are deprecated (their board columns are authoritative). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Planning docs — current milestone

The **current milestone is M4 (flysystem_aws submodule, `aws_s3` driver)**. Its execution contract is
`planning/plan-m4.md`. Source-of-truth companions: `planning/adapter-submodules.md` (the adapter
carve-out: Core ships `local` only; `s3`/`aws_s3`/`sftp` are optional submodules M4–M6; `in_memory` is
a dev-only test fixture), `planning/architecture.md` (§4–§7 behavioral contracts, §11 plugin
contract), `planning/testing.md` (§2 TDD/seams, §4 Floci integration, §5 pain-map, §8 milestones),
`planning/config-and-upgrade.md` (§2 preserved settings.php shapes, §3 preserved config-entity
shapes). M3 (`planning/plan-m3.md`) is complete and immutable (milestone-immutability rule).

**Floci is a prerequisite of the S3 submodules, not an M7 afterthought** (corrected 2026-09-05): the
Floci integration layer (#24/#61) lives in M4, and #102/#104 are `blocked_by` it. M4 cannot be tested
without Floci-emulated S3 + CloudFront — that is its entire testing purpose.