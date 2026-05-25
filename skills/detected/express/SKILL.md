---
name: detected/express
description: Stack-aware page-template extras + ECC-bridge for Express code pages. Activates when package.json contains "express" AND the source file is .ts/.js. Bridges to ecc:backend-patterns.
origin: codebrain
version: 0.1.1
tier: detected
pattern: Generator
related_skills: [behavioral/codebrain, ingestion/page-format, detected/typescript]
detect:
  - { file_exists: "package.json", contains: "\"express\"" }
applies_to_extensions: [".ts", ".js"]
expert_skills: [ecc:backend-patterns]
---

# detected/express — Express-aware extras + ECC bridge

## When Activated

1. **Project signal**: `package.json` contains `"express"`
2. **File signal**: `.ts` or `.js`

When `.ts`, `detected/typescript` also applies.

## Inheritance Contract

Extras append AFTER `## Cross-references`.

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## Express route role` | App entry (`app.listen`), router (`express.Router()`), route handler, middleware factory, or error handler? |
| `## Middleware chain` | Middlewares applied (cors, body-parser, custom auth) in registration order. |
| `## Route patterns` | HTTP method + path templates. Format: `- GET /users/:id — list users` |
| `## Error handling` | Error-handling middleware (4-arg signature); `next(err)` call sites. |
| `## Side effects` | `res.cookie`, `res.session`, streaming responses, file uploads, WebSocket upgrades. |

## Expert-Skill Bridge (v0.1.1)

`expert_skills: [ecc:backend-patterns]` — general backend patterns (API design, error handling, request validation). No Express-specific ECC skill exists yet; v0.2 may add one.

## Cross-references

- Generic page contract: `../../ingestion/page-format/SKILL.md`
- Sibling: `../typescript/SKILL.md`
- Inlined extras: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
