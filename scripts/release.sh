#!/usr/bin/env bash
# Compute next semver from conventional commits since the last v* tag,
# update version.txt, and prepend a categorised entry to CHANGELOG.md.
# Pure file mutation — does not git add, commit, tag, or push.
#
# Usage:
#   scripts/release.sh [--dry-run] [--bump auto|patch|minor|major]
#
# Outputs (for CI consumption):
#   prints NEXT_VERSION=x.y.z on stdout
#   prints BUMP_KIND=major|minor|patch|none on stdout
#   exits 1 if no releasable commits found (and bump=auto)

set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
BUMP_MODE="auto"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --bump) BUMP_MODE="${2:?--bump requires a value}"; shift ;;
    --bump=*) BUMP_MODE="${1#--bump=}" ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$BUMP_MODE" in
  auto|patch|minor|major) ;;
  *) echo "invalid --bump: $BUMP_MODE (expected auto|patch|minor|major)" >&2; exit 2 ;;
esac

current=$(cat version.txt)
prev_tag=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || git rev-list --max-parents=0 HEAD)

if [ "$BUMP_MODE" = "auto" ]; then
  bump="none"
  while IFS= read -r line; do
    case "$line" in
      *"BREAKING CHANGE"*|*"!:"*)               bump="major" ;;
      feat:*|feat\(*\):*)                       [ "$bump" != "major" ] && bump="minor" ;;
      fix:*|fix\(*\):*|perf:*|perf\(*\):*)      [ "$bump" = "none" ] && bump="patch" ;;
    esac
  done < <(git log "${prev_tag}..HEAD" --pretty=tformat:"%s" --no-merges)
else
  bump="$BUMP_MODE"
fi

if [ "$bump" = "none" ]; then
  echo "BUMP_KIND=none"
  echo "no feat/fix/perf commits since ${prev_tag}; nothing to release" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<< "$current"
case "$bump" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="${major}.$((minor + 1)).0" ;;
  patch) next="${major}.${minor}.$((patch + 1))" ;;
esac

repo_url=$(git config --get remote.origin.url | sed -E 's|\.git$||; s|^git@github.com:|https://github.com/|')
today=$(date -u +%Y-%m-%d)

section() {
  local title="$1"; shift
  local pattern="$1"
  local lines
  lines=$(git log "${prev_tag}..HEAD" --no-merges --pretty=format:"%h%x09%s" \
    | awk -F'\t' -v p="$pattern" '$2 ~ p { sub(/^[a-z]+(\([^)]*\))?!?:[[:space:]]*/, "", $2); print $1 "\t" $2 }')
  [ -z "$lines" ] && return
  printf '\n### %s\n\n' "$title"
  while IFS=$'\t' read -r sha msg; do
    printf '* %s ([%s](%s/commit/%s))\n' "$msg" "$sha" "$repo_url" "$sha"
  done <<< "$lines"
}

entry=$(
  printf '## [%s](%s/compare/v%s...v%s) (%s)\n' "$next" "$repo_url" "$current" "$next" "$today"
  section "Features" '^feat[(!:]'
  section "Bug Fixes" '^fix[(!:]'
  section "Performance" '^perf[(!:]'
  section "Reverts" '^revert[(!:]'
  section "Code Refactoring" '^refactor[(!:]'
  section "Tests" '^test[(!:]'
  section "Build System" '^build[(!:]'
  section "Continuous Integration" '^ci[(!:]'
  section "Documentation" '^docs[(!:]'
)

echo "BUMP_KIND=${bump}"
echo "NEXT_VERSION=${next}"

if [ "$DRY_RUN" = "1" ]; then
  echo "--- dry run: changelog entry ---" >&2
  printf '%s\n' "$entry" >&2
  exit 0
fi

printf '%s\n' "$next" > version.txt

tmp=$(mktemp)
{
  head -n 1 CHANGELOG.md
  echo
  printf '%s\n' "$entry"
  tail -n +2 CHANGELOG.md
} > "$tmp"
mv "$tmp" CHANGELOG.md

# Emit changelog body (without leading "## [..](...)" heading) for downstream GH-release notes.
notes_path="${RELEASE_NOTES_PATH:-$(mktemp)}"
printf '%s\n' "$entry" | tail -n +2 > "$notes_path"
echo "RELEASE_NOTES_PATH=${notes_path}"
