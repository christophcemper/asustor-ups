#!/bin/bash
# install-mac.sh — set up a Mac as a NUT client for a UPS shared by an Asustor NAS.
# Usage: ./scripts/install-mac.sh <upsname>@<nas-ip>
#   e.g. ./scripts/install-mac.sh ASUSTOR-UPS-MYNAS@192.168.1.100
# Discover the UPS name with: upsc -l <nas-ip>
set -euo pipefail

UPS="${1:?usage: $0 <upsname>@<nas-ip>   (e.g. ASUSTOR-UPS-MYNAS@192.168.1.100)}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NUT_ETC="/opt/homebrew/etc/nut"
PLIST="org.networkupstools.upsmon.plist"

echo "==> Installing packages (nut, terminal-notifier)"
brew list nut >/dev/null 2>&1 || brew install nut
brew list terminal-notifier >/dev/null 2>&1 || brew install terminal-notifier

echo "==> Installing configs to $NUT_ETC (UPS: $UPS)"
mkdir -p "$NUT_ETC"
if [ -e "$NUT_ETC/upsmon.conf" ] && [ ! -w "$NUT_ETC/upsmon.conf" ]; then
  echo "    keeping the existing root-only upsmon.conf (it holds a NUT login; see scripts/nut-credential.sh)"
else
  sed "s|^MONITOR .*|MONITOR $UPS 1 monitor CHANGE_ME_readonly secondary|" \
    "$REPO_DIR/config/upsmon.conf" > "$NUT_ETC/upsmon.conf"
fi
cp "$REPO_DIR/config/notify.sh" "$NUT_ETC/"
chmod +x "$NUT_ETC/notify.sh"

echo "==> Installing LaunchDaemon (sudo required)"
sudo cp "$REPO_DIR/config/$PLIST" "/Library/LaunchDaemons/$PLIST"
sudo chown root:wheel "/Library/LaunchDaemons/$PLIST"
sudo chmod 644 "/Library/LaunchDaemons/$PLIST"
sudo launchctl bootout "system/${PLIST%.plist}" 2>/dev/null || true
sudo launchctl bootstrap system "/Library/LaunchDaemons/$PLIST"

CRED="${NUT_CRED_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/asustor-ups/nut-credential.env}"
if [ -f "$CRED" ]; then
  echo "==> Installing the NUT login from $CRED (restarts upsmon)"
  UPS_TARGET="$UPS" "$REPO_DIR/scripts/nut-credential.sh" apply \
    || echo "NOTE: nut-credential.sh apply exited $?; see TROUBLESHOOTING.md#login-failed"
else
  echo "==> No NUT credential file at $CRED: upsmon uses the placeholder login (see TROUBLESHOOTING.md#login-failed)"
fi

PROFILE="$HOME/.bash_profile"
[ "$(basename "${SHELL:-}")" = "zsh" ] && PROFILE="$HOME/.zshrc"
if ! grep -q 'alias ups=' "$PROFILE" 2>/dev/null; then
  echo "==> Adding ups alias to $PROFILE"
  printf '\nalias ups="upsc %s"\n' "$UPS" >> "$PROFILE"
else
  echo "==> ups alias already present in $PROFILE (left unchanged)"
fi

echo "==> Verifying connection to $UPS"
if /opt/homebrew/bin/upsc "$UPS" ups.status 2>/dev/null; then
  echo "OK — UPS reachable."
else
  echo "WARNING: cannot reach $UPS."
  echo "Check the NAS is up and that its firewall (if any) allows this Mac on TCP 3493."
fi

echo "Done. Open a new shell (or 'source $PROFILE') and run: ups"
