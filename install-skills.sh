#!/usr/bin/env bash
#
# install-skills.sh — Install skills from this repo into agent skill directories.
#
# Installs every skill under ./skills/ into the user's OpenCode directory
# (~/.config/opencode/skills/<skill-name>/) and, by default, into the personal
# GitHub Copilot skills directory (~/.copilot/skills/), which the Copilot
# extension in VS Code (plus Copilot CLI and the Copilot app) reads automatically.
# Supports symlinks (for development) or copy (for stable deployment).
#
# Usage:
#   ./install-skills.sh              # Interactive — prompts per existing skill
#   ./install-skills.sh --symlink    # Symlink instead of copy (dev mode)
#   ./install-skills.sh --force      # Overwrite existing without prompting
#   ./install-skills.sh --dry-run    # Show what would be done
#   ./install-skills.sh --list       # List installable skills and exit
#   ./install-skills.sh --skip       # Skip existing, only install new
#   ./install-skills.sh --no-copilot # Skip the ~/.copilot/skills destination
#   ./install-skills.sh --dest ~/some/dir
#                                    # Install ONLY to the given path
#                                    # (overrides both default destinations)
#

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SOURCE="$SCRIPT_DIR/skills"
DEFAULT_DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
COPILOT_DEST="$HOME/.copilot/skills"

# ── Help ────────────────────────────────────────────────────────────────────

usage() {
  sed -n '3,21p' "$0" | sed 's/^# \?//'
}

# ── Parse args ──────────────────────────────────────────────────────────────

MODE="copy"       # copy | symlink
FORCE=false
DRY_RUN=false
LIST_ONLY=false
SKIP_EXISTING=false
NO_COPILOT=false
CUSTOM_DEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)     usage; exit 0 ;;
    -s|--symlink)  MODE="symlink" ; shift ;;
    -f|--force)    FORCE=true ; shift ;;
    -d|--dry-run)  DRY_RUN=true ; shift ;;
    -l|--list)     LIST_ONLY=true ; shift ;;
    -S|--skip)     SKIP_EXISTING=true ; shift ;;
    -n|--no-copilot) NO_COPILOT=true ; shift ;;
    -D|--dest)
      shift
      CUSTOM_DEST="$(realpath -m "$1")"
      shift
      ;;
    *)  echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 1 ;;
  esac
done

# ── Destinations ─────────────────────────────────────────────────────────────

# An explicit --dest is the only target; otherwise install to the default
# OpenCode destination and (unless --no-copilot) the personal Copilot one.
if [[ -n "$CUSTOM_DEST" ]]; then
  DESTS=("$CUSTOM_DEST")
else
  DESTS=("$DEFAULT_DEST")
  $NO_COPILOT || DESTS+=("$COPILOT_DEST")
fi

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
  echo "Destinations:"
  for dest in "${DESTS[@]}"; do
    echo "  - $dest"
  done
  echo "Mode: $MODE"
  echo
  for name in "${SKILLS[@]}"; do
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
  for dest in "${DESTS[@]}"; do
    mkdir -p "$dest"
    if [[ ! -w "$dest" ]]; then
      echo "Error: Destination $dest is not writable." >&2
      exit 1
    fi
  done
fi

# ── Install ──────────────────────────────────────────────────────────────────

install_into() {
  local dest="$1"
  local name src dst reply
  local installed=0
  local skipped=0
  local failed=0

  for name in "${SKILLS[@]}"; do
    src="$SKILLS_SOURCE/$name"
    dst="$dest/$name"

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
        echo -n "           Overwrite at $dest? [y/N] "
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

  # ── Summary (per destination) ────────────────────────────────────────────

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Destination:    $dest"
  echo "  Mode:           $MODE"
  echo "  Installed:      $installed"
  echo "  Skipped:        $skipped"
  echo "  Failed:         $failed"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
}

for dest in "${DESTS[@]}"; do
  install_into "$dest"
done

if $DRY_RUN; then
  echo "Dry-run complete. Run without --dry-run to actually install."
  exit 0
fi

# ── Final hints ─────────────────────────────────────────────────────────────

if [[ "$MODE" == "symlink" ]]; then
  echo "⚠  Symlinked — if you remove or move this repo, the skills will break."
fi

echo "Skills installed. Read automatically from:"
for dest in "${DESTS[@]}"; do
  if [[ "$dest" == "$COPILOT_DEST" ]]; then
    echo "  $dest  (GitHub Copilot personal skills — VS Code extension, CLI, app)"
  else
    echo "  $dest"
  fi
done

if [[ -z "$CUSTOM_DEST" ]] && ! $NO_COPILOT; then
  echo
  echo "OpenCode reads skills from:"
  echo "  1. $DEFAULT_DEST (user-installed, highest priority)"
  echo "  2. \$PWD/skills/ (project-local)"
fi
echo

echo "To verify:"
for dest in "${DESTS[@]}"; do
  echo "  ls -la \"$dest\""
done
