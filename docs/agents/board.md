# Board Conventions — @codementality Flysystem 4.0 (Projects v2 #11)

How the project board is structured and how tickets move through it. Read before any
board mutation. The board is the visual workflow; the issue tracker (and its
`blocked_by` dependency edges) is the source of truth for dependencies.

## Columns (left → right)

`Backlog` → `Needs triage` → `Ready` → `In progress` → `In review` → `Tests complete, failing` → `Done`

**IMPORTANT — do NOT set descriptions on Status options.** GitHub's board UI renders a Status option's `description` as a phantom card in that column (a card with the description text, unclickable, not backed by any issue). The meaning of each column lives here in `docs/agents/board.md`, not in the option descriptions. Any option created via the API must have `description: ""`. (Root cause of the 2026-08-28 phantom-card incident.)

| Column | Meaning |
|---|---|
| Backlog | Dependency-blocked (a `blocked_by` ticket has **not started**) OR not yet picked up. Carries the `dependency-blocked` label when a blocker is unstarted. |
| Needs triage | Awaiting a human decision/triage. Tickets here may carry `needs-triage` + `needs-human` labels and, once decided, a `decision-made` label. |
| Ready | Unblocked and startable — every `blocked_by` ticket has **started** (even if not yet closed). |
| In progress | Being worked. |
| In review | Work complete, awaiting independent review/approval. **A test-only T# ticket sits here once its red tests are authored and verified** — the user reviews the failing tests here, BEFORE they move to Tests complete, failing. |
| Tests complete, failing | **Red-test ticket (T#) post-approval state.** The red tests are authored, verified failing, AND **approved by the user** (reviewed in In review). The ticket sits here while its implementation ticket makes those tests green. This is NOT "done": the red state satisfies the blocking edge for starting the implementation ticket, and both tickets move to Done together once the tests pass. |
| Done | Closed — dependencies done, reviewed, and closed. A T# ticket reaches Done when its tests are green (either immediately, or via the Tests complete, failing column then green). |

## The two-ticket test/implementation dance

A feature ticket and its red-test ticket work as a pair:

1. **T#** writes failing tests → **In review** (awaiting the user's review of the authored red tests).
2. **User approves the red tests** → T# moves to **Tests complete, failing** (not Done).
3. **The implementation ticket starts** — the approved red state satisfies its blocking edge for *starting* (it does not need T# to be Done to begin).
4. Implementation makes the tests green.
5. **Both move to Done** — T# because its tests pass, the implementation because its work is complete and reviewed. This unblocks anything depending on either.
6. **There is NO "straight to Done" bypass for a T# (CORRECTED 2026-08-31, user directive — NON-NEGOTIABLE).** If a T#'s tests are already green when its turn arrives (the behavior already exists), they are still authored as regression pins and gated through the **T# review** (In review → user approval → Tests complete, failing → implementation). A T# never goes straight to Done. This revokes the earlier step-6 language that allowed it.

## The dependency rule

- A ticket is **Blocked from starting** when a `blocked_by` ticket has **not started**.
  It sits in **Backlog** with the `dependency-blocked` label.
- When a blocker **starts** (moves to In progress), the dependent ticket is **startable**:
  remove `dependency-blocked`, move to **Ready** (or Backlog/Needs triage as appropriate).
  It can start even though it cannot *finish* until the blocker closes.
- When a blocker **closes**, the dependent ticket can proceed toward Done.
- **Consumer-chain trace on pull** (added 2026-08-31 after #54/#17/#78): Ready only proves a ticket's OWN blockers are started. Before pulling any ticket to In progress, inspect the ticket it feeds (a T#'s implementation ticket) and confirm no OTHER blocker of that consumer is unstarted — otherwise the pulled ticket's output idles (approved but unconsumable). Work the deepest unstarted blocker first.
- **Never move a ticket directly from Backlog to Done** — always the in-between steps
  (Ready → In progress → In review → Done).

## Labels

Labels carry **blocking/decision state**, NOT workflow position (the column does that):

| Label | Meaning |
|---|---|
| `dependency-blocked` | Cannot start until a `blocked_by` ticket has started. Remove when the blocker starts. |
| `needs-human` | Awaiting a human decision or action (not agent-workable). |
| `needs-triage` | Issue not yet evaluated/routed. |
| `decision-made` | A human decision has been recorded; the ticket is a candidate for a status review. |
| `seam:*` | TDD test seam boundary (adapter-plugin, stream-wrapper, file-system, url-generation, service-api, migration, integrations, stream-wrapper-manager). |
| `planning gap identified` | The issue records a deliverable the planning docs require but no ticket owned at scoping time; waits in **Needs triage** for routing into a milestone/owner. See `docs/agents/triage-labels.md`. |

Deprecated/avoided: `ready-for-agent` and `ready-for-human` duplicate the Ready/Needs
triage columns and are not applied to new tickets.

## Review triggers (the `decision-made` workflow)

On a periodic review pass (user-driven):
- Any ticket in **Needs triage** carrying `decision-made` → decision is recorded; move it
  to its next state (usually **Blocked**/**Backlog** while dependencies remain, or
  **Done** if its blockers are closed).
- Any ticket carrying `dependency-blocked` whose blockers have **started** → remove the
  label and move to **Ready**.

## Board mutation protocol (dry-run first)

Bulk board mutations are error-prone (a wrong item ID or a stale snapshot silently moves
the wrong ticket). Before any bulk status/label change:

1. **Fetch fresh state** immediately before operating (never reuse a previously captured
   snapshot — it goes stale the moment another mutation lands).
2. **Resolve item IDs fresh, keyed by issue number** — query `items` for the issue's `content.number`
   and take its `id` in the SAME step you plan to move it. Never reuse an item ID from memory or an
   earlier command output (IDs are opaque base64 and a mixup is invisible in the mutation's success
   echo — the response returns only the item ID, not the ticket number).
3. **Dry-run**: compute the expected change-set (ticket → status/label) and present it for
   approval before executing.
4. **Apply**, then **re-read** the board and verify the result matches the expected
   change-set exactly — including that each moved item's `content.number` is the intended ticket
   (a mixup drags the WRONG issue; on a Done move it may also auto-close that issue — reopen and
   restore it if caught). Resolve item IDs from the fresh read, not from memory.

## "Update the board" — THE executable procedure (added 2026-09-07)

"Update the board" is a **full reconciliation of the board against the tracker's true
dependency state** — it is NEVER limited to the ticket(s) just approved. SCOPE RULE
(user directive 2026-09-08): full-board review happens ONLY during milestone
planning. While working implementation tickets, every read and every
reconciliation filters to the CURRENT milestone — the agent never fetches,
moves, or reasons about other milestones' tickets unless explicitly instructed
to. The agent executes
this exact ordered checklist, in full, every time the user says "update the board", and the
final step is MANDATORY — the update is not complete until the verification passes.

1. **Fetch fresh state.** One board read (`gh project item-list`) + one GraphQL query of the
    `blockedBy` edges for every OPEN issue on the board, captured immediately before operating.
    Never reuse an earlier snapshot. EFFICIENCY (binding 2026-09-10): scope every pull to the
    current milestone's tickets (extract only those issue numbers; past-milestone closed tickets
    are never fetched); one pull per work phase, reused for all checks in that phase; never
    re-pull to confirm a routine move (the mutation's empty echo means applied — verify
    positions in the next phase's pull); single-card checks via scoped GraphQL aliases, never a
    full pull; REST (`gh issue view/comment/close`, dependencies endpoints) for everything that
    is not a card move. Heavy repeated pulls trigger GitHub's secondary rate limit and freeze
    all card moves (happened 2026-09-10).
2. **Move approved tickets to their correct columns.** Done pairs → Done (both T# and feature,
   same action, then close both issues). A T# whose red tests the user approved but whose
   implementation has NOT started → "Tests complete, failing". A T# whose red tests are authored
   but not yet approved → In review.
3. **Reconcile every non-Done ticket in the current milestone against its real blockers.** For EVERY ticket in
   Backlog and Ready: fetch its actual `blocked_by` edge set. A ticket with an unstarted
   (OPEN) blocker belongs in **Backlog** with `dependency-blocked`. A ticket with NO unstarted
   blockers that is part of the current milestone belongs in **Ready**. Do not skip any ticket;
   do not decide from memory or from an earlier read. (Other milestones' tickets are out of
   scope during implementation work — see the SCOPE RULE above.)
4. **Apply labels.** Add `dependency-blocked` to any Backlog ticket with an unstarted blocker.
   Remove `dependency-blocked` from any ticket whose blockers are all started/closed — regardless
   of column (a stale label in Ready or Done is a defect, fix it).
5. **Verify milestones/board-presence.** Every new ticket is on the board in the correct column
   and carries its milestone and labels.
6. **Verification (MANDATORY, non-skippable).** Re-read the board + edges fresh and confirm the
   resulting state matches the intended change-set exactly: every moved item's `content.number`
   is the intended ticket, every Ready ticket has no unstarted blockers, every Backlog ticket
   with an unstarted blocker carries `dependency-blocked`, no Done ticket carries
   `dependency-blocked`. Report the full change-set to the user — every column move, label change,
   edge change, and the verification result. The update is NOT complete until this step passes.