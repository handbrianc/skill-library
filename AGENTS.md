<!-- gitnexus:start -->
# GitNexus — Skill Library

This is a GitNexus skill distribution repo. Index is minimal (1 symbol) — treat as infrastructure template, not production code.

> If any GitNexus tool warns "index is stale", run `npx gitnexus analyze` from the project root first.

## Core Workflow (Enforced)

### Before Editing Any Symbol
1. `gitnexus_impact({target: "symbolName", direction: "upstream"})` — get blast radius
2. Report risk to user: **HIGH/CRITICAL requires explicit user consent before proceeding**
3. Make edits

### Before Committing
- `gitnexus_detect_changes({scope: "staged"})` — verify only expected symbols/execution flows are affected

### Exploration Defaults
- Use `gitnexus_query({query: "concept"})` instead of grep — returns process-grouped execution flows
- Use `gitnexus_context({name: "symbol"})` for 360° symbol view (callers, callees, processes)

## Naming Safety

**NEVER** use find-and-replace to rename symbols — use only:
```
gitnexus_rename({symbol_name: "oldName", new_name: "newName", dry_run: true})
```
Review all edits before accepting. Confidence-tagged: `graph` (high) vs `text_search` (needs scrutiny).

## Skill File References

| Task | File |
|------|------|
| Architecture, "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius, "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Bug hunting, "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, graph schema, resources | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index/clean/wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

## Repo Resources

| Resource | Purpose |
|----------|---------|
| `gitnexus://repo/skill-library/context` | Overview + index freshness check |
| `gitnexus://repo/skill-library/clusters` | Functional areas with cohesion scores |
| `gitnexus://repo/skill-library/processes` | All execution flow traces |
| `gitnexus://repo/skill-library/process/{name}` | Specific step-by-step flow |

<!-- gitnexus:end -->