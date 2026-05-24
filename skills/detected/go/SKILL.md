---
name: detected/go
description: Stack-aware page-template extras for Go code pages. Loaded by /brain ingest when a Go project is detected (go.mod exists) AND the source file's extension is .go. Extras APPEND AFTER the generic 5 sections — never replace.
origin: codebrain
version: 0.1.0
tier: detected
pattern: Generator
related_skills: [behavioral/codebrain, ingestion/page-format]
detect:
  - { file_exists: "go.mod" }
applies_to_extensions: [".go"]
---

# detected/go — Go-aware code-page extras

## When Activated

Activates when BOTH conditions are met:

1. **Project signal**: `go.mod` exists in the repo root.
2. **File signal**: source file extension is `.go`.

## Inheritance Contract

Always appends AFTER `## Cross-references`. Never replaces. See `detected/react/SKILL.md` for the full ordering rule.

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## Package` | Package declaration + the file's role in the package. Examples: "main package — CLI entry point", "package auth — middleware for JWT validation". |
| `## Receivers` | Bullet list of methods grouped by receiver type. Format: `- (s *Server) Method(...) — purpose`. `_(none)_` if no methods. |
| `## Interfaces satisfied` | Bullet list of interfaces this file's types satisfy (inferred from method sets). Format: `- TypeName satisfies io.Reader, fmt.Stringer`. `_(none observed)_` if uncertain. |
| `## init() functions` | Any `init()` functions defined in this file with a description. `_(none)_` if none. |
| `## Build tags` | Any `//go:build` or legacy `// +build` tags at the top of the file. `_(none)_` if no build constraints. |

## Examples

For a file `internal/auth/middleware.go`:

```go
//go:build !test

package auth

import "net/http"

func init() {
    registerMiddleware("auth", New)
}

type Middleware struct {
    secret string
}

func New(secret string) *Middleware { return &Middleware{secret: secret} }

func (m *Middleware) Wrap(next http.Handler) http.Handler { ... }
```

Go extras:

```
## Package
package auth — JWT-based HTTP middleware. This file defines the Middleware
type and its registration. Other files in the package (auth/token.go,
auth/claims.go) handle token issuance and claim verification.

## Receivers
- (m *Middleware) Wrap(next http.Handler) http.Handler — wraps a handler with JWT validation

## Interfaces satisfied
- Middleware.Wrap is a func(http.Handler) http.Handler — usable as a
  standard net/http middleware combinator

## init() functions
- init: registers this middleware in the package-level middleware registry
  via registerMiddleware("auth", New). Side effect of importing this file.

## Build tags
- //go:build !test — file is excluded from test builds
```

## Cross-references

- Generic code-page contract: `../../ingestion/page-format/SKILL.md`
- Inlined load-bearing copy: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
- PRD design decisions: #21, #22, #23, #7
