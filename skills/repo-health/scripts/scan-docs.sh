#!/usr/bin/env bash
#
# scan-docs.sh
# Documentation audit — inventory docs and check accuracy.
# Covers PHASE 4 of the repo-health audit.
#
# Usage: ./scan-docs.sh [--check-links]
#
# Target directory: $REPO_HEALTH_TARGET_DIR env override, else the current
# working directory.
#
# The previous version piped a plain `ls README* INSTALL* ...` into an
# `|| echo "No standard doc files found"` fallback: when SOME operands existed
# ls printed them but still exited 2 (other operands missing), so the script
# listed the files AND claimed none were found. Now existence is checked per
# glob before listing.
#

set -euo pipefail

TARGET_DIR="${REPO_HEALTH_TARGET_DIR:-$PWD}"
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "SCAN_DOCS_ERROR: target directory not found: $TARGET_DIR" >&2
  exit 1
fi
cd "$TARGET_DIR"
shopt -s nullglob

echo "=== DOCUMENTATION INVENTORY ==="

# Step 4.1 — Inventory all docs (dependency/vendor/build trees excluded)
DOC_FILE_COUNT=$(find . -maxdepth 3 \( -name "*.md" -o -name "*.rst" -o -name "*.txt" \) \
  -not -path "./node_modules/*" -not -path "./.venv/*" -not -path "./venv/*" \
  -not -path "./.git/*" -not -path "./__pycache__/*" -not -path "./site-packages/*" \
  -not -path "*.dist-info/*" -not -path "./.tox/*" -not -path "./.mypy_cache/*" \
  -not -path "./.ruff_cache/*" -not -path "./.pytest_cache/*" \
  -not -path "./dist/*" -not -path "./build/*" -not -path "./target/*" \
  -type f -print 2>/dev/null | wc -l | tr -d '[:space:]')
echo "DOC_FILE_COUNT: ${DOC_FILE_COUNT:-0} (md/rst/txt, depth<=3, vendor dirs excluded)"

find . -maxdepth 3 \( -name "*.md" -o -name "*.rst" -o -name "*.txt" \) \
  -not -path "./node_modules/*" -not -path "./.venv/*" -not -path "./venv/*" \
  -not -path "./.git/*" -not -path "./__pycache__/*" -not -path "./site-packages/*" \
  -not -path "*.dist-info/*" -not -path "./.tox/*" -not -path "./.mypy_cache/*" \
  -not -path "./.ruff_cache/*" -not -path "./.pytest_cache/*" \
  -not -path "./dist/*" -not -path "./build/*" -not -path "./target/*" \
  -type f -exec wc -l {} \; 2>/dev/null | sort -rn | head -30 || true

# Step 4.2 — Standard top-level docs (list only what exists)
echo ""
STD_DOCS=()
for f in README* INSTALL* CONTRIBUTING* CHANGELOG* AUTHORS* SECURITY* \
         LICENSE* LICENCE* COPYING* NOTICE* CODE_OF_CONDUCT* MAINTAINERS*; do
  if [[ -f "$f" ]]; then STD_DOCS+=("$f"); fi
done
if (( ${#STD_DOCS[@]} > 0 )); then
  ls -lh -- "${STD_DOCS[@]}"
  echo "STANDARD_DOC_COUNT: ${#STD_DOCS[@]}"
else
  echo "No standard doc files found"
fi

# docs/ directory and named root docs — checked separately so a missing
# API.md can no longer mask an existing docs/ directory.
echo ""
if [[ -d docs ]]; then
  ls -lh docs/ 2>/dev/null | head -40 || true
else
  echo "(no docs/ directory)"
fi
NAMED_DOCS=()
for f in README.md API.md ARCHITECTURE* DESIGN* GUIDE*; do
  if [[ -f "$f" ]]; then NAMED_DOCS+=("$f"); fi
done
if (( ${#NAMED_DOCS[@]} > 0 )); then
  ls -lh -- "${NAMED_DOCS[@]}"
else
  echo "(no named root doc files: README.md, API.md, ARCHITECTURE*, DESIGN*, GUIDE*)"
fi

# Step 4.3 — Accuracy check (link rot)
if [[ "${1:-}" == "--check-links" ]]; then
  echo ""
  echo "=== LINK ROT CHECK ==="
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/check-doc-links.sh" ]]; then
    "$SCRIPT_DIR/check-doc-links.sh" docs/ || true
  else
    echo "check-doc-links.sh: not available"
  fi
fi

echo ""
echo "DOC_SCAN_COMPLETE"
exit 0
