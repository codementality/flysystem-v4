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
| In review | Work complete, awaiting independent review/approval. |
| Tests complete, failing | **Red-test ticket (T#) terminal state.** The ticket's sole purpose — writing tests designed to FAIL in preparation for an implementation ticket — is complete: the tests are authored and failing (red). The ticket sits here while its implementation ticket makes those tests green. This is NOT "done": it unblocks the implementation ticket to start (the red state satisfies the blocking edge for starting), and both tickets move to Done together once the tests pass. |
| Done | Closed — dependencies done, reviewed, and closed. A T# ticket reaches Done when its tests are green (either immediately, or via the Tests complete, failing column then green). |

## The two-ticket test/implementation dance

A feature ticket and its red-test ticket work as a pair:

1. **T#** writes failing tests → **Tests complete, failing** (not Done).
2. **The implementation ticket starts** — the red state satisfies its blocking edge for *starting* (it does not need T# to be Done to begin).
3. Implementation makes the tests green.
4. **Both move to Done** — T# because its tests pass, the implementation because its work is complete and reviewed. This unblocks anything depending on either.
5. If a T# ticket's tests are already green when its turn arrives (e.g. the work was folded into an earlier slice), it goes **straight to Done** — the "Tests complete, failing" column is only for genuinely red tests awaiting implementation.

## The dependency rule

- A ticket is **Blocked from starting** when a `blocked_by` ticket has **not started**.
  It sits in **Backlog** with the `dependency-blocked` label.
- When a blocker **starts** (moves to In progress), the dependent ticket is **startable**:
  remove `dependency-blocked`, move to **Ready** (or Backlog/Needs triage as appropriate).
  It can start even though it cannot *finish* until the blocker closes.
- When a blocker **closes**, the dependent ticket can proceed toward Done.
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
2. **Dry-run**: compute the expected change-set (ticket → status/label) and present it for
   approval before executing.
3. **Apply**, then **re-read** the board and verify the result matches the expected
   change-set exactly. Resolve item IDs from the fresh read, not from memory.