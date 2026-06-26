# Vālet — Redesign Package

Ground-up reinvention of the ValetBook360 valet-parking platform.
**Preserved:** brand magenta (`#A60445` family) + premium dark-luxe personality.
**New:** mobile-first Flutter (Material 3) on a Spring Boot + PostgreSQL + MinIO + Socket.IO + Docker backend (off Supabase).

Author: Nova (Design Director). Audit is grounded in the real codebase — findings cite actual files/lines.

## Read in order

| # | File | What |
|---|---|---|
| 00 | [00-executive-summary.md](00-executive-summary.md) | Thesis, five-pillar redesign, non-negotiables |
| 01 | [01-ux-audit.md](01-ux-audit.md) | Code-cited audit, per surface + scorecard |
| 02 | [02-strategy-and-positioning.md](02-strategy-and-positioning.md) | Positioning, personas, principles |
| 03 | [03-information-architecture.md](03-information-architecture.md) | IA + screen hierarchy per role |
| 04 | [04-user-flows.md](04-user-flows.md) | Flow diagrams + lifecycle (Mermaid) |
| 05 | [05-navigation.md](05-navigation.md) | Mobile navigation per role |
| 06 | [06-design-system.md](06-design-system.md) | Tokens, components, motion, a11y |
| 07 | [07-screen-specs.md](07-screen-specs.md) | Screen-by-screen layouts + state matrices |
| 08 | [08-accessibility-responsive.md](08-accessibility-responsive.md) | WCAG + adaptive behavior |
| 09 | [09-flutter-implementation.md](09-flutter-implementation.md) | Widget map, navigation, timings |
| 10 | [10-backend-integration.md](10-backend-integration.md) | Microservices, Postgres, MinIO, Socket.IO, Docker |
| 11 | [11-developer-handoff-and-scale.md](11-developer-handoff-and-scale.md) | DoD, build order, scale-to-millions |
| — | [tokens.json](tokens.json) | DTCG design tokens (source of truth) |

## The one thing to remember

> The old product is a desktop dashboard on a phone. Vālet is a **gesture-first operational instrument**: one thumb, one glance, one action — built for the valet's worst moment (8pm Friday, rain, gloves, weak signal). The 8-state transaction lifecycle is the visible spine of the whole experience.
