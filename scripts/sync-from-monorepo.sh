#!/usr/bin/env bash
#
# sync-from-monorepo.sh
#
# Copies OpenBat agent skills from the upstream openbat monorepo into
# this distribution repo (.claude/skills/<name>/SKILL.md).
#
# Why this exists: the canonical skill files live next to the product
# code in openbat/.claude/skills/, so authors edit them in context (with
# the actual CLI/MCP/SDK source one directory away). This repo is the
# distribution surface — skills.sh + npx skills add only see this one.
# The script keeps them in lockstep without copy-paste mistakes.
#
# Usage:
#   ./scripts/sync-from-monorepo.sh                # interactive (asks before committing)
#   ./scripts/sync-from-monorepo.sh --dry-run      # print diff, change nothing
#   ./scripts/sync-from-monorepo.sh --commit       # auto-commit "Sync skills from monorepo"
#   ./scripts/sync-from-monorepo.sh --monorepo=PATH  # override monorepo path
#
# Defaults the monorepo location to a sibling directory: ../openbat
# (i.e. you have ~/code/openbat and ~/code/openbat-agent-skills checked
# out side by side). Override with --monorepo=/abs/path or the
# OPENBAT_MONOREPO env var.

set -euo pipefail

# ─── Args ───────────────────────────────────────────────────────────

DRY_RUN=0
AUTO_COMMIT=0
MONOREPO="${OPENBAT_MONOREPO:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --commit)  AUTO_COMMIT=1 ;;
    --monorepo=*) MONOREPO="${arg#--monorepo=}" ;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Try: $0 --help" >&2
      exit 2
      ;;
  esac
done

# ─── Locate the repos ────────────────────────────────────────────────

# This script lives at <repo>/scripts/sync-from-monorepo.sh — the repo
# root is one level up.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [ -z "$MONOREPO" ]; then
  MONOREPO="$(cd .. && pwd)/openbat"
fi

if [ ! -d "$MONOREPO/.claude/skills" ]; then
  echo "✗ Could not find monorepo skills at: $MONOREPO/.claude/skills" >&2
  echo "  Pass --monorepo=/abs/path or set OPENBAT_MONOREPO env var." >&2
  exit 1
fi

echo "→ Repo:     $REPO_ROOT"
echo "→ Monorepo: $MONOREPO"
echo

# ─── Discover which skills to sync ──────────────────────────────────
#
# Convention: every directory under <monorepo>/.claude/skills/ whose
# name starts with `openbat-` or equals `using-openbat` is one of ours.
# Adding a new skill upstream means it auto-syncs on next run — no
# manifest to maintain.

shopt -s nullglob
UPSTREAM=()
for dir in "$MONOREPO/.claude/skills"/openbat-* "$MONOREPO/.claude/skills/using-openbat"; do
  [ -d "$dir" ] && UPSTREAM+=("$(basename "$dir")")
done
shopt -u nullglob

if [ "${#UPSTREAM[@]}" -eq 0 ]; then
  echo "✗ No matching skills found under $MONOREPO/.claude/skills" >&2
  exit 1
fi

echo "Skills to sync (${#UPSTREAM[@]}):"
printf '  • %s\n' "${UPSTREAM[@]}"
echo

# ─── Validate each upstream skill before touching anything ──────────
#
# Two checks:
#   1. Frontmatter has `name:` and `description:`.
#   2. Body contains no real-looking API keys (sentinel-only allowed).

KEY_REGEX='ob_(live|read|pat|admin)_[a-f0-9]{32}'

for s in "${UPSTREAM[@]}"; do
  f="$MONOREPO/.claude/skills/$s/SKILL.md"
  if [ ! -f "$f" ]; then
    echo "✗ Missing SKILL.md for: $s ($f)" >&2
    exit 1
  fi
  # Extract frontmatter (lines between first two --- markers).
  fm="$(awk '/^---$/{c++; if(c==2) exit} c==1' "$f")"
  if ! echo "$fm" | grep -qE '^name:[[:space:]]+'; then
    echo "✗ $s/SKILL.md: missing 'name' in frontmatter" >&2
    exit 1
  fi
  if ! echo "$fm" | grep -qE '^description:'; then
    echo "✗ $s/SKILL.md: missing 'description' in frontmatter" >&2
    exit 1
  fi
  if grep -qE "$KEY_REGEX" "$f"; then
    echo "✗ $s/SKILL.md contains a real-looking API key — replace with sentinel (e.g. ob_pat_EXAMPLE0…)" >&2
    grep -nE "$KEY_REGEX" "$f" >&2 | head -3
    exit 1
  fi
done
echo "✓ All ${#UPSTREAM[@]} upstream skills pass validation"
echo

# ─── Plan the change set ─────────────────────────────────────────────
#
# Compare upstream files to local ones; list adds, modifies, removes.

ADDED=()
MODIFIED=()
UNCHANGED=()
REMOVED=()

mkdir -p .claude/skills

for s in "${UPSTREAM[@]}"; do
  src="$MONOREPO/.claude/skills/$s/SKILL.md"
  dst=".claude/skills/$s/SKILL.md"
  if [ ! -f "$dst" ]; then
    ADDED+=("$s")
  elif ! cmp -s "$src" "$dst"; then
    MODIFIED+=("$s")
  else
    UNCHANGED+=("$s")
  fi
done

# Detect skills present locally but not upstream.
for dir in .claude/skills/*; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  in_upstream=0
  for u in "${UPSTREAM[@]}"; do
    [ "$u" = "$name" ] && in_upstream=1 && break
  done
  [ "$in_upstream" -eq 0 ] && REMOVED+=("$name")
done

[ "${#ADDED[@]}"     -gt 0 ] && { echo "+ Added (${#ADDED[@]})";     printf '    %s\n' "${ADDED[@]}";     echo; }
[ "${#MODIFIED[@]}"  -gt 0 ] && { echo "~ Modified (${#MODIFIED[@]})"; printf '    %s\n' "${MODIFIED[@]}";  echo; }
[ "${#REMOVED[@]}"   -gt 0 ] && { echo "- Removed (${#REMOVED[@]})";   printf '    %s\n' "${REMOVED[@]}";   echo; }
[ "${#UNCHANGED[@]}" -gt 0 ] && { echo "= Unchanged (${#UNCHANGED[@]})"; printf '    %s\n' "${UNCHANGED[@]}"; echo; }

if [ "${#ADDED[@]}" -eq 0 ] && [ "${#MODIFIED[@]}" -eq 0 ] && [ "${#REMOVED[@]}" -eq 0 ]; then
  echo "Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "(dry run — no files written)"
  exit 0
fi

# ─── Apply ───────────────────────────────────────────────────────────

for s in "${ADDED[@]}" "${MODIFIED[@]}"; do
  src="$MONOREPO/.claude/skills/$s"
  dst=".claude/skills/$s"
  mkdir -p "$dst"
  # Copy SKILL.md only — ignore any local artifacts (test files, fixtures).
  cp "$src/SKILL.md" "$dst/SKILL.md"
done

for s in "${REMOVED[@]}"; do
  rm -rf ".claude/skills/$s"
done

echo "✓ Sync complete."
echo

# ─── Stage + commit ──────────────────────────────────────────────────

git add .claude/skills

if [ "$AUTO_COMMIT" -eq 1 ]; then
  commit_lines=()
  [ "${#ADDED[@]}"    -gt 0 ] && commit_lines+=("Added: ${ADDED[*]}")
  [ "${#MODIFIED[@]}" -gt 0 ] && commit_lines+=("Modified: ${MODIFIED[*]}")
  [ "${#REMOVED[@]}"  -gt 0 ] && commit_lines+=("Removed: ${REMOVED[*]}")
  msg="Sync skills from monorepo"
  for line in "${commit_lines[@]}"; do
    msg="$msg"$'\n'"  - $line"
  done
  git commit -m "$msg"
  echo "✓ Committed. Don't forget to tag + push:"
  echo "    git tag vX.Y.Z && git push && git push --tags"
else
  echo "Changes staged. Review with: git diff --cached"
  echo "Commit with:                git commit -m 'Sync skills from monorepo'"
  echo "Or rerun with --commit to auto-commit."
fi
