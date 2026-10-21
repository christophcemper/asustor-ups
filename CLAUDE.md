# CLAUDE.md — asustor-ups

Public documentation repo: monitoring a UPS attached to an Asustor NAS from macOS
clients via NUT. Read [README.md](README.md) first; [INSTALL.md](INSTALL.md) has
the setup; [TROUBLESHOOTING.md](TROUBLESHOOTING.md) the failure modes.

## Rules

- **This repo is public.** Never commit real LAN IPs, hostnames, machine names,
  credentials, serial numbers, or log excerpts containing them. All examples use
  the placeholders `ASUSTOR-UPS-MYNAS` and `192.168.1.100` — keep it that way.
- `config/` holds **templates**: on a real machine they are installed to
  `/opt/homebrew/etc/nut/` and `/Library/LaunchDaemons/`, with the `MONITOR` line
  parameterized by `scripts/install-mac.sh <upsname>@<nas-ip>`. The NUT login is
  never committed: `scripts/nut-credential.sh` writes it from a mode-600 file outside
  the repo into the live `MONITOR` line.
- `upsmon -c` is not a config test (it sends `fsd`/`stop`/`reload`); never use it to validate.
- Docs-only repo — no build, no tests. Verifying a change means walking the
  commands in INSTALL.md §2.6 / running `scripts/status.sh` on a machine with the
  stack installed.
- The daemon design is deliberate: a system LaunchDaemon (not `brew services`, not
  a LaunchAgent) so monitoring runs pre-login and may invoke `shutdown`.
- Shell scripts are plain bash, `set -euo pipefail`, no dependencies beyond
  Homebrew `nut` and `terminal-notifier`.
