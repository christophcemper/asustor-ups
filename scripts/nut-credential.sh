#!/bin/bash
# nut-credential.sh — manage this Mac's NUT login for a UPS shared by an Asustor NAS.
#
#   init      create a random password in the credential file (once; then set it in ADM)
#   copy      put the password on the clipboard (to paste into ADM; cleared after 120 s)
#   apply     write the stored user/password into the live upsmon.conf MONITOR line, restart upsmon
#             (NUT_DRY_RUN=1: render and validate only, touch nothing)
#   rollback  restore the newest upsmon.conf backup and restart upsmon
#   check     show whether the last upsmon start logged in or got ERR ACCESS-DENIED
#
# Environment (all optional):
#   UPS_TARGET     <upsname>@<nas-ip>; default: the first MONITOR line of the live upsmon.conf
#   NUT_ETC        NUT config dir (default /opt/homebrew/etc/nut)
#   NUT_CRED_FILE  credential file (default ~/.config/asustor-ups/nut-credential.env, mode 600,
#                  lines NUT_USER=... and NUT_PASSWORD=...)
#   NUT_USER       user name written by init (default upsadmin, ADM's default NUT user)
#   MIN_CHARGE     apply/rollback refuse below this battery charge in % (default 30)
#
# The password is never printed, never put on a command line and never written to the repo.
# apply/rollback refuse to touch upsmon unless the UPS is on line power with enough charge.
set -euo pipefail

NUT_ETC="${NUT_ETC:-/opt/homebrew/etc/nut}"
CONF="$NUT_ETC/upsmon.conf"
LABEL="system/org.networkupstools.upsmon"
LOG="/var/log/upsmon.log"
UPSC="/opt/homebrew/bin/upsc"
CRED="${NUT_CRED_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/asustor-ups/nut-credential.env}"
MIN_CHARGE="${MIN_CHARGE:-30}"

die() { echo "ERROR: $1" >&2; exit "${2:-2}"; }

live_conf() { if [ -r "$CONF" ]; then cat "$CONF"; else sudo cat "$CONF"; fi; }

resolve_ups() {
  UPS="${UPS_TARGET:-}"
  [ -n "$UPS" ] || UPS="$(live_conf 2>/dev/null | awk '/^MONITOR /{print $2; exit}')"
  [[ "$UPS" =~ ^[A-Za-z0-9_.-]+@[A-Za-z0-9_.:-]+$ ]] || die "no UPS target; set UPS_TARGET=<upsname>@<nas-ip> or install upsmon.conf first"
}

read_cred() {
  [ -f "$CRED" ] || die "no credential file $CRED (run: $0 init)"
  [ "$(stat -f %Lp "$CRED")" = "600" ] || die "$CRED must be mode 600"
  local k v
  USER_NAME="" PASSWORD=""
  while IFS='=' read -r k v; do
    case "$k" in NUT_USER) USER_NAME="$v" ;; NUT_PASSWORD) PASSWORD="$v" ;; esac
  done < "$CRED"
  [[ "$USER_NAME" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || die "NUT_USER missing or invalid in $CRED"
  # ADM accepts max 32 chars of A-Za-z0-9!@#$%^&*; alphanumerics only keeps upsmon.conf quoting trivial.
  [[ "$PASSWORD" =~ ^[A-Za-z0-9]{12,32}$ ]] || die "NUT_PASSWORD missing or not 12-32 chars A-Za-z0-9 in $CRED"
}

# Never touch upsmon while the UPS is on battery, flagged FSD/LB, unreachable, or low.
preflight() {
  local st ch
  st="$("$UPSC" "$UPS" ups.status 2>/dev/null)" || die "UPS $UPS unreachable; not touching upsmon" 4
  ch="$("$UPSC" "$UPS" battery.charge 2>/dev/null)" || die "cannot read battery.charge; not touching upsmon" 4
  case " $st " in
    *" OB "*|*" LB "*|*" FSD "*) die "UPS status '$st'; not touching upsmon" 4 ;;
    *" OL "*) ;;
    *) die "UPS status '$st' is not OL; not touching upsmon" 4 ;;
  esac
  ch="${ch%%.*}"
  [[ "$ch" =~ ^[0-9]+$ ]] && [ "$ch" -ge "$MIN_CHARGE" ] || die "battery.charge '$ch' below $MIN_CHARGE %; not touching upsmon" 4
  echo "preflight OK: status=$st charge=$ch %"
}

# Restart upsmon and wait for its first verdict. Sets RESULT=ok|denied|unknown|failed.
#   failed  = upsmon is not running after the restart (config error): the caller rolls back
#   denied  = connected, but the NAS answered ERR ACCESS-DENIED to the login
#   ok      = connected and no failed login within a few seconds
#   unknown = running but could not connect (NAS unreachable); the config itself is fine
restart_and_wait() {
  local off i new
  off="$(stat -f %z "$LOG" 2>/dev/null || echo 0)"
  sudo launchctl kickstart -k "$LABEL"
  RESULT=unknown
  for i in $(seq 1 25); do
    sleep 1
    new="$(tail -c +"$((off + 1))" "$LOG" 2>/dev/null || true)"
    if grep -q 'Connected to NUT server' <<<"$new"; then
      sleep 3
      new="$(tail -c +"$((off + 1))" "$LOG" 2>/dev/null || true)"
      if grep -q 'ACCESS-DENIED' <<<"$new"; then RESULT=denied; else RESULT=ok; fi
      break
    fi
  done
  pgrep -x upsmon >/dev/null || RESULT=failed
}

cmd_init() {
  [ ! -e "$CRED" ] || die "$CRED already exists; delete it deliberately to rotate"
  local dir pw user="${NUT_USER:-upsadmin}"
  [[ "$user" =~ ^[A-Za-z0-9_.-]{1,32}$ ]] || die "NUT_USER '$user' invalid"
  dir="$(dirname "$CRED")"
  mkdir -p "$dir"; chmod 700 "$dir"
  pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"
  [ "${#pw}" -eq 32 ] || die "could not generate a password"
  ( umask 077; printf 'NUT_USER=%s\nNUT_PASSWORD=%s\n' "$user" "$pw" > "$CRED" )
  chmod 600 "$CRED"
  echo "created $CRED (mode 600, value not shown); next: '$0 copy' and paste it into ADM"
}

cmd_copy() {
  read_cred
  printf %s "$PASSWORD" | pbcopy
  local pw="$PASSWORD"
  ( sleep 120; [ "$(pbpaste)" = "$pw" ] && printf '' | pbcopy ) >/dev/null 2>&1 &
  echo "password copied to the clipboard; it is cleared again after 120 s"
}

cmd_apply() {
  read_cred
  resolve_ups
  live_conf >/dev/null 2>&1 || die "no live $CONF; install it first (INSTALL.md §2.2)"
  preflight
  local tmp line n=0 kw sys pv u p typ rest
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  chmod 700 "$tmp"
  # Rewrite only fields 4/5 (user, password) of the MONITOR line for $UPS; every other line is kept verbatim.
  ( umask 077
    live_conf | while IFS= read -r line || [ -n "$line" ]; do
      read -r kw sys pv u p typ rest <<<"$line" || true
      if [ "$kw" = "MONITOR" ] && [ "$sys" = "$UPS" ]; then
        line="MONITOR $sys $pv $USER_NAME $PASSWORD $typ${rest:+ $rest}"
      fi
      printf '%s\n' "$line"
    done > "$tmp/upsmon.conf" )
  n="$(grep -c "^MONITOR $UPS " "$tmp/upsmon.conf" || true)"
  [ "$n" = "1" ] || die "found $n MONITOR lines for $UPS in $CONF, expected 1"
  grep -q "^MONITOR $UPS [0-9]* .* secondary$" "$tmp/upsmon.conf" || die "MONITOR line for $UPS is not a 'secondary'"
  [ "$(grep -c -F -- "$PASSWORD" "$tmp/upsmon.conf" || true)" = "1" ] || die "the password must appear exactly once in the rendered config"
  if live_conf | cmp -s - "$tmp/upsmon.conf"; then
    echo "live $CONF already has this credential; nothing to do (see: $0 check)"; exit 0
  fi
  [ "${NUT_DRY_RUN:-0}" = "1" ] && { echo "dry run OK: only the MONITOR credential for $UPS would change"; exit 0; }
  local bak="$CONF.bak-$(date +%Y%m%d-%H%M%S)"
  sudo install -m 0600 -o root -g wheel "$CONF" "$bak"
  sudo install -m 0600 -o root -g wheel "$tmp/upsmon.conf" "$CONF"
  echo "installed new $CONF (mode 600 root:wheel); backup: $bak"
  restart_and_wait
  case "$RESULT" in
    ok)     echo "RESULT: upsmon restarted and the NAS accepted the login (no ACCESS-DENIED)." ;;
    denied) echo "RESULT: upsmon restarted with the stored credential, but the NAS still answers ERR ACCESS-DENIED."
            echo "        Expected until the same password is set in ADM. Monitoring itself works. Re-check later: $0 check"
            exit 3 ;;
    unknown) echo "RESULT: upsmon is running with the new config but could not reach $UPS; login not verified. Re-check: $0 check" >&2
            exit 6 ;;
    *)      echo "RESULT: upsmon is not running after the restart; rolling back to $bak" >&2
            sudo install -m 0600 -o root -g wheel "$bak" "$CONF"; restart_and_wait
            echo "rollback result: $RESULT" >&2
            exit 5 ;;
  esac
}

cmd_rollback() {
  resolve_ups
  preflight
  local bak
  bak="$(ls -1t "$CONF".bak-* 2>/dev/null | head -1 || true)"
  [ -n "$bak" ] || die "no backup $CONF.bak-* found"
  sudo install -m 0600 -o root -g wheel "$bak" "$CONF"
  echo "restored $bak"
  restart_and_wait
  echo "RESULT: $RESULT"
}

cmd_check() {
  local last new verdict
  resolve_ups
  last="$(grep -n 'Network UPS Tools upsmon' "$LOG" 2>/dev/null | tail -1 | cut -d: -f1 || true)"
  [ -n "$last" ] || die "no upsmon start found in $LOG"
  new="$(tail -n +"$last" "$LOG")"
  pgrep -x upsmon >/dev/null && echo "upsmon: running" || echo "upsmon: NOT RUNNING"
  echo "since last start: established=$(grep -c 'established' <<<"$new") login-denied=$(grep -c 'ACCESS-DENIED' <<<"$new") giving-up=$(grep -c 'Giving up on the primary' <<<"$new")"
  echo "clients logged in on $UPS:"; "$UPSC" -c "$UPS" 2>/dev/null | grep -v -E '^(Connected|Certificate)' | sed 's/^/  /'
  # The latest login event decides: denials before a later "established" are history.
  verdict="$(grep -E 'ACCESS-DENIED|Communications with UPS .* established' <<<"$new" | tail -1 || true)"
  case "$verdict" in
    *ACCESS-DENIED*) echo "RESULT: login still denied"; exit 3 ;;
    *established*)   echo "RESULT: login accepted" ;;
    *)               echo "RESULT: no login event since the last upsmon start; re-check later"; exit 4 ;;
  esac
}

case "${1:-}" in
  init) cmd_init ;; copy) cmd_copy ;; apply) cmd_apply ;; rollback) cmd_rollback ;; check) cmd_check ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
