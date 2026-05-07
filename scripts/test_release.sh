#!/usr/bin/env bash
# Local simulation of the release-please bump + CHANGELOG generation.
# Does not push, tag, or call gh; prints what the next release would look like.
set -euo pipefail

cd "$(dirname "$0")/.."

current=$(cat version.txt)
prev_tag=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)

# Walk commits since the last tag. Bump rules:
#   feat!: / fix!: / BREAKING CHANGE: -> major
#   feat:                              -> minor
#   fix: / perf:                       -> patch
#   anything else                      -> no bump
bump="none"
while IFS= read -r line; do
  case "$line" in
    *"BREAKING CHANGE"*|*"!:"*)         bump="major" ;;
    feat:*|feat\(*\):*)                 [ "$bump" != "major" ] && bump="minor" ;;
    fix:*|fix\(*\):*|perf:*|perf\(*\):*) [ "$bump" = "none" ] && bump="patch" ;;
  esac
done < <(git log "${prev_tag}..HEAD" --pretty=format:"%s" --no-merges)

IFS='.' read -r major minor patch <<< "$current"
case "$bump" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="${major}.$((minor + 1)).0" ;;
  patch) next="${major}.${minor}.$((patch + 1))" ;;
  none)  next="(no release — no feat/fix/perf commits since ${prev_tag})" ;;
esac

echo "current:   ${current}"
echo "previous:  ${prev_tag}"
echo "bump kind: ${bump}"
echo "next:      ${next}"
echo
echo "--- changelog preview ---"
git log "${prev_tag}..HEAD" --pretty=format:"- %s" --no-merges || true
echo
