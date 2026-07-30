#!/bin/sh
# NUT upsmon NOTIFYCMD -> macOS Notification Center via terminal-notifier
MSG="$1"
TYPE="${NOTIFYTYPE:-EVENT}"
TN="/opt/homebrew/bin/terminal-notifier"

uid=$(stat -f%u /dev/console)
user=$(stat -f%Su /dev/console)

case "$TYPE" in
  ONBATT|LOWBATT|FSD|COMMBAD|NOCOMM|SHUTDOWN|REPLBATT) sound="Basso" ;;
  ONLINE|COMMOK)                                       sound="Glass" ;;
  *)                                                   sound="Submarine" ;;
esac

if [ -n "$uid" ] && [ "$user" != "root" ] && [ "$user" != "loginwindow" ] && [ "$user" != "_mbsetupuser" ]; then
  launchctl asuser "$uid" sudo -u "$user" \
    "$TN" -title "UPS — $TYPE" -message "$MSG" -sound "$sound" >/dev/null 2>&1
fi

logger -t upsmon "$TYPE: $MSG"
