# Code Review Guide — @codementality Flysystem 4.0

How a code review in this project is **written**, so the person acting on it — a human or an
implementation agent — can extract "what is wrong, how bad, what do I fix, in what order" in one pass.
The reviews this guide replaces were thorough but hard to read: findings were ordered by discovery,
severity was buried mid-prose, the verdict came after the explanation, and the disposition was
detached from the findings. This guide exists so that never happens again.

Read before running any review. Reviewers (including the `code-review` agent) must produce output
that follows this shape.

---

## 1. The one-screen contract

A reviewer writes for a reader who will act on the findings. That reader must be able to answer four
questions without re-reading:

1. **What is the verdict?** — first sentence.
2. **What must be fixed before this ships?** — a list, by severity, nothing else.
3. **Why does each matter?** — one sentence per finding, the harm if ignored.
4. **How was it verified?** — the exact command/output that proves each finding.

If a reader cannot get all four from a single pass, the review is not finished.

---

## 2. Document structure (fixed)

Every review uses this exact skeleton, in this order. No exceptions.

```
# <Scope> — Independent <Plan|Code> Review

Status: <Review|Approved>, <date>. Scope: <milestone/ticket set>, <commits reviewed>,
<docs the work is judged against>.

## Executive summary
- Verdict (1–3 lines): met / not met, and the headline reason.
- Gate table (if code): the canonical QA gates and their actual results.

## Findings — by severity
- CRITICAL — <one line each>
- HIGH — <one line each>
- MEDIUM — <one line each>
- LOW / hygiene — <one line each>

## Findings detail
For each finding, the FIXED block shape in §3.

## What this review got right
Deliberate, brief. Bounds the findings; tells the reader what is solid.

## Verification
The exact commands + expected output that reproduce the findings.

## Disposition
What to file (new tickets, rescopes, board changes), by priority. This section
ONLY references the findings by their IDs — it never re-explains them.
```

---

## 3. The per-finding block (fixed shape)

Each finding is a block with exactly these labeled parts, in this order. The labels are part of the
format — keep them.

```
### C1. <Defect in one line> — <SEVERITY> *(verified|reviewed)*

**What:** <one sentence: the code does X when it should do Y.>
**Evidence:** <file:line, and the exact observed output if verified. A verification is
  "I ran <command> and got <output>" — never "this would fail".>
**Impact:** <one sentence: the harm if ignored, and who hits it.>
**Fix:** <one paragraph or a bullet list of the concrete change.>
```

Rules for the block:

- **Severity is in the header**, in capitals, never buried in prose. Definitions:
  - `CRITICAL` — breaks a primary user-facing operation, or a security/data-integrity exposure.
  - `HIGH` — a contract in a green ticket is unmet, or a real correctness/resource gap.
  - `MEDIUM` — correctness or robustness gap that does not break a primary path.
  - `LOW` / hygiene — naming, docs, style, dead code.
- **One finding = one defect.** A finding with two unrelated defects is two findings. If two defects
  share a root cause, they are one finding and the root cause is named once, in `**What:**`.
- **Evidence before impact.** The reader needs to trust the claim before caring about the harm.
- **`*(verified)*` is earned, not claimed.** It means you ran the exact command and read its output.
  Anything inferred from code shape is `*(reviewed)*` — never silently upgrade.
- **The fix is concrete.** Name the method/change, not the goal. "Resolve source and destination
  independently, four combinations" is a fix; "make copy/move work" is a wish.

---

## 4. Ordering and grouping

- **Findings are ordered by severity, then by blast radius.** All CRITICAL first, then HIGH, then
  MEDIUM, then LOW. Within a severity, the one that breaks the most callers comes first. Never order
  by the order you happened to find them.
- **The severity table in §2 is the navigation aid.** It lists every finding in one line each, so a
  reader who only reads the summary knows the full shape. The detail section is for the reader who
  needs the evidence.
- **Group only when the fix is one commit.** Three findings that are three separate fixes are three
  findings. Three findings fixed by one change are one finding with three sub-bullets under `**Fix:**`.

---

## 5. Tables over prose, bullets over paragraphs

- **A blast-radius table beats three paragraphs.** If a defect has multiple callers, list them:
  `caller | file:line | effect`. Do not describe each caller in prose.
- **The gate table in §1 is always a table** (`gate | result`).
- **Bullets, not prose**, for: the severity list, verification commands, and the disposition.
- **No walls of code in findings.** Quote only the 2–5 lines that carry the defect, with a
  `file:line` anchor. The reader opens the file for the rest.

---

## 6. Language and length

- **The verdict is the first sentence of the review and the first sentence of every finding.**
- **No hedging.** "This fails" not "this appears to fail". If you did not verify it, say
  `*(reviewed)*` and be explicit about the uncertainty — do not soften with "appears".
- **One line per finding in the summary.** If it cannot be said in one line, the finding is two.
- **American English spelling** (project rule 9).
- **A review is not an essay.** The detail section is long only because the defects are real; the
  writing around them is minimal.

---

## 7. What a review is not

- **Not a style pass.** PHPCS/PHPStan already run in the pipeline; a finding that is purely "this
  would fail phpcs" goes in LOW/hygiene or is dropped.
- **Not a re-run of the gates.** The gate table records the gates' results; it does not re-analyze
  what they already cover.
- **Not a fix.** A review reports. Fixing is the implementation agent's job; the review's `**Fix:**`
  is guidance for that agent, never a code change in the review.
- **Not a re-explanation of the disposition.** The disposition references finding IDs only.

---

## 8. Self-check before delivery

Before the review is handed over, the reviewer reads it as the *acting agent* would and confirms:

1. The verdict is the first sentence.
2. The severity list in §2 is complete and matches the detail section's headers.
3. Every `*(verified)*` is backed by an exact command + output in §6 (Verification).
4. Every finding's `**Fix:**` is concrete enough to hand to an implementation agent.
5. The disposition is cross-referenced by finding ID and nothing else.
6. A reader who stops after the executive summary and severity list knows what to fix, in what order.

If any answer is no, the review is not finished.