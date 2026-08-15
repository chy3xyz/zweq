#!/usr/bin/env bash

# Read-only heuristic audit for common UTS, UVUE, and UCSS compiler risks.
set -u

ROOT="${1:-.}"
PROFILE="${2:-official}"

if [[ ! -e "$ROOT" ]]; then
  printf 'uniapp-x audit: target not found: %s\n' "$ROOT" >&2
  exit 2
fi

if [[ "$PROFILE" != "official" && "$PROFILE" != "conservative-app" ]]; then
  printf 'uniapp-x audit: profile must be official or conservative-app\n' >&2
  exit 2
fi

if ! command -v rg >/dev/null 2>&1; then
  printf 'uniapp-x audit: rg is required but was not found\n' >&2
  exit 2
fi

found=0

warn() {
  local title="$1"
  local pattern="$2"
  shift 2
  local output
  output="$(rg -n --color never "$pattern" "$@" \
    --glob '!unpackage/**' --glob '!node_modules/**' "$ROOT" 2>/dev/null || true)"
  if [[ -n "$output" ]]; then
    found=1
    printf '\n[WARN] %s\n%s\n' "$title" "$output"
  fi
}

printf 'uniapp-x static audit: %s (profile: %s)\n' "$ROOT" "$PROFILE"
printf 'Findings are review warnings, not compiler results.\n'

warn 'UTS does not support undefined; review real code matches' \
  '(^|[^A-Za-z0-9_])undefined([^A-Za-z0-9_]|$)' \
  --glob '*.uts' --glob '*.uvue'

warn 'Function call inside inline style object can trigger UVUE inference errors' \
  ':style[[:space:]]*=[[:space:]]*"[[:space:]]*\{[^"\n]*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\(' \
  --glob '*.uvue'

if [[ "$PROFILE" == "conservative-app" ]]; then
  warn 'Conservative App review: verify font weight 800/900 compatibility' \
    'font-weight[[:space:]]*:[[:space:]]*(800|900)([^0-9]|$)' \
    --glob '*.uvue' --glob '*.css' --glob '*.scss'

  warn 'Conservative App review: verify browser text wrapping properties' \
    '(^|[[:space:];{])(word-break|overflow-wrap)[[:space:]]*:' \
    --glob '*.uvue' --glob '*.css' --glob '*.scss'

  warn 'Conservative App review: verify grid layout compatibility' \
    'display[[:space:]]*:[[:space:]]*grid([^A-Za-z-]|$)' \
    --glob '*.uvue' --glob '*.css' --glob '*.scss'

  warn 'Conservative App review: verify gap property compatibility' \
    '(^|[[:space:];{])(row-gap|column-gap|gap)[[:space:]]*:' \
    --glob '*.uvue' --glob '*.css' --glob '*.scss'
fi

if [[ "$found" -eq 0 ]]; then
  printf '\nNo known static risks found. This does not replace compilation.\n'
else
  printf '\nReview warnings above, then run the real uni-app x compiler.\n'
fi

exit 0
