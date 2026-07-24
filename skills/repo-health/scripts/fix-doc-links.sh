#!/usr/bin/env bash
#
# fix-doc-links.sh
# Check and report broken external links in documentation files.
# Does NOT modify files — only reports findings for review.
# For auto-fixable links (internal), applies corrections.
#
# Usage: ./fix-doc-links.sh [--external]
#   --external   also check external (http/https) links
#
# Exit codes: 0 = no broken links, 1 = broken links found but unfixable
#             2 = fixable links were repaired

set -euo pipefail

FIX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_REPO_ROOT="$(cd "$FIX_DIR/../../.." && pwd)"
source "$FIX_DIR/lib/fix-common.sh"
SCRIPT_DIR="$FIX_DIR"
source "$SCRIPT_DIR/lib/common.sh"

CHECK_EXTERNAL=false
EXIT_CODE=0

for arg in "$@"; do
  case "$arg" in
    --external) CHECK_EXTERNAL=true ;;
  esac
done

fix_section "FIX: Documentation Link Check"

# ── Find all markdown files ─────────────────────────────────────────────────
MD_FILES=$(find "$FIX_REPO_ROOT" -name '*.md' ! -path '*/node_modules/*' ! -path '*/.git/*' 2>/dev/null | sort)
MD_COUNT=$(echo "$MD_FILES" | wc -l)
fix_sub "Scanning $MD_COUNT markdown files for links"

# ── Check internal links ────────────────────────────────────────────────────
fix_section "Internal Links"
BROKEN_INTERNAL=0
CHECKED_INTERNAL=0

while IFS= read -r file; do
  rel="${file#"$FIX_REPO_ROOT"/}"
  # Find markdown links: [text](path)
  while IFS= read -r link; do
    # Extract the link target from markdown [text](target) or [text](target#anchor)
    target=$(echo "$link" | grep -oP '\]\(([^)]+)\)' | sed 's/\]\((.*)\)/\1/' | head -1)
    [[ -z "$target" ]] && continue

    # Skip external links
    if echo "$target" | grep -qP '^https?://'; then
      ((CHECKED_INTERNAL++)) || true
      continue
    fi

    # Skip anchors-only links
    if echo "$target" | grep -qP '^#'; then
      # Check if the anchor exists in the file
      anchor=$(echo "$target" | sed 's/^#//')
      if ! grep -qi "^#\+ *$anchor" "$file" 2>/dev/null; then
        fix_warn "$rel: anchor not found '$target'"
        ((BROKEN_INTERNAL++)) || true
      fi
      continue
    fi

    # Relative link — resolve relative to the file's directory
    dir=$(dirname "$file")
    resolved="$dir/$target"
    # Remove anchor
    resolved="${resolved%%#*}"
    # Resolve ../
    resolved=$(cd "$dir" 2>/dev/null && realpath -m "$target" 2>/dev/null || echo "")

    if [[ -z "$resolved" || ! -f "$resolved" ]]; then
      # Try relative to repo root
      resolved="$FIX_REPO_ROOT/$target"
      resolved="${resolved%%#*}"
    fi

    if [[ ! -f "$resolved" ]]; then
      fix_warn "$rel: broken link '$target' (resolved: $resolved)"
      ((BROKEN_INTERNAL++)) || true
    fi
  done < <(grep -oP '\[[^\]]*\]\([^)]+\)' "$file" 2>/dev/null || true)
done <<< "$MD_FILES"

fix_info "Internal links checked: $CHECKED_INTERNAL"
fix_info "Broken internal links: $BROKEN_INTERNAL"

if [[ "$BROKEN_INTERNAL" -gt 0 ]]; then
  EXIT_CODE=1
fi

# ── Check external links ────────────────────────────────────────────────────
if $CHECK_EXTERNAL; then
  fix_section "External Links"
  BROKEN_EXTERNAL=${BROKEN_EXTERNAL:-0}
  CHECKED_EXTERNAL=0

  while IFS= read -r file; do
    rel="${file#"$FIX_REPO_ROOT"/}"
    while IFS= read -r url; do
      # Clean up URL
      url=$(echo "$url" | sed 's/)$//' | sed 's/#.*$//')
      [[ -z "$url" ]] && continue

      # Skip non-HTTP
      if ! echo "$url" | grep -qP '^https?://'; then
        continue
      fi

      ((CHECKED_EXTERNAL++)) || true

      # Check with curl (follow redirects, timeout 5s)
      if ! curl -sfL --max-time 5 "$url" >/dev/null 2>&1; then
        fix_warn "$rel: broken external link: $url"
        ((BROKEN_EXTERNAL++)) || true
      fi
    done < <(grep -oP '\[[^\]]*\]\(https?://[^)]+\)' "$file" 2>/dev/null || true)
  done <<< "$MD_FILES"

  fix_info "External links checked: $CHECKED_EXTERNAL"
  fix_info "Broken external links: $BROKEN_EXTERNAL"

  if [[ "$BROKEN_EXTERNAL" -gt 0 ]]; then
    EXIT_CODE=1
  fi
else
  fix_skip "External link check disabled (use --external to enable)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
fix_section "Documentation Links — Summary"
fix_info "  Broken internal: $BROKEN_INTERNAL"
if $CHECK_EXTERNAL; then
  fix_info "  Broken external: $BROKEN_EXTERNAL"
fi
fix_info "  Checked: $CHECKED_INTERNAL internal, ${CHECKED_EXTERNAL:-0} external"

if [[ "$BROKEN_INTERNAL" -eq 0 && "$BROKEN_EXTERNAL" -eq 0 ]]; then
  fix_ok "All documentation links are valid"
  exit 0
else
  fix_warn "Some links are broken — manual review required for external URLs"
  exit "$EXIT_CODE"
fi
