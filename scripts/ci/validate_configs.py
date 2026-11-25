#!/usr/bin/env python3
"""Validate the config formats this repo ships.

Checks JSON, JSONC, TOML and systemd units. Exits non-zero with a list of
every failure so a CI run points at all problems at once, not just the first.

Run from anywhere: paths are resolved relative to the repo root.
"""

from __future__ import annotations

import configparser
import json
import pathlib
import re
import subprocess
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parents[2]
failures: list[str] = []


def tracked_files() -> list[pathlib.Path]:
    """Tracked files when inside git, otherwise every non-.git file."""
    try:
        out = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd=ROOT,
            capture_output=True,
            check=True,
        ).stdout
        names = [p for p in out.decode().split("\0") if p]
        return [ROOT / p for p in names]
    except (OSError, subprocess.CalledProcessError):
        return [
            p
            for p in ROOT.rglob("*")
            if p.is_file() and ".git" not in p.relative_to(ROOT).parts
        ]


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments and trailing commas, string-aware."""
    out: list[str] = []
    i = 0
    n = len(text)
    in_string = False

    while i < n:
        ch = text[i]

        if in_string:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue

        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue

        if text.startswith("//", i):
            newline = text.find("\n", i)
            i = n if newline == -1 else newline
            continue

        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue

        if ch == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                i += 1  # drop the trailing comma
                continue

        out.append(ch)
        i += 1

    return "".join(out)


def check_json(path: pathlib.Path, jsonc: bool) -> None:
    raw = path.read_text(encoding="utf-8")
    try:
        json.loads(strip_jsonc(raw) if jsonc else raw)
    except json.JSONDecodeError as exc:
        failures.append(f"{path.relative_to(ROOT)}: invalid JSON: {exc}")


def check_toml(path: pathlib.Path) -> None:
    try:
        tomllib.loads(path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as exc:
        failures.append(f"{path.relative_to(ROOT)}: invalid TOML: {exc}")


def check_systemd(path: pathlib.Path) -> None:
    rel = path.relative_to(ROOT)
    parser = configparser.ConfigParser(strict=False, interpolation=None)
    parser.optionxform = str  # keys are case-sensitive in unit files
    try:
        parser.read_string(path.read_text(encoding="utf-8"), source=str(rel))
    except configparser.Error as exc:
        failures.append(f"{rel}: invalid systemd unit: {exc}")
        return

    suffix = path.suffix
    sections = {s.lower() for s in parser.sections()}

    if suffix == ".service":
        if "service" not in sections:
            failures.append(f"{rel}: .service has no [Service] section")
        elif not any(
            key in parser["Service"]
            for key in ("ExecStart", "ExecStartPre", "ExecStartPost")
        ):
            failures.append(f"{rel}: .service has no ExecStart* command")
    elif suffix == ".timer":
        if "timer" not in sections:
            failures.append(f"{rel}: .timer has no [Timer] section")
        elif not any(
            key in parser["Timer"]
            for key in (
                "OnCalendar",
                "OnActiveSec",
                "OnBootSec",
                "OnStartupSec",
                "OnUnitActiveSec",
                "OnUnitInactiveSec",
            )
        ):
            failures.append(f"{rel}: .timer has no schedule trigger")
    elif not sections:
        failures.append(f"{rel}: unit drop-in has no section")


def main() -> int:
    files = tracked_files()

    for path in files:
        name = path.name
        suffix = path.suffix.lower()
        if suffix == ".json":
            check_json(path, jsonc=False)
        elif suffix == ".jsonc":
            check_json(path, jsonc=True)
        elif suffix == ".toml":
            check_toml(path)
        elif suffix == ".conf" and path.relative_to(ROOT).parts[0] == "systemd":
            # systemd drop-ins live under systemd/*.service.d/; other .conf
            # files (wireplumber, hyprsunset, …) are not unit files.
            check_systemd(path)
        elif suffix in {".service", ".timer", ".socket", ".path", ".target"}:
            check_systemd(path)

    if failures:
        print("Config validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"Config validation passed ({len(files)} tracked files checked).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
