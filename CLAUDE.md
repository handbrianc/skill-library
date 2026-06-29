<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **skill-library** (129 symbols, 125 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/skill-library/context` | Codebase overview, check index freshness |
| `gitnexus://repo/skill-library/clusters` | All functional areas |
| `gitnexus://repo/skill-library/processes` | All execution flows |
| `gitnexus://repo/skill-library/process/{name}` | Step-by-step execution trace |

## CLI

| Task | How |
|------|-----|
| Understand architecture / "How does X work?" | Use `query({search_query: "concept"})` built-in tool |
| Blast radius / "What breaks if I change X?" | Use `impact({target: "symbolName", direction: "upstream"})` built-in tool |
| Trace bugs / "Why is X failing?" | Use `context({name: "symbolName"})` built-in tool |
| Rename / extract / split / refactor | Use `rename` built-in tool |
| Tools, resources, schema reference | See Resources table above |
| Index, status, clean, wiki CLI commands | Run `node .gitnexus/run.cjs` from the project root |

<!-- gitnexus:end -->
