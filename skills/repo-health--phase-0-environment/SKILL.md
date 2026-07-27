---
name: repo-health--phase-0-environment
description: "INTERNAL SUBSKILL of repo-health. Environment readiness gate — validates baseline tools and prerequisites. Not for direct invocation."
subskill-of: repo-health
---

# PHASE 0 — Environment Readiness (Gate + Auto-Install)

**Goal:** Validate baseline tools, install missing project-type tools automatically,
then proceed. Only abort if core utilities are irrecoverably missing.

## Required Core Utilities (blocking if missing)

- Bash >= 4.0
- Node.js >= 18
- Git installed and accessible
- `jq` for JSON parsing
- GNU `find` with `-maxdepth` support
- GNU `grep` with BRE alternation support (`\|`)
- `timeout`/`gtimeout` (macOS: `brew install coreutils`)

## Optional Tools (auto-installed by category)

| Category | Tools | Auto-Install |
| ---------- | ------- | ------------- |
| **Test runners** | vitest, jest, pytest | `./install-missing-tools.sh --filter=test` |
| **Security** | semgrep, grype | `./install-missing-tools.sh --filter=security` |
| **SBOM** | syft | `./install-missing-tools.sh --filter=sbom` |
| **Linters** | flake8, typescript, golangci-lint, rubocop, checkstyle, ktlint, swiftlint, ts-prune | `./install-missing-tools.sh --filter=linter` |
| **Formatters** | black, prettier | `./install-missing-tools.sh --filter=formatter` |
| **Runtimes** | go, cargo, dotnet | `./install-missing-tools.sh --filter=runtime` |
| **Utilities** | bc, zip, xmlstarlet, jscpd, npm-check-updates | `./install-missing-tools.sh --filter=utility` |

## Run

```bash
# Step 0.0 — Ensure GNU toolchain on macOS (auto-setup)
# If on macOS, the install-missing-tools.sh will detect and install GNU grep +
# coreutils via Homebrew if not present. This is required for grep -P and realpath -m.
./skills/repo-health/scripts/install-missing-tools.sh gnu-grep coreutils gnu-date 2>&1 | tail -5

# Export GNU tools PATH (macOS Homebrew installs them with 'g' prefix by default;
# gnubin wrappers provide standard names)
if command -v ggrep &>/dev/null && ! echo "test" | grep -P 't' &>/dev/null 2>&1; then
  export PATH="$(brew --prefix 2>/dev/null)/opt/grep/libexec/gnubin:$PATH"
fi
if command -v grealpath &>/dev/null && ! realpath -m . &>/dev/null 2>&1; then
  export PATH="$(brew --prefix 2>/dev/null)/opt/coreutils/libexec/gnubin:$PATH"
fi

# Step 0.1 — Check what's present
./skills/repo-health/scripts/scan-environment.sh --check-tools
```

**If any core utility prints `MISSING/BROKEN`** (bash, node, npm, npx, git, jq, find):

- Collect all missing/malformed core items into a single block
- **ABORT — do not proceed to PHASE 1**
- Report using this template:

```markdown
## 🚫 ENVIRONMENT GAP — Cannot Proceed

The following tools are missing or broken. Install them before re-running:

| Tool | Status | Install Command |
| ---- | ------ | --------------- |
| bash | MISSING | (system package manager) |
| ...  | ...    | ...             |
```

**If `grep -P` or `realpath -m` are the ONLY missing items** (macOS GNU toolchain):

- Do NOT abort. These are NOT core utilities — they are platform-specific conveniences.
- Run auto-install if not already attempted:
  ```bash
  ./skills/repo-health/scripts/install-missing-tools.sh gnu-grep coreutils gnu-date
  ```
- If install succeeds, continue. If it fails, proceed to Phase 1 anyway — scanners
  will use fallback detection for `grep -P` and `realpath -m`.

**If only optional tools are missing** (MISSING (optional)):

```bash
# Step 0.2 — Auto-install all missing optional tools
./skills/repo-health/scripts/install-missing-tools.sh

# Or install by category matching the project's detected stack
./skills/repo-health/scripts/install-missing-tools.sh --filter=test
./skills/repo-health/scripts/install-missing-tools.sh --filter=security

# Step 0.3 — Re-verify after install
./skills/repo-health/scripts/scan-environment.sh --check-tools
```

The installer (`install-missing-tools.sh`) auto-detects the OS and package manager:
**Linux** (apt/dnf/yum/apk/zypper) and **macOS** (Homebrew), with pip3/npm/curl fallbacks.

If any optional tool still cannot be installed, proceed to Phase 1 anyway — the
missing tool's corresponding scanner section will produce reduced or empty output,
and findings will be adjusted accordingly.
