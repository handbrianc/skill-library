---
name: repo-health--phase-1-discovery
description: "INTERNAL SUBSKILL of repo-health. Project discovery — stack detection, package manager, applicable dimensions. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 1 — Setup & Discovery

**Goal:** Understand project structure, tech stack, package manager, and which audit dimensions actually apply.

## Run

```bash
./skills/repo-health/scripts/scan-setup.sh --mode=discovery
```

## Produce

```
| Dimension         | Stack       | Toolchain          |
| ----------------- | ----------- | ------------------ |
| Language          | TypeScript  | node/npm           |
| Framework         | Next.js 14  | eslint, vitest     |
| Package Manager   | npm         | npm ls             |
| Build Target      | SPA + API   | tsc, next build    |
| Has Specs Dir?    | YES         | ./specs/           |
| Has Docs Dir?     | PARTIAL     | ./docs/ partial    |
| Test Runner       | vitest      | vitest run --coverage |
| Coverage Tool     | —           |                    |
```

Mark any dimension as **NOT APPLICABLE** if the project type makes it irrelevant (e.g., no test runner for a pure-config repo).
