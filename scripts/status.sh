#!/bin/bash
# status.sh — one-shot health check of the UPS monitoring stack on this Mac.
# Usage: ./scripts/status.sh [<upsname>@<nas-ip>]
# Without an argument, the UPS is read from the installed upsmon.conf.
UPSC="/opt/homebrew/bin/upsc"
CONF="/opt/homebrew/etc/nut/upsmon.conf"

UPS="${1:-$(awk '/^MONITOR /{print $2; exit}' "$CONF" 2>/dev/null)}"
if [ -z "$UPS" ]; then
  echo "No UPS given and none found in $CONF" >&2
  exit 1
fi

echo "== UPS ($UPS) =="
if "$UPSC" "$UPS" >/dev/null 2>&1; then
  for v in ups.status battery.charge battery.runtime output.voltage outlet.power device.model; do
    printf '  %-18s %s\n' "$v" "$("$UPSC" "$UPS" "$v" 2>/dev/null)"
  done
else
  echo "  UNREACHABLE — is the NAS up and does its firewall allow this Mac on TCP 3493?"
fi

echo "== upsmon daemon =="
if pgrep -x upsmon >/dev/null; then
  echo "  running ($(pgrep -x upsmon | wc -l | tr -d ' ') processes; root parent + nobody child is normal)"
else
  echo "  NOT RUNNING — sudo launchctl kickstart -k system/org.networkupstools.upsmon"
fi

echo "== last log lines (/var/log/upsmon.log) =="
tail -5 /var/log/upsmon.log 2>/dev/null | sed 's/^/  /' || echo "  (no log readable)"
