#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install-missing-tools.sh — PHASE 1 OS-agnostic tool installer
#
# Installs missing tools detected by scan-environment-tools.sh.
# Detects OS and package manager automatically, supports:
#   Linux: apt (Debian/Ubuntu), dnf (Fedora), yum (RHEL/CentOS),
#          apk (Alpine), zypper (openSUSE/SLES)
#   macOS: Homebrew
#   Others: pip3, npm (cross-platform fallbacks)
#
# Usage:
#   ./install-missing-tools.sh                          # Install ALL missing tools
#   ./install-missing-tools.sh --list                   # List what would be installed
#   ./install-missing-tools.sh --check-only             # Only check what's missing
#   ./install-missing-tools.sh go cargo                 # Install specific tools only
#   ./install-missing-tools.sh --filter=lang            # Only for project-detected stack
#
# Exit: 0 = all requested tools installed, 1 = some failed
# ---------------------------------------------------------------------------
set -euo pipefail

# ---- Paths & Config ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

DRY_RUN=false
CHECK_ONLY=false
LIST_ONLY=false
REQUESTED=()           # empty = all
INSTALL_LOG="/tmp/repo-health-install-$$.log"

# ---- Colour helpers ---------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
  RED='\033[0;31m'; CYAN='\033[0;36m'; GREY='\033[0;90m'; NC='\033[0m'
else
  BOLD=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; GREY=''; NC=''
fi

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
err()  { echo -e "  ${RED}✖${NC} $*" >&2; }
info() { echo -e "  ${GREY}$*${NC}"; }
sec()  { echo -e "\n${BOLD}${CYAN}====${NC} ${BOLD}$*${NC}${BOLD}${CYAN} ====${NC}"; }
sub()  { echo -e "  ${GREEN}$*${NC}"; }

# ---- OS / Package Manager Detection -----------------------------------------

OS="unknown"
PKG_MANAGER=""
PKG_INSTALL=""

detect_os() {
  case "$(uname -s)" in
    Linux)
      OS="linux"
      if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt-get install -y -qq"
      elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
      elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
      elif command -v apk &>/dev/null; then
        PKG_MANAGER="apk"
        PKG_INSTALL="apk add -q"
      elif command -v zypper &>/dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="zypper install -y"
      fi
      ;;
    Darwin)
      OS="macos"
      if command -v brew &>/dev/null; then
        PKG_MANAGER="brew"
        PKG_INSTALL="brew install"
      else
        warn "Homebrew not found. Install from https://brew.sh"
      fi
      ;;
    *)
      OS="$(uname -s)"
      warn "Unsupported OS: $OS — install tools manually."
      ;;
  esac
  info "Detected: OS=${OS}, Package manager=${PKG_MANAGER:-none}"
}

# ---- Sudo wrapper (elevate only if not root) --------------------------------
as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  elif command -v sudo &>/dev/null; then
    sudo "$@"
  else
    err "Need root but no sudo available. Run: $*"
    return 1
  fi
}

# ---- Tool Status Cache ------------------------------------------------------
declare -A TOOL_CACHE

tool_missing() {
  local name="$1"
  if [[ -n "${TOOL_CACHE[$name]:-}" ]]; then
    local cached="${TOOL_CACHE[$name]}"
    # Cache stores 0=present, 1=missing; return inverted 0=missing, 1=present
    if [[ "$cached" -eq 0 ]]; then return 1; else return 0; fi
  fi
  if command -v "$name" &>/dev/null; then
    TOOL_CACHE[$name]=0
    return 1
  else
    TOOL_CACHE[$name]=1
    return 0
  fi
}

# ---- Individual Tool Installers (sourced) ------------------------------------

source "$SCRIPT_DIR/lib/installers.sh"

# ---- Dispatch Table ---------------------------------------------------------
# Maps tool names to installer functions
declare -A INSTALLERS
INSTALLERS=(
  [go]=install_go
  [cargo]=install_cargo
  [semgrep]=install_semgrep
  [syft]=install_syft
  [grype]=install_grype
  [flake8]=install_flake8
  [black]=install_black
  [prettier]=install_prettier
  [typescript]=install_typescript
  [vitest]=install_vitest
  [jest]=install_jest
  [npm-check-updates]=install_npm_check_updates
  [ts-prune]=install_ts_prune
  [bc]=install_bc
  [zip]=install_zip
  [xmlstarlet]=install_xmlstarlet
  [jscpd]=install_jscpd
  [golangci-lint]=install_golangci_lint
  [rubocop]=install_rubocop
  [checkstyle]=install_checkstyle
  [dotnet]=install_dotnet
  [ktlint]=install_ktlint
  [swiftlint]=install_swiftlint
)

# ---- META: Tool Categories & Descriptions -----------------------------------
declare -A TOOL_CATEGORY
declare -A TOOL_DESC
declare -A TOOL_CMD

TOOL_CATEGORY[go]="runtime"
TOOL_DESC[go]="Go programming language"
TOOL_CMD[go]="go version"

TOOL_CATEGORY[cargo]="runtime"
TOOL_DESC[cargo]="Rust package manager + compiler"
TOOL_CMD[cargo]="cargo --version"

TOOL_CATEGORY[semgrep]="security"
TOOL_DESC[semgrep]="Static analysis security scanner (SAST)"
TOOL_CMD[semgrep]="semgrep --version"

TOOL_CATEGORY[syft]="sbom"
TOOL_DESC[syft]="SBOM generator (Anchore)"
TOOL_CMD[syft]="syft version"

TOOL_CATEGORY[grype]="security"
TOOL_DESC[grype]="Vulnerability scanner (Anchore)"
TOOL_CMD[grype]="grype version"

TOOL_CATEGORY[flake8]="linter"
TOOL_DESC[flake8]="Python linter"
TOOL_CMD[flake8]="flake8 --version"

TOOL_CATEGORY[black]="formatter"
TOOL_DESC[black]="Python formatter"
TOOL_CMD[black]="black --version"

TOOL_CATEGORY[prettier]="formatter"
TOOL_DESC[prettier]="Multi-language code formatter"
TOOL_CMD[prettier]="prettier --version"

TOOL_CATEGORY[typescript]="linter"
TOOL_DESC[typescript]="TypeScript compiler (tsc)"
TOOL_CMD[typescript]="tsc --version"

TOOL_CATEGORY[vitest]="test"
TOOL_DESC[vitest]="JavaScript/TypeScript test runner (Vite-based)"
TOOL_CMD[vitest]="vitest --version"

TOOL_CATEGORY[jest]="test"
TOOL_DESC[jest]="JavaScript test runner"
TOOL_CMD[jest]="jest --version"

TOOL_CATEGORY[npm-check-updates]="utility"
TOOL_DESC[npm-check-updates]="npm dependency version checker"
TOOL_CMD[npm-check-updates]="npm-check-updates --version"

TOOL_CATEGORY[ts-prune]="linter"
TOOL_DESC[ts-prune]="TypeScript unused export detector"
TOOL_CMD[ts-prune]="ts-prune --version"

TOOL_CATEGORY[bc]="utility"
TOOL_DESC[bc]="Arbitrary precision calculator"
TOOL_CMD[bc]="bc --version"

TOOL_CATEGORY[zip]="utility"
TOOL_DESC[zip]="Compression utility"
TOOL_CMD[zip]="zip --version"

TOOL_CATEGORY[xmlstarlet]="utility"
TOOL_DESC[xmlstarlet]="XML/coverage report parser"
TOOL_CMD[xmlstarlet]="xmlstarlet --version"

TOOL_CATEGORY[jscpd]="utility"
TOOL_DESC[jscpd]="Copy-paste detection"
TOOL_CMD[jscpd]="jscpd --version"

TOOL_CATEGORY[golangci-lint]="linter"
TOOL_DESC[golangci-lint]="Go linter aggregator"
TOOL_CMD[golangci-lint]="golangci-lint --version"

TOOL_CATEGORY[rubocop]="linter"
TOOL_DESC[rubocop]="Ruby linter"
TOOL_CMD[rubocop]="rubocop --version"

TOOL_CATEGORY[checkstyle]="linter"
TOOL_DESC[checkstyle]="Java linter"
TOOL_CMD[checkstyle]="checkstyle --version"

TOOL_CATEGORY[dotnet]="runtime"
TOOL_DESC[dotnet]=".NET SDK"
TOOL_CMD[dotnet]="dotnet --version"

TOOL_CATEGORY[ktlint]="linter"
TOOL_DESC[ktlint]="Kotlin linter"
TOOL_CMD[ktlint]="ktlint --version"

TOOL_CATEGORY[swiftlint]="linter"
TOOL_DESC[swiftlint]="Swift linter"
TOOL_CMD[swiftlint]="swiftlint --version"

ALL_TOOLS=(
  go cargo           # runtimes
  semgrep syft grype # security/sbom
  flake8 black       # python
  prettier typescript vitest jest ts-prune npm-check-updates jscpd  # node
  bc zip xmlstarlet  # system
  golangci-lint rubocop checkstyle dotnet ktlint swiftlint # language-specific
)

# ---- Main Logic -------------------------------------------------------------

# Parse args
for arg in "$@"; do
  case "$arg" in
    --dry-run|--dryrun) DRY_RUN=true ;;
    --check-only|--check) CHECK_ONLY=true ;;
    --list) LIST_ONLY=true ;;
    --filter=*)
      FILTER="${arg#*=}"
      ;;
    --help|-h)
      echo "Usage: $0 [--dry-run] [--check-only] [--list] [tool1 tool2...]"
      echo ""
      echo "  --dry-run           Show what would be installed without installing"
      echo "  --check-only        Only check which tools are missing"
      echo "  --list              List all managed tools and their status"
      echo "  --filter=runtime    Filter by category (runtime|linter|formatter|security|sbom|test|utility)"
      echo "  tool1 tool2 ...     Install specific tools only"
      exit 0
      ;;
    *)
      REQUESTED+=("$arg")
      ;;
  esac
done

detect_os

# If specific tools requested, use those; otherwise ALL_TOOLS
if [[ ${#REQUESTED[@]} -gt 0 ]]; then
  TARGETS=("${REQUESTED[@]}")
else
  TARGETS=("${ALL_TOOLS[@]}")
fi

# Apply category filter
if [[ -n "${FILTER:-}" ]]; then
  TARGETS=()
  for t in "${ALL_TOOLS[@]}"; do
    if [[ "${TOOL_CATEGORY[$t]:-}" == "$FILTER" ]]; then
      TARGETS+=("$t")
    fi
  done
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    warn "No tools found for category '$FILTER'"
    info "Available categories: runtime linter formatter security sbom test utility"
    exit 0
  fi
fi

# ── LIST mode ────────────────────────────────────────────────────────────────
if $LIST_ONLY; then
  sec "Managed Tools"
  printf "  %-22s %-12s %s\n" "Tool" "Category" "Status"
  printf "  %-22s %-12s %s\n" "----" "--------" "------"
  for t in "${ALL_TOOLS[@]}"; do
    if command -v "${t}" &>/dev/null || [[ "$t" == "typescript" && "$(command -v tsc)" ]]; then
      printf "  ${GREEN}%-22s${NC} %-12s ${GREEN}installed${NC}\n" "$t" "${TOOL_CATEGORY[$t]:-}"
    else
      printf "  ${YELLOW}%-22s${NC} %-12s ${YELLOW}missing${NC}\n" "$t" "${TOOL_CATEGORY[$t]:-}"
    fi
  done
  exit 0
fi

# ── CHECK-ONLY mode ──────────────────────────────────────────────────────────
if $CHECK_ONLY; then
  sec "Missing Tools Check"
  MISSING_COUNT=0
  for t in "${TARGETS[@]}"; do
    # typescript is checked via tsc binary
    local_bin="${t}"
    [[ "$t" == "typescript" ]] && local_bin="tsc"
    if command -v "$local_bin" &>/dev/null; then
      ok "$t (${TOOL_DESC[$t]:-})"
    else
      warn "$t — ${TOOL_DESC[$t]:-}"
      ((MISSING_COUNT++)) || true
    fi
  done
  info ""
  info "Total missing: $MISSING_COUNT"
  if [[ "$MISSING_COUNT" -gt 0 ]]; then
    info "Run without --check-only to install, or pass tool names to install selectively."
  fi
  exit 0
fi

# ── INSTALL mode ─────────────────────────────────────────────────────────────
sec "Tool Installation — OS: ${OS}, Pkg Mgr: ${PKG_MANAGER:-none}"

INSTALLED=0
SKIPPED=0
FAILED=0

for target in "${TARGETS[@]}"; do
  # Resolve bin name — typescript -> tsc
  bin_name="$target"
  [[ "$target" == "typescript" ]] && bin_name="tsc"

  if command -v "$bin_name" &>/dev/null; then
    ok "$target already installed"
    ((SKIPPED++)) || true
    continue
  fi

  installer="${INSTALLERS[$target]:-}"
  if [[ -z "$installer" ]]; then
    warn "$target — no automatic installer available; install manually"
    ((SKIPPED++)) || true
    continue
  fi

  info "Installing $target (${TOOL_DESC[$target]:-})..."

  if $DRY_RUN; then
    info "  [dry-run] would run: $installer"
    ((SKIPPED++)) || true
    continue
  fi

  # Run installer, capture exit code
  set +e
  (
    "$installer"
  ) >> "$INSTALL_LOG" 2>&1
  rc=$?
  set -euo pipefail

  if [[ $rc -eq 0 ]] && command -v "$bin_name" &>/dev/null; then
    ok "$target installed successfully"
    ((INSTALLED++)) || true
  else
    err "$target installation FAILED (exit=$rc)"
    tail -5 "$INSTALL_LOG" | while IFS= read -r line; do err "  $line"; done
    ((FAILED++)) || true
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
sec "Installation Summary"
info "  Total targets: ${#TARGETS[@]}"
info "  Installed:     $INSTALLED"
info "  Skipped:      $SKIPPED"
info "  Failed:       $FAILED"
info "  Log:          $INSTALL_LOG"
echo ""

if [[ "$FAILED" -gt 0 ]]; then
  err "Some tools failed to install. Review log and install manually."
  exit 1
fi

if [[ "$INSTALLED" -eq 0 ]]; then
  info "Nothing new installed — all requested tools already present."
fi

exit 0
