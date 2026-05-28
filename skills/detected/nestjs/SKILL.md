---
name: detected/nestjs
description: Stack-aware page-template extras + ECC-bridge for NestJS code pages. Activates when package.json contains "@nestjs/core" AND the source file is .ts. Extras APPEND AFTER the generic 5 sections. Bridges to ECC's expert NestJS pattern skill (ecc:nestjs-patterns) when available.
origin: graphbrain
version: 0.1.1
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format, detected/typescript]
detect:
  - { file_exists: "package.json", contains: "\"@nestjs/core\"" }
applies_to_extensions: [".ts"]
expert_skills: [ecc:nestjs-patterns]
---

# detected/nestjs — NestJS-aware extras + ECC bridge

## When Activated

Both conditions must hold:

1. **Project signal**: `package.json` contains `"@nestjs/core"`
2. **File signal**: source file extension is `.ts`

When a `.tsx` file matches, `detected/typescript` also applies (registry order — TypeScript first).

## Inheritance Contract

Generic 5 sections always written first → NestJS extras append AFTER `## Cross-references`. Never replaces. Same pattern as `detected/react`.

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## NestJS module role` | Is this file a `@Module`, `@Controller`, `@Injectable` (service/provider), `@Pipe`, `@Guard`, `@Interceptor`, `@Filter`, `@Middleware`, or DTO? |
| `## Injections` | Constructor-injected providers + their tokens. Note `@Inject()` overrides and circular-dep workarounds. |
| `## Exports / Imports (Nest module)` | For `@Module` files: what providers are exported; what modules/providers are imported. |
| `## Lifecycle hooks` | `OnModuleInit`, `OnApplicationBootstrap`, `OnModuleDestroy`, `OnApplicationShutdown` implementations. |
| `## Decorators in use` | Nest-specific decorators (`@UseGuards`, `@UseInterceptors`, `@UsePipes`, `@HttpCode`, `@Header`, custom decorators). |

## Expert-Skill Bridge (v0.1.1)

`expert_skills: [ecc:nestjs-patterns]` in `skills/registry.json`. The bridge contract:

- When the agent writes/reviews code in this codebase AND `ecc:nestjs-patterns` is available in the harness: **load `ecc:nestjs-patterns`** for code-writing guidance (module structure, provider patterns, async correctness, DTO validation, exception filters, testing strategy).
- This skill is responsible for page-format extras only; code-writing expertise is delegated to ECC.
- When `ecc:nestjs-patterns` is NOT available, the agent works without that expertise; pages still get the NestJS-aware sections.

Documented in `commands/brain.md` Step 4b "Expert skill bridge".

## Cross-references

- Generic code-page contract: `../../ingestion/page-format/SKILL.md`
- Sibling: `../typescript/SKILL.md` (co-applies on .ts files)
- ECC bridge target: `ecc:nestjs-patterns`
- Inlined load-bearing copy: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
