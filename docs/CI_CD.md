# CI/CD

Every change flows through the same gates, locally and on GitHub:

```
edit → scripts/ci/run-local.sh → branch → PR → CI → merge to main → CD package
                                                        └─ tag v* → GitHub Release
```

## What CI checks (`.github/workflows/ci.yml`)

| Job | Gate |
|---|---|
| **ShellCheck** | `scripts/ci/check_shell.sh` — every shell script, `--severity=warning` |
| **Python syntax** | `py_compile` on tracked `*.py` and the extensionless `bin/*` Python tools |
| **Config formats** | `scripts/ci/validate_configs.py` — JSON, JSONC (comments/trailing commas allowed), TOML, systemd units |
| **Lua** | `luac -p` on every tracked `*.lua` |
| **YAML** | PyYAML parse of every workflow and config YAML |
| **Installer** | `scripts/ci/check_install_pairs.py` + `scripts/ci/smoke_install.sh` |
| **Workflows** | `actionlint` |
| **CI OK** | Aggregate gate — the only check that needs to be required in branch protection |

The installer smoke test runs `install.sh --apply everything`, `--verify`,
a second `--apply`, and `--revert` in a throwaway `HOME`, with `hyprctl`,
`systemctl`, `pgrep` and `pkill` stubbed and the session bus unset. It also
fails if the retired single-window square-aspect toggle is installed again.

## What CD does (`.github/workflows/cd.yml`)

- **Push to `main`**: re-runs the installer smoke test, then builds
  `omarchy-customization-<branch>-<sha>.tar.gz` from `git archive` plus
  `SHA256SUMS` and uploads it as a workflow artifact (30 days).
- **Push a `v*` tag**: the same archive is attached to a generated GitHub
  Release. Tags containing a hyphen (e.g. `v1.2.0-rc1`) are marked prerelease.
- **Manual run**: `gh workflow run cd.yml` packages the current ref without
  publishing a release.

There is no remote deploy step: this repo is installed deliberately with
`./install.sh`, and the post-update hook re-applies it after `omarchy-update`.

## Run the gates locally

```bash
scripts/ci/run-local.sh
```

Requirements: `shellcheck`, `python3` (3.11+ for `tomllib`), `luac`,
PyYAML, and optionally `actionlint`. Missing `shellcheck`, `luac` or
`actionlint` are skipped locally (CI always runs them); everything else is
required.

## Releasing

```bash
git tag -a v1.3.0 -m "v1.3.0"
git push origin v1.3.0
```

CD publishes the release with auto-generated notes. Update `CHANGELOG.md`
before tagging.

## When a gate fails

1. CI failure on a PR → the PR stays unmerged.
2. File the failure as a GitHub issue with the failing job/log link
   (`gh issue create`).
3. Fix it on the same branch, push, and wait for the re-run.
4. Merge only when the **CI OK** job is green; CD then packages `main`.

Branch protection for `main` should require the **CI OK** check (the
aggregate job) so a failing or cancelled job blocks the merge.
