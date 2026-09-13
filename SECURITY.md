# Security Policy

## Scope

This project is **desktop configuration**: Hyprland override configs, Quickshell
bar plugins, and small helper scripts. It runs as the **logged-in user** and
does not operate with elevated privileges. Severity is therefore low in the
usual sense — but desktop config touches the whole UI, so real bugs can still
bite.

Attractively in-scope concerns:

- Shell/`hyprctl` command injection through untrusted input (e.g. window
  titles, app ids flowing into dispatched commands or the taskbar's icon
  resolver).
- Any file the **installer** writes outside the intended paths, or that
  backs up/restores the wrong thing.
- Bindings that could silently destroy state (the `Ctrl+Alt+Delete` → panic-is
  behaviors this project deliberately removed are the pattern we care about).

Out of scope: the Omarchy/Hyprland/Quickshell codebases themselves — report
those upstream.

## Reporting

Please **do not open a public issue for suspected vulnerabilities.** Instead:

- Open a **private** GitHub vulnerability report on the repository, or
- Email the maintainer directly (see the GitHub profile linked from the
  repository).

Include: a description, the affected file(s) and config version, and a
proof-of-concept if you have one. Response time is aimed at within a week for
reproducible issues.

## Handling

- Confirmed issues are fixed privately and released as a normal commit with a
  `security` note in the [CHANGELOG](CHANGELOG.md).
- Fixes land the same way every other change does: config + docs updated
  together, no secrets, no surprise paths.

## Disclosure

This is a small, single-maintainer config project.

- **30 days** after a fix is committed **before** public disclosure.
- The reporter is credited (if they want to be) in the changelog entry.

## Security-conscious defaults

This project deliberately unbinds dangerous or hijacking defaults as part of
its design:

- `Ctrl+Alt+Delete` (close-all-windows panic) — removed.
- `Super+C/V/X` universal clipboard — removed so app-level clipboard works
  predictably and nothing silently grabs your clipboard.
- `Super+Print` color-picker → made a fullscreen screenshot instead.

Keep these unbindings intact when contributing volume-binding changes.