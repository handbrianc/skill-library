#!/usr/bin/env bash
#
# check-doc-links.sh
# Checks markdown files for broken internal and external links.
# Does NOT follow redirects or check JS-rendered pages.
#
# Usage: ./check-doc-links.sh <doc_dir> [--external]
# Output: TSV of BROKEN_LINK entries
#
set -euo pipefail

TARGET="${1:-.}"
EXTERNAL="${2:-false}"

echo "=== DOC LINK CHECK ===" >&2
echo "Target dir: $TARGET" >&2
echo "Checking externals: $EXTERNAL" >&2
echo "" >&2

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# -------- Internal link checker --------
# Find all markdown links in markdown files
find "$TARGET" -type f \( -name "*.md" -o -name "*.mdx" -o -name "*.rst" \) \
  ! -path "*/node_modules/*" ! -path "*/.git/*" \
  > "$TMPDIR/doc_files.txt"

echo "Checking internal links..." >&2

# Extract relative links from markdown
# ![alt](path) and [text](url) patterns
grep -rhn --include="*.md" --include="*.mdx" -E '\[([^\]]+)\]\(([^)]+)\)' "$TARGET" 2>/dev/null \
  | while IFS=: read -r file linum match; do
    url=$(printf '%s' "$match" | sed -nE 's/.*\(([^)]+)\).*/\1/p')
    [[ "$url" =~ ^(https?|ftp|ssh|npm|tel|mailto|javascript|blob): ]] && continue
    # Strip anchors (#fragment) for file existence check
    BASE_URL="${url%%#*}"
    
    if [ -z "$BASE_URL" ]; then
      continue
    fi
    
    # Relative path — resolve from file's directory
    if [[ "$BASE_URL" != /* ]]; then
      ABS_PATH="$(dirname "$file")/$BASE_URL"
      ABS_PATH="$(realpath -m "$ABS_PATH" 2>/dev/null || echo "$ABS_PATH")"
    else
      ABS_PATH="$BASE_URL"
    fi
    
    if [ ! -e "$ABS_PATH" ]; then
      # Maybe it's an anchor within a file (file:#anchor)?
      BASEFILE="${ABS_PATH%%#*}"
      if [ -e "$BASEFILE" ]; then
        continue  # anchor within existing file — OK
      fi
      echo -e "BROKEN_INTERNAL\t$file:$linum\t$url" >&2
    fi
  done

# Check fragment-only links (#some-anchor at end of URLs)
# These point to headings within the SAME file, which is generally fine

# -------- External link checker (optional, slow) --------
if [ "$EXTERNAL" == "--external" ]; then
  echo "" >&2
  echo "Checking external links (this can be slow)..." >&2
  
  grep -rhn --include="*.md" --include="*.mdx" -E '\[([^\]]+)\]\((https?://[^)]+)\)' "$TARGET" 2>/dev/null \
    | head -50 | while IFS=: read -r file linum pattern url; do
    HTTP_CODE=$(curl -sIL --max-time 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" == "000" ] || [ "$HTTP_CODE" == "404" ] || [ "$HTTP_CODE" == "410" ]; then
      echo -e "BROKEN_EXTERNAL\t$file:$linum\t$url\tHTTP:$HTTP_CODE" >&2
    fi
  done
else
  echo "(Skipped external link check — use --external to enable)" >&2
fi

echo "" >&2
echo "=== LINK CHECK COMPLETE ===" >&2

exit 0