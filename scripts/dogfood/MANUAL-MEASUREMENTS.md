# graphbrain — manual measurements procedure

This document describes the **LLM-driven measurements** for graphbrain v0.1 validation. These can't be automated in bash; they require real Claude Code sessions, real time, and (for M2) real ongoing edits.

Run these on **3 target repos** per the PRD M#8 outcome:

1. **graphbrain itself** — `/Users/dev/Desktop/Project/OSS/idea/graphbrain/`
2. **graphify** — `/Users/dev/Desktop/Project/OSS/idea/graphify/`
3. **graphbrain** — `/Users/dev/Desktop/Project/OSS/idea/graphbrain/`

Record each measurement in `.claude/validation/v0.1-baseline.md` under the matching section.

---

## M1 — Token-reduction A/B (10 questions × 3 repos = 30 measurements)

**Target**: ≥ 50% token reduction on structural questions vs. grep+read baseline.

### Setup (per repo)

```
cd <target-repo>
npx graphbrain init
# Restart Claude Code or open a new session
/brain init
/brain ingest src/        # or appropriate top-level source folder
```

### Procedure

For each of the 10 canned questions below:

**Round A (baseline — grep+read)**:

1. Open a **fresh** Claude Code session in the target repo (no `.brain/` available, OR explicitly tell the agent to ignore it)
2. Paste the question verbatim
3. Note the token cost via `/cost` after the agent answers
4. Note answer quality (subjective 1–5)

**Round B (with brain)**:

1. Open another fresh Claude Code session in the target repo
2. Paste the question prefixed with: `Use /brain query to answer this:`
3. The agent should invoke `/brain query "<question>"` per the M#5 procedure
4. Note token cost
5. Note answer quality

**Reduction**: `(A_tokens - B_tokens) / A_tokens × 100`

### Canned questions

Pick a representative mix — some structural, some cross-cutting:

1. "What does this codebase do?" *(overview)*
2. "How does authentication work end-to-end?" *(cross-cutting)*
3. "What does `<file>` export?" *(pick a real file from this repo — structural)*
4. "Where do we touch `<library/integration>`?" *(pick a real dep — cross-cutting)*
5. "What's the role of `<module>`?" *(pick a real module — structural)*
6. "What are the main entry points?" *(structural)*
7. "What are the key data structures / domain entities?" *(cross-cutting)*
8. "Where would I add a new `<feature>`?" *(action-oriented)*
9. "What conventions does this codebase follow?" *(cross-cutting)*
10. "What's the error-handling pattern?" *(cross-cutting)*

### Record

In `.claude/validation/v0.1-baseline.md` § M1, append a sub-table per repo:

```
### M1 — <repo name>

| # | Question | A tokens | B tokens | Reduction | A quality | B quality |
|---|---|---|---|---|---|---|
| 1 | What does this codebase do? | 4200 | 1100 | 74% | 4 | 4 |
| ... |
```

Compute average across the 10 questions per repo, and overall.

---

## M2 — Freshness drift (≥ 7 days of typical agent work)

**Target**: < 5% of total pages are true-stale after a week.

### Procedure

1. After M1's ingest is in place, **leave the brain alone**
2. Do **normal coding work** for at least 7 days — Edit/Write source files via Claude Code in the usual way; the M#4 PostToolUse hook will auto-flip pages STALE
3. After day 7: run `/brain lint`
4. Count from the report:
   - **Total pages**: from the Inventory section
   - **True-stale**: from `## Defects → Stale (true)` count
5. Compute: `true-stale / total × 100`

### Record

In `.claude/validation/v0.1-baseline.md` § M2:

```
### M2 — <repo name>
- Started: <date>
- Ended: <date> (<N> days)
- Total pages: <N>
- True-stale at end: <N>
- Stale rate: <percent>%
- Edits in window: <approximate count>
```

---

## M3 — Wikilink precision (manual sample)

**Target**: ≥ 90% precision.

### Procedure

1. After M1's ingest, walk `.brain/**/*.md` and collect every wikilink (`[[code/<path>]]`, `[[concepts/<name>]]`, `[[decisions/<adr>]]`)
2. Random-sample 100 wikilinks (or all if < 100 exist)
3. For each:
   - **Existence check**: does the target page exist in `.brain/`? (M#6 lint already catches; should be 100%)
   - **Relationship check** (the precision question): does the description match reality? E.g., if `[[code/auth.ts]] — issues JWTs` is on a page, open `code/auth.ts.md` — does it actually describe a file that issues JWTs?
4. Mark each as `correct | incorrect | ambiguous`
5. Precision = `correct / total × 100`

### Record

```
### M3 — <repo name>
- Total wikilinks sampled: <N>
- Correct: <N>
- Incorrect: <N>
- Ambiguous: <N>
- Precision: <N>%
```

---

## M4 — Time-to-first-value (wall-clock)

**Target**: < 5 minutes from `npx graphbrain init` to first useful wiki page.

### Procedure

On a clean target repo (no `.brain/`, no `.claude/commands/brain*`, no graphbrain entries in settings.local.json):

1. **Stopwatch start**
2. `npx graphbrain init`
3. Restart Claude Code session
4. `/brain init`
5. `/brain ingest src/<the most important file or folder>`
6. `/brain query "what does this codebase do?"`
7. **Stopwatch stop** when the operator has the answer

### Record

```
### M4 — <repo name>
- Start: <time>
- npx graphbrain init: <duration>
- restart + /brain init: <duration>
- /brain ingest: <duration>
- /brain query: <duration>
- Total: <duration>
- Met target (<5 min): yes / no
```

---

## M5 — Continuous-learning lift

**Target**: TBD (deferred). Depends on Milestone #7's observer agent + XDG instinct store.

### Status

`pending Milestone #7` — the observer agent + XDG store don't exist in v0.1. Re-evaluate after M#7 ships.

When ready, the procedure will be:

1. Take a target repo. Ingest as in M1.
2. Run a week's worth of normal coding work (M2's procedure).
3. After the week: dump the XDG instincts via `/brain instincts` (M#7 verb).
4. Spot-check: do the captured instincts reflect things you actually do in this codebase? Are they specific or generic?
5. Record qualitative + quantitative findings.

---

## Summary checklist

After completing M1–M4 on all 3 repos:

- [ ] M1 measurements recorded (30 question/repo combinations)
- [ ] M2 measurements recorded (3 repos × 1 week each)
- [ ] M3 measurements recorded (3 repos × ~100 wikilinks each)
- [ ] M4 measurements recorded (3 repos)
- [ ] M5 marked pending pending Milestone #7
- [ ] Validation report `.claude/validation/v0.1-baseline.md` overall verdict updated
- [ ] If any metric missed by ≥20%, file follow-up items in the PRD Open Questions

---

## Notes on running these measurements

- **Cost discipline**: M1 alone runs 30 × 2 = 60 LLM calls. Budget ~$5–10 for the full M1 across 3 repos. Set `CODEBRAIN_PROFILE=minimal` if you want to avoid the observer's overhead during measurement (relevant once M#7 ships).
- **Repeatability**: record the graphbrain version used for each measurement (`graphbrain version`). M2 in particular spans a week — graphbrain may upgrade between start and end; note any version changes.
- **Honest reporting**: if a metric MISSES its target, document what happened. The goal of M#8 is to know whether graphbrain delivers, not to confirm a hypothesis. A 30% token reduction is still useful; a 0% reduction is a signal to revise the design.
