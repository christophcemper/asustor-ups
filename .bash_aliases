# asustor-ups — shell helpers
#
# Author:     Christoph C. Cemper
# Repository: https://github.com/christophcemper/asustor-ups
# License:    MIT — see LICENSE. NO WARRANTY.
#
# POSIX sh compatible on purpose (works in bash and zsh; function names use
# underscores, hyphenated aliases are provided for convenience — same
# conventions as asustor-realfanctrl's .bash_aliases).
#
# Install on a Mac (bash):
#     cp .bash_aliases ~/.bash_aliases_ups
#     printf '%s\n' '[ -f "$HOME/.bash_aliases_ups" ] && . "$HOME/.bash_aliases_ups"' >> ~/.bash_profile
#     . ~/.bash_aliases_ups
# (zsh: append to ~/.zshrc instead.)
#
# Configuration — set before sourcing, e.g. in ~/.bash_profile:
#     export UPS_TARGET="ASUSTOR-UPS-MYNAS@192.168.1.100"
#     export UPS_TARGETS="ASUSTOR-UPS-MYNAS@192.168.1.100 ups2@192.168.1.101"
# If UPS_TARGET is unset, it is read from the first MONITOR line of the
# installed upsmon.conf, so a machine set up per INSTALL.md needs no config.

: "${UPS_CONF:=/opt/homebrew/etc/nut/upsmon.conf}"
if [ -z "${UPS_TARGET:-}" ] && [ -r "$UPS_CONF" ]; then
    UPS_TARGET=$(awk '/^MONITOR /{print $2; exit}' "$UPS_CONF")
fi
: "${UPS_TARGET:=ASUSTOR-UPS-MYNAS@192.168.1.100}"
: "${UPS_TARGETS:=$UPS_TARGET}"

# ---------------------------------------------------------------------------
# Main alias: full live status of the primary UPS
# ---------------------------------------------------------------------------
alias ups='upsc "$UPS_TARGET"'

# The values you look up most, one at a time.
alias ups-state='upsc "$UPS_TARGET" ups.status'        # OL / OB / LB
alias ups-charge='upsc "$UPS_TARGET" battery.charge'   # percent
alias ups-runtime='upsc "$UPS_TARGET" battery.runtime' # seconds
alias ups-load='upsc "$UPS_TARGET" ups.load 2>/dev/null || upsc "$UPS_TARGET" outlet.power'

# ---------------------------------------------------------------------------
# Diagnostics (Mac client per INSTALL.md)
# ---------------------------------------------------------------------------
alias ups-log='tail -f /var/log/upsmon.log'
alias ups-daemon='sudo launchctl print system/org.networkupstools.upsmon | head -8'
alias ups-restart='sudo launchctl kickstart -k system/org.networkupstools.upsmon'

# ups_list [host] — every UPS a NUT server exports (default: UPS_TARGET's host).
ups_list() {
    _ups_host="${1:-${UPS_TARGET#*@}}"
    upsc -l "$_ups_host"
}
alias ups-list='ups_list'

# ups_watch [seconds] — refresh the key values on an interval (default 10 s).
ups_watch() {
    while :; do
        printf '%s  %s' "$(date '+%H:%M:%S')" "$UPS_TARGET"
        printf '  status=%s' "$(upsc "$UPS_TARGET" ups.status 2>/dev/null || echo '??')"
        printf '  charge=%s%%' "$(upsc "$UPS_TARGET" battery.charge 2>/dev/null || echo '?')"
        printf '  runtime=%ss\n' "$(upsc "$UPS_TARGET" battery.runtime 2>/dev/null || echo '?')"
        sleep "${1:-10}"
    done
}
alias ups-watch='ups_watch'

# ---------------------------------------------------------------------------
# Multi-UPS helpers — set UPS_TARGETS to a space-separated list of
# <upsname>@<host> entries (several NAS boxes, a Raspberry Pi NUT server
# aggregating UPSes over a USB hub, a Home Assistant NUT add-on, ...).
# ---------------------------------------------------------------------------

# ups_all [variable] — one line per UPS (default: ups.status), or full dump
# with `ups_all -f`.
ups_all() {
    for _ups_t in $UPS_TARGETS; do
        echo "=== $_ups_t ==="
        case "${1:-}" in
            -f|--full) upsc "$_ups_t" ;;
            '')        upsc "$_ups_t" ups.status ;;
            *)         upsc "$_ups_t" "$1" ;;
        esac
    done
}
alias ups-all='ups_all'
