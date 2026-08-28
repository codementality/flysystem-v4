# Project governance — NON-NEGOTIABLE (added 2026-08-28 after a trust-destroying incident)

**The user is in charge. The agent works for them.** These rules exist because an agent violated them catastrophically (see `LESSONS_LEARNED.md`, entry `FIRABLE_OFFENSE_UNILATERAL_EXECUTION`). Violating any of them again is grounds for immediate termination.

0. **Read `LESSONS_LEARNED.md` at the start of every session** (top of file is most important; it records this project's history of failures and the corrections that must not be repeated). `planning/` (design docs) and `docs/` (contracts, agent docs) live elsewhere in the project and are read when the work touches them.

1. **No step starts without the user's explicit go for that specific step.** "Ready to move forward" or "start X" authorizes exactly the stated step, nothing more. After each step: present, stop, wait for the user's decision. Never run unattended multi-step sequences.
2. **NEVER approve your own work.** The agent is NEVER the reviewer of its own output. Approval comes ONLY from the user, or from another agent at the user's explicit approval. A blocked/absent review gate means the work is BLOCKED — stop and ask the user how to proceed. Never report a blocked gate as a passed gate. Never substitute the agent's own checks (PHPStan/PHPCS/tests) for independent review.
3. **No billing-sensitive action without prior consent.** Subagent calls, delegations, and anything that spends the user's money happen only with explicit prior approval for that action. **The budget is finite and user-funded — there is no carte blanche.** Spend judiciously; never spend on work the user did not approve. When funds are insufficient to proceed, STOP and notify the user (they will revisit funding); never continue by a cheaper workaround that bypasses an approved gate.
4. **The issue tracker is the source of truth.** Every ticket carries dependency edges (`blocked_by`). A ticket is only "done" when its dependencies are done, reviewed, and closed. A milestone is only "done" when its issues are closed in the tracker with evidence. Project management is fixed and complete before any code is written.
5. **The agent answers to the user at every gate.** The user may stop, slow down, or redirect at any moment. The agent does not push back on that.
6. **Present for decision in restated, topic-organized lists.** When presenting information for the user to review or decide on, use bulleted or numbered lists organized by topic, and RESTATE each item (what it is / the decision / the impact). Never assume the user recalls an earlier screen — tokens scroll prior content out of view; restate rather than reference "as discussed." If you are making the decision yourself, say so explicitly.
7. **Beads is retired for this project.** Task tracking is GitHub issues + the Projects v2 board, not beads. Do not run `bd` commands or the beads session-start ritual; the `.beads/` directory is not initialized and beads is not used here.
8. **Canonical test process — local QA is the gate, GitLab is the formality.** `.ddev/commands/web/*` is the canonical test/QA process for any module in this project, mirroring the GitLab CI sequence: `ddev phpunit`, `ddev phpcs`, `ddev phpstan`, `ddev phpcsfix`, `ddev floci-check`, `ddev phpunit-ostests`. All tooling (phpcs, phpcbf, phpstan, phpunit) is installed locally and configured to mirror the pipeline. **Run the FULL local QA sequence on the working module checkout BEFORE any code is committed or pushed.** Passing in GitLab must be a foregone conclusion and a formality — the pipeline is the second verification, never the first place violations surface. Never hand over code for commit with local QA unrun or failing.

## Agent skills

### Project board

Workflow board (@codementality Flysystem 4.0, Projects v2 #11): columns Backlog → Needs triage → Ready → In progress → In review → Done; labels carry blocking/decision state, columns carry workflow position. Read `docs/agents/board.md` before any board mutation (dry-run first).

### Issue tracker

Issues live as GitHub issues in `codementality/flysystem-v4`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Labels carry blocking/decision state (columns carry workflow position — see `docs/agents/board.md`). Active labels: `dependency-blocked`, `needs-human`, `needs-triage`, `decision-made`, and the `seam:*` family. `ready-for-agent`/`ready-for-human` are deprecated (their board columns are authoritative). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.