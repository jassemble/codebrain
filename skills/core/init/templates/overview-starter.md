---
kind: overview
status: UNENRICHED
created: <!-- AGENT: insert ISO YYYY-MM-DD -->
last_ingested: <!-- AGENT: insert ISO YYYY-MM-DD on /brain init -->
ingested_by: <!-- AGENT: insert your model identifier, e.g. claude-sonnet-4-6 -->
---

# Overview

## Project Purpose

<!-- AGENT: write 1-3 sentences. Sources to consult, in priority order:
     1. package.json "description" field
     2. pyproject.toml [project] description / setup.py description
     3. README.md tagline (the first paragraph after the H1)
     4. The repo's top-level comment in main entrypoint files
     If none of these exist, write "Project purpose not yet documented; see codebase structure below."
     Do not invent a purpose; if signals are absent, say so. -->

## Codebase Structure

<!-- AGENT: produce a 1-level directory tree of the top-level entries with a one-line purpose each.
     Skip: .git, node_modules, .venv, __pycache__, dist, build, .brain itself, .claude.
     Format:
       - `src/` — application source
       - `tests/` — test suite
       - `docs/` — user-facing documentation
     Infer purpose from directory name + a quick glance at contents; if ambiguous, say "purpose unclear — investigate". -->

## Key Patterns

<!-- AGENT: leave a single line "_Will be populated by Milestone #3 ingest as the codebrain agent
     learns the codebase. /brain ingest src/ is the first step._"
     Do not invent patterns at init time — that's ingest's job. -->

## Active State

<!-- AGENT: write a brief, factual statement of current state. Template:

     - Initialized: <today's ISO date> via `/brain init`
     - Codebrain version: <read from .brain/.codebrain-version>
     - Detected stack: <comma-separated list from /brain init's stack-detection step>
     - Pages: <count of files in .brain/code/ + .brain/concepts/ + .brain/decisions/>
     - Last ingest: never (run `/brain ingest <path>` to begin)
     -->

## Recent Activity

<!-- AGENT: leave a single line "_See `.brain/log.md` for the canonical activity log._"
     This section is intentionally thin — log.md is the source of truth for activity history. -->
