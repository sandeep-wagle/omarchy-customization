#!/usr/bin/env bash
# ShellCheck every shell script the repo ships.
#
# Gate is --severity=warning: style/info findings are reported locally by
# editors but do not block a merge.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found. Install it first (e.g. pacman -S shellcheck)." >&2
  exit 1
fi

mapfile -t files < <(
  git ls-files -z --cached --others --exclude-standard |
    xargs -0 -r grep -lIm1 -E '^#!.*(bash|/sh)' -- 2>/dev/null || true
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No shell scripts found; nothing to check."
  exit 0
fi

printf 'ShellCheck: %d scripts\n' "${#files[@]}"
shellcheck -x --severity=warning --format=gcc "${files[@]}"
