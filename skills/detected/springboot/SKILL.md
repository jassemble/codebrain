---
name: detected/springboot
description: Stack-aware page-template extras + ECC-bridge for Spring Boot code pages. Activates when pom.xml OR build.gradle contains "spring-boot" AND the source file is .java/.kt. Bridges to ecc:springboot-patterns + ecc:springboot-security.
origin: graphbrain
version: 0.1.1
tier: detected
pattern: Generator
related_skills: [behavioral/graphbrain, ingestion/page-format]
detect:
  - { file_exists: "pom.xml", contains: "spring-boot" }
applies_to_extensions: [".java", ".kt"]
expert_skills: [ecc:springboot-patterns, ecc:springboot-security]
---

# detected/springboot — Spring Boot-aware extras + ECC bridge

## When Activated

One of (project signal):

1. `pom.xml` contains `spring-boot`
2. `build.gradle` contains `spring-boot`

AND file signal: `.java` or `.kt`.

## Inheritance Contract

Extras append AFTER `## Cross-references`. Never replaces.

## Extra Sections This Skill Declares

| Section | What goes in it |
|---|---|
| `## Spring component role` | `@SpringBootApplication`, `@Configuration`, `@Component`, `@Service`, `@Repository`, `@Controller` / `@RestController`, `@RestControllerAdvice`, `@Aspect`, or `@Bean` factory method? |
| `## Beans + autowiring` | Constructor-injected dependencies + their bean types; `@Qualifier` overrides; `@ConditionalOn*` annotations. |
| `## Endpoints (web layer)` | For controllers: `@RequestMapping` / `@GetMapping` / etc. with paths, request bodies, response types. |
| `## Persistence (JPA / Spring Data)` | Entities (`@Entity`, `@Table`, relationships), repositories (`extends JpaRepository`), query methods, custom `@Query`. |
| `## Configuration + properties` | `@ConfigurationProperties` classes, `@Value` injections, profile-specific beans (`@Profile`). |

## Expert-Skill Bridge (v0.1.1)

`expert_skills: [ecc:springboot-patterns, ecc:springboot-security]` — load both when present. Patterns covers architecture/JPA/REST/caching/async; Security covers authn/authz/CSRF/validation/secrets/headers/rate-limiting.

## Cross-references

- Generic page contract: `../../ingestion/page-format/SKILL.md`
- ECC bridge targets: `ecc:springboot-patterns`, `ecc:springboot-security`
- Inlined extras: `../../../commands/brain.md` Step 4b
- Registry entry: `../../registry.json`
