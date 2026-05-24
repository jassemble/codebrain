---
kind: code
status: <!-- AGENT: insert FRESH on first ingest, RESYNCED on refresh -->
source: <!-- AGENT: insert relative path from repo root, e.g. src/api/auth.ts -->
source_hash: <!-- AGENT: insert format-prefixed hash — `git:<hash>` from `git hash-object <path>`, or `sha256:<hash>` from `shasum -a 256 <path>` -->
last_ingested: <!-- AGENT: insert today's ISO date YYYY-MM-DD -->
ingested_by: <!-- AGENT: insert your model identifier, e.g. claude-sonnet-4-6 -->
tokens: <!-- AGENT: insert your best estimate of page token count; informational, ±20% is fine, not enforced -->
---

# <!-- AGENT: insert source-path verbatim, e.g. src/api/auth.ts -->

## Purpose
<!-- AGENT: 1-3 sentences. What this file is responsible for. Infer from the
     file's symbols, comments, imports/exports, and any docstring at the top.

     For CODE files (.ts, .py, .go, .rs, etc.): describe responsibility in
     terms of what the code does. Be concrete; avoid generic phrases like
     "this module".

     For NON-CODE files (config, schema, YAML, JSON, SQL, CSS, docs):
     describe what the file configures, declares, or documents.

     For EMPTY files (0 bytes): write `_(empty file)_`.

     If you cannot infer purpose at all, write `_(unclear — investigate)_`.
     Do not invent. -->

## Exports
<!-- AGENT: bullet list of exported symbols (functions, classes, constants,
     types). One line per symbol: `- name: one-line purpose`.

     Keep purposes 1 line — do not enumerate parameters or return types here.
     The source file is the canonical reference for signatures.

     If the file has no exports (e.g., a CSS file, a config, an empty file),
     write `_(none)_`.

     For empty files: `_(none)_`. -->

## Imports
<!-- AGENT: bullet list grouped by source module. Format:
       - from `<module>`: <name1>, <name2> — <why this file needs them>

     Skip stdlib imports unless they're load-bearing (e.g., `fs/promises`
     for a file that reads disk; `os` for cross-platform path handling).

     If nothing notable, write `_(none)_`.
     For empty files: `_(none)_`. -->

## Key behaviors
<!-- AGENT: bullet list of notable behaviors, error paths, side effects,
     I/O, state mutation, network calls. Pick the 3-7 things a reader most
     needs to know — NOT a line-by-line transcription of the code.

     If the file is trivial (e.g., a re-export shim, a constants file),
     write `_(trivial — see Exports above)_`.
     For empty files: `_(empty file)_`. -->

## Cross-references
<!-- AGENT: wikilinks to other .brain/code/ pages this file calls or
     extends. Format: `- [[code/src/path/other.ts]] — <why linked>`.

     In Milestone #3a (this milestone) we typically only have one page (this
     one), so this section is usually `_(none yet — see Milestone #3b for
     cross-page linking)_`.

     If you have evidence the source file imports from other files in the
     repo that you know will be ingested later, you MAY wikilink to them;
     the M#6 lint pass will flag dangling links. -->
