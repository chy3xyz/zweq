#!/usr/bin/env bash

# List likely references to API/model fields before and after a schema change.
set -u

TARGET="${1:-}"
shift || true

if [[ -z "$TARGET" || ! -e "$TARGET" ]]; then
  printf 'field reference audit: target not found: %s\n' "$TARGET" >&2
  exit 2
fi

if [[ "$#" -eq 0 ]]; then
  printf 'usage: field-reference-audit.sh <file-or-directory> <field> [field...]\n' >&2
  exit 2
fi

if ! command -v rg >/dev/null 2>&1; then
  printf 'field reference audit: rg is required but was not found\n' >&2
  exit 2
fi

for field in "$@"; do
  if [[ ! "$field" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    printf 'field reference audit: invalid field name: %s\n' "$field" >&2
    exit 2
  fi

  printf '\nField: %s\n' "$field"
  pattern="(\\?\\.|\\.)${field}\\b|get(Any|String|Number|Boolean|JSON|Array)\\([[:space:]]*['\"]${field}['\"]|(^|[^A-Za-z0-9_])${field}[[:space:]]*:"
  output="$(rg -n --pcre2 --color never "$pattern" \
    --glob '*.uts' --glob '*.uvue' --glob '*.ts' --glob '*.vue' \
    --glob '!unpackage/**' --glob '!node_modules/**' "$TARGET" 2>/dev/null || true)"

  if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
  else
    printf 'No likely references found.\n'
  fi
done

printf '\nReview every match in its declared type context; generic field names may belong to unrelated models.\n'
exit 0
