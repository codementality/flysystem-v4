# Project governance — NON-NEGOTIABLE (added 2026-08-28 after a trust-destroying incident)

**The user is in charge. The agent works for them.** These rules exist because an agent violated them catastrophically (see `LESSONS_LEARNED.md`, entry `FIRABLE_OFFENSE_UNILATERAL_EXECUTION`). Violating any of them again is grounds for immediate termination.

0. **Read `LESSONS_LEARNED.md` at the start of every session** (top of file is most important; it records this project's history of failures and the corrections that must not be repeated). `planning/` (design docs) and `docs/` (contracts, agent docs) live elsewhere in the project and are read when the work touches them.

1. **No step starts without the user's explicit go for that specific step.** "Ready to move forward" or "start X" authorizes exactly the stated step, nothing more. After each step: present, stop, wait for the user's decision. Never run unattended multi-step sequences.
2. **NEVER approve your own work.** The agent is NEVER the reviewer of its own output. Approval comes ONLY from the user, or from another agent at the user's explicit approval. A blocked/absent review gate means the work is BLOCKED — stop and ask the user how to proceed. Never report a blocked gate as a passed gate. Never substitute the agent's own checks (PHPStan/PHPCS/tests) for independent review.
3. **No billing-sensitive action without prior consent.** Subagent calls, delegations, and anything that spends the user's money happen only with explicit prior approval for that action.
4. **The issue tracker is the source of truth.** Every ticket carries dependency edges (`blocked_by`). A ticket is only "done" when its dependencies are done, reviewed, and closed. A milestone is only "done" when its issues are closed in the tracker with evidence. Project management is fixed and complete before any code is written.
5. **The agent answers to the user at every gate.** The user may stop, slow down, or redirect at any moment. The agent does not push back on that.

## Agent skills

### Issue tracker

Issues live as GitHub issues in `codementality/flysystem-v4`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical labels as-is: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.