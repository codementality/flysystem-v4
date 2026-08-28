# Board Conventions — @codementality Flysystem 4.0 (Projects v2 #11)

How the project board is structured and how tickets move through it. Read before any
board mutation. The board is the visual workflow; the issue tracker (and its
`blocked_by` dependency edges) is the source of truth for dependencies.

## Columns (left → right)

`Backlog` → `Needs triage` → `Ready` → `In progress` → `In review` → `Done`

| Column | Meaning |
|---|---|
| Backlog | Dependency-blocked (a `blocked_by` ticket has **not started**) OR not yet picked up. Carries the `dependency-blocked` label when a blocker is unstarted. |
| Needs triage | Awaiting a human decision/triage. Tickets here may carry `needs-triage` + `needs-human` labels and, once decided, a `decision-made` label. |
| Ready | Unblocked and startable — every `blocked_by` ticket has **started** (even if not yet closed). |
| In progress | Being worked. |
| In review | Work complete, awaiting independent review/approval. |
| Done | Closed — dependencies done, reviewed, and closed. |

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