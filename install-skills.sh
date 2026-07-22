#!/usr/bin/env bash
#
# install-skills.sh — Install skills from this repo to the user's OpenCode directory.
#
# Installs every skill under ./skills/ into ~/.config/opencode/skills/<skill-name>/.
# Supports symlinks (for development) or copy (for stable deployment).
#
# Usage:
#   ./install-skills.sh              # Interactive — prompts per existing skill
#   ./install-skills.sh --symlink    # Symlink instead of copy (dev mode)
#   ./install-skills.sh --force      # Overwrite existing without prompting
#   ./install-skills.sh --dry-run    # Show what would be done
#   ./install-skills.sh --list       # List installable skills and exit
#   ./install-skills.sh --skip       # Skip existing, only install new
#   ./install-skills.sh --dest ~/.config/opencode/skills
#

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SOURCE="$SCRIPT_DIR/skills"
DEFAULT_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"

# ── Help ────────────────────────────────────────────────────────────────────

usage() {
  sed -n '3,20p' "$0" | sed 's/^# \?//'
  exit 0
}

# ── Parse args ──────────────────────────────────────────────────────────────

MODE="copy"       # copy | symlink
FORCE=false
DRY_RUN=false
LIST_ONLY=false
SKIP_EXISTING=false
DEST="$DEFAULT_DEST"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     usage ;;
    -s|--symlink)  MODE="symlink" ; shift ;;
    -f|--force)    FORCE=true ; shift ;;
    -d|--dry-run)  DRY_RUN=true ; shift ;;
    -l|--list)     LIST_ONLY=true ; shift ;;
    -S|--skip)     SKIP_EXISTING=true ; shift ;;
    -D|--dest)
      shift
      DEST="$(realpath -m "$1")"
      shift
      ;;
    *)  echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 1 ;;
  esac
done

# ── Discover skills ─────────────────────────────────────────────────────────

if [[ ! -d "$SKILLS_SOURCE" ]]; then
  echo "Error: No skills/ directory found at $SKILLS_SOURCE" >&2
  exit 1
fi

SKILLS=()
for dir in "$SKILLS_SOURCE"/*/; do
  name="$(basename "$dir")"
  if [[ -f "$dir/SKILL.md" ]]; then
    SKILLS+=("$name")
  fi
done

if [[ ${#SKILLS[@]} -eq 0 ]]; then
  echo "No skills found (no directories with SKILL.md under $SKILLS_SOURCE)." >&2
  exit 1
fi

# ── List mode ────────────────────────────────────────────────────────────────

if $LIST_ONLY; then
  echo "Installable skills (source: $SKILLS_SOURCE)"
  echo "Destination: $DEST"
  echo "Mode: $MODE"
  echo
  for name in "${SKILLS[@]}"; do
    extra=""
    has_scripts=
    if [[ -d "$SKILLS_SOURCE/$name/scripts" ]]; then
      has_scripts=" ($(find "$SKILLS_SOURCE/$name/scripts" -type f | wc -l) scripts)"
    fi
    printf "  %-20s %s\n" "$name" "$has_scripts"
  done
  exit 0
fi

# ── Pre-flight checks ───────────────────────────────────────────────────────

if ! $DRY_RUN; then
  mkdir -p "$DEST"
  if [[ ! -w "$DEST" ]]; then
    echo "Error: Destination $DEST is not writable." >&2
    exit 1
  fi
fi

# ── Install ──────────────────────────────────────────────────────────────────

installed=0
skipped=0
failed=0

for name in "${SKILLS[@]}"; do
  src="$SKILLS_SOURCE/$name"
  dst="$DEST/$name"

  # ── Check if destination exists ─────────────────────────────────
  if [[ -e "$dst" || -L "$dst" ]]; then
    if $DRY_RUN; then
      echo "  [dry-run] $name  ->  $dst  (would replace existing, mode: $MODE)"
      ((installed++)) || true
      continue
    fi
    if $SKIP_EXISTING; then
      echo "  [skip]   $name  (already exists at $dst)"
      ((skipped++)) || true
      continue
    fi
    if ! $FORCE; then
      echo "  [exist]  $name  already installed at $dst"
      echo "           Use --force to overwrite, --skip to skip existing,"
      echo "           or remove it manually: rm -rf \"$dst\""
      echo -n "           Overwrite? [y/N] "
      read -r reply < /dev/tty 2>/dev/null || true
      case "${reply:-n}" in
        y|Y|yes|YES) ;;
        *) echo "           Skipping $name." ; ((skipped++)) || true ; continue ;;
      esac
    fi
    # Remove existing (handle both symlink and directory)
    rm -rf "$dst"
  fi

  # ── Install ────────────────────────────────────────────────────
  if $DRY_RUN; then
    echo "  [dry-run] $name  ->  $dst  (mode: $MODE)"
    ((installed++)) || true
    continue
  fi

  if [[ "$MODE" == "symlink" ]]; then
    # Resolve full path to the source so the symlink is absolute
    ln -sf "$src" "$dst"
    echo "  [link]   $name  ->  $dst"
  else
    cp -a "$src" "$dst"
    echo "  [copy]   $name  ->  $dst"
  fi
  ((installed++)) || true

  # ── Post-install sanity ─────────────────────────────────────────
  if [[ ! -f "$dst/SKILL.md" ]]; then
    echo "  Warning: SKILL.md not found at $dst/SKILL.md — skill may be incomplete." >&2
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Skills source:  $SKILLS_SOURCE"
echo "  Destination:    $DEST"
echo "  Mode:           $MODE"
echo "  Installed:      $installed"
echo "  Skipped:        $skipped"
echo "  Failed:         $failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

if $DRY_RUN; then
  echo "Dry-run complete. Run without --dry-run to actually install."
  exit 0
fi

# ── Final hints ─────────────────────────────────────────────────────────────

if [[ "$MODE" == "symlink" ]]; then
  echo "⚠  Symlinked — if you remove or move this repo, the skills will break."
fi

echo "Skills installed. OpenCode reads skills from:"
echo "  1. $DEST (user-installed, highest priority)"
echo "  2. \$PWD/skills/ (project-local)"
echo
echo "To verify: look for these skills in ~/.config/opencode/skills/:"
for name in "${SKILLS[@]}"; do
  echo "  ls -la \"$DEST/$name\""
done
