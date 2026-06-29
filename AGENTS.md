<!-- gitnexus:start -->
# GitNexus — Skill Distribution Template

This repo packages GitNexus skill files. Treat as **infrastructure template** — it has no product code and minimal index (1 symbol: "HI").

> If GitNexus tools report "index is stale," run `npx gitnexus analyze` from the project root.

## Two Skill Locations

There are TWO sets of GitNexus skills. **User-installed skills (at `~/.config/opencode/skills/gitnexus-*`) take priority** over project-local ones (at `.claude/skills/gitnexus/`).

- Project-local skills: `.claude/skills/gitnexus/` (gitnexus-cli, exploring, impact-analysis, debugging, refactoring, guide)
- Distributed skills (in `skills/`): `skills/sarcastic/` — a tone/sarcasm skill for the user's amusement

## Enforced Workflows

### Before Editing Any Symbol
1. `gitnexus_impact({target: "symbolName", direction: "upstream"})` — get blast radius
2. Report risk: **HIGH/CRITICAL requires user consent before proceeding**

### Before Committing
- `gitnexus_detect_changes({scope: "staged"})` — verify only expected symbols/execution flows affected

### Exploration
- `gitnexus_query({query: "concept"})` → process-grouped execution flows (prefer over grep)
- `gitnexus_context({name: "symbol"})` → 360° view: callers, callees, processes

### Safe Rename
Always use: `gitnexus_rename({symbol_name: "oldName", new_name: "newName", dry_run: true})`
Graph edits = high confidence; text_search edits = review carefully before accepting.

## Index Maintenance

The index goes stale frequently (visible via `npx gitnexus status`). Refresh with:
```bash
npx gitnexus analyze --force
```
This also regenerates `AGENTS.md` and `CLAUDE.md`.

<!-- gitnexus:end -->