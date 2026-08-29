# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## 2026-08-28 revision — labels vs columns

Per the board-conventions doc (`docs/agents/board.md`), **columns carry workflow position
and labels carry blocking/decision state**. Two canonical labels are **deprecated** in
this project because they duplicate columns and are no longer applied to new tickets:

- `ready-for-agent` → the board's **Ready** column is authoritative.
- `ready-for-human` → the board's **Needs triage** column (with the `needs-human` label) is authoritative.

Labels that remain active as blocking/decision markers: `dependency-blocked`,
`needs-human`, `needs-triage`, `decision-made`, `planning gap identified`, and the `seam:*` family.

- `planning gap identified` — the issue records a deliverable the planning docs require
  but no ticket owned at scoping time (found post-hoc during execution). Such tickets
  sit in **Needs triage** until the gap is routed into a milestone/owner. Created 2026-08-29;
  first applied: #78 (shipped adapter drivers).