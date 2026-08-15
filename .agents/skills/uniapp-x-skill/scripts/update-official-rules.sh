#!/usr/bin/env bash

# Refresh the bundled DCloud AI Rules snapshot without modifying local extensions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$SKILL_DIR/references/dcloud-official"
TMP_DIR="$(mktemp -d)"
REPO_DIR="$TMP_DIR/uni-app-x-ai-rules"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

git clone --depth 1 https://gitcode.com/dcloud/uni-app-x-ai-rules.git "$REPO_DIR"
install -d "$TARGET_DIR"

cp "$REPO_DIR"/.agent/rules/*.md "$TARGET_DIR"/
cp "$REPO_DIR/LICENSE" "$TARGET_DIR/LICENSE"

revision="$(git -C "$REPO_DIR" rev-parse HEAD)"
revision_date="$(git -C "$REPO_DIR" log -1 --format=%ad --date=iso-strict)"
imported_date="$(date +%Y-%m-%d)"

{
  printf '# Source and License\n\n'
  printf 'The files in this directory were copied without modification from:\n\n'
  printf -- '- Project: DCloud `uni-app-x-ai-rules`\n'
  printf -- '- Repository: https://gitcode.com/dcloud/uni-app-x-ai-rules\n'
  printf -- '- Revision: `%s`\n' "$revision"
  printf -- '- Revision date: `%s`\n' "$revision_date"
  printf -- '- Imported on: `%s`\n' "$imported_date"
  printf -- '- Source paths: `.agent/rules/*.md` and `LICENSE`\n\n'
  printf 'The upstream work is distributed under the Apache License 2.0. See `LICENSE` in this directory. Local additions and compiler playbooks live outside this directory so the official snapshot remains identifiable and updateable.\n'
} > "$TARGET_DIR/SOURCE.md"

printf 'Updated DCloud rules to %s (%s)\n' "$revision" "$revision_date"
printf 'Review the diff before publishing.\n'
