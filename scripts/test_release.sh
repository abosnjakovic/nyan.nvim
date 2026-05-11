#!/usr/bin/env bash
# Dry run of the release script: prints next version and changelog preview
# without writing version.txt or CHANGELOG.md.
set -euo pipefail

cd "$(dirname "$0")/.."
exec ./scripts/release.sh --dry-run "$@"
