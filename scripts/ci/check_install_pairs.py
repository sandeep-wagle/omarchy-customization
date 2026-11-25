#!/usr/bin/env python3
"""Keep install.sh's PAIRS list honest.

The installer is the only way a file reaches the live system, so a file that
is shipped in the repo but absent from PAIRS is silently never installed.
This check fails when:

  * a PAIRS source file does not exist,
  * a destination is not under $HOME,
  * the same repo path or destination appears twice,
  * a file under a shipped directory has no PAIRS entry,
  * an executable script lost its +x bit.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
INSTALL = ROOT / "install.sh"

# Directories whose contents are meant to be installed. Top-level `branding/`,
# `defaults/`, `extensions/`, `hooks/`, `plugins/` and `themes/` are legacy
# duplicates of their `omarchy/` counterparts and are intentionally not
# installed; they are not listed here.
SHIPPED_DIRS = {
    "bin",
    "hypr",
    "terminals",
    "dotfiles",
    "omarchy",
    "systemd",
    "wireplumber",
    "voxtype",
    "mogtab",
    "emulator",
    "src",
    "toggles",
    "ghostty",
}

ALLOWLIST = {
    "hypr/README.md",  # contributor documentation, not a live config
}


def tracked_files() -> list[str]:
    try:
        out = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd=ROOT,
            capture_output=True,
            check=True,
        ).stdout
        return [p for p in out.decode().split("\0") if p]
    except (OSError, subprocess.CalledProcessError):
        return [
            str(p.relative_to(ROOT))
            for p in ROOT.rglob("*")
            if p.is_file() and ".git" not in p.relative_to(ROOT).parts
        ]


def parse_pairs() -> list[tuple[str, str, str]]:
    text = INSTALL.read_text(encoding="utf-8")
    pattern = re.compile(r'^\s*"([^"|]+)\|([^"|]+)\|([^"]+)"', re.MULTILINE)
    return pattern.findall(text)


def main() -> int:
    failures: list[str] = []
    pairs = parse_pairs()

    if not pairs:
        print("No PAIRS entries found in install.sh", file=sys.stderr)
        return 1

    seen_src: set[str] = set()
    seen_dest: set[str] = set()

    for rel, dest, _feature in pairs:
        src = ROOT / rel

        if not src.is_file():
            failures.append(f"PAIRS source missing: {rel}")

        if not re.match(r"^\$\{HOME\}/|^\$HOME/", dest):
            failures.append(f"destination is not under $HOME: {rel} -> {dest}")

        if rel in seen_src:
            failures.append(f"duplicate PAIRS source: {rel}")
        if dest in seen_dest:
            failures.append(f"duplicate PAIRS destination: {dest}")
        seen_src.add(rel)
        seen_dest.add(dest)

    for rel in tracked_files():
        parts = pathlib.PurePosixPath(rel).parts
        if not parts or parts[0] not in SHIPPED_DIRS:
            continue
        if rel in ALLOWLIST:
            continue
        if rel not in seen_src:
            failures.append(f"shipped file has no PAIRS entry: {rel}")

    for rel in sorted(seen_src):
        path = ROOT / rel
        if not path.is_file():
            continue
        first = path.read_bytes().split(b"\n", 1)[0]
        # `.sample` hooks are documentation examples, deliberately not
        # executable so omarchy-update does not run them.
        if (
            first.startswith(b"#!")
            and not path.name.endswith(".sample")
            and not (path.stat().st_mode & 0o111)
        ):
            failures.append(f"script is not executable: {rel}")

    if not (INSTALL.stat().st_mode & 0o111):
        failures.append("install.sh is not executable")

    if failures:
        print("install.sh PAIRS check failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"install.sh PAIRS check passed ({len(pairs)} entries).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
