#!/usr/bin/env bash
# Run the same gates CI runs, locally.
#
# Usage: scripts/ci/run-local.sh
# Requires: bash, git, python3 (3.11+ for tomllib), luac, shellcheck,
#           PyYAML. actionlint is used when present.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

step() { printf '\n== %s ==\n' "$*"; }

step "ShellCheck"
if command -v shellcheck >/dev/null 2>&1; then
  scripts/ci/check_shell.sh
else
  printf 'shellcheck not installed; skipping locally (CI still runs it).\n'
fi

step "Python syntax"
mapfile -t py_files < <(git ls-files -z --cached --others --exclude-standard '*.py' | tr '\0' '\n')
while IFS= read -r -d '' f; do
  head -n1 -- "$f" 2>/dev/null | grep -q 'python' && py_files+=("$f")
done < <(git ls-files -z --cached --others --exclude-standard 'bin/*')
python3 -m py_compile "${py_files[@]}"

step "JSON / JSONC / TOML / systemd"
python3 scripts/ci/validate_configs.py

step "Lua syntax"
LUAC="$(command -v luac5.4 || command -v luac || true)"
if [ -n "$LUAC" ]; then
  while IFS= read -r -d '' f; do
    "$LUAC" -p "$f" || { echo "Lua parse failed: $f" >&2; exit 1; }
  done < <(git ls-files -z --cached --others --exclude-standard '*.lua')
  echo "Lua syntax OK"
else
  printf 'luac not installed; skipping locally (CI still runs it).\n'
fi

step "install.sh coverage"
python3 scripts/ci/check_install_pairs.py

step "YAML"
python3 - <<'PY'
import pathlib
import subprocess
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: python3 -m pip install --user pyyaml")

root = pathlib.Path.cwd()
files = subprocess.run(
    ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "*.yml", "*.yaml"],
    capture_output=True, check=True,
).stdout.decode().split("\0")
files = [f for f in files if f]
for name in files:
    try:
        yaml.safe_load((root / name).read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        sys.exit(f"{name}: invalid YAML: {exc}")
print(f"YAML OK ({len(files)} files)")
PY

step "Installer smoke test"
scripts/ci/smoke_install.sh

step "actionlint"
if command -v actionlint >/dev/null 2>&1; then
  actionlint -color
else
  printf 'actionlint not installed; skipping locally (CI still runs it).\n'
fi

printf '\nAll local CI gates passed.\n'
