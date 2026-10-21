# TROUBLESHOOTING

All examples use `ASUSTOR-UPS-MYNAS@192.168.1.100` — substitute your UPS name and
NAS IP. The Mac-side log is `/var/log/upsmon.log`.

<a name="login-failed"></a>
## `Login on UPS [...] failed - got [ERR ACCESS-DENIED]`

ADM's NUT server has exactly **one** account, the user name and password set in
ADM → External Devices → UPS → Preferences (ADM ships a well-known default; change
it). A `MONITOR` line with any other user or the `CHANGE_ME_readonly` placeholder is
rejected — **but everything user-visible still works**, because anonymous reads are
allowed: polling, the `ups` alias, notifications, and local ONBATT/LOWBATT handling
all function. The log shows `Communications ... established` after a failed login on
a reconnect (a fresh start only logs `Connected to NUT server` and the failed login).

**Fix:** put the ADM account's user name and password into the `MONITOR` line and
restart upsmon: `sudo launchctl kickstart -k system/org.networkupstools.upsmon`.
The account has the NUT role `master` (ADM's only role), so every client holds that
privilege; keep `upsmon.conf` readable by root only (`chmod 600`). Never use
`upsmon -c` to test a config: it sends `fsd`/`stop`/`reload` to the running daemon.

What the failed login costs you: the NAS (NUT primary) can't count your Mac as a
logged-in secondary, so coordinated shutdown ordering (primary waits for
secondaries before killing power) isn't guaranteed. The Mac still shuts itself down
on LOWBATT/FSD via its own polling. For a home/studio LAN this is usually an
acceptable trade-off.

## `connect failed: Connection failure: Connection refused`

Seen whenever the NAS is rebooting, powered off, or the "network UPS server" option
got disabled in ADM. upsmon retries forever (this is fine). Check:

```bash
ping -c1 192.168.1.100
```

```bash
nc -vz 192.168.1.100 3493
```

If port 3493 is closed while the NAS is up: re-enable network UPS sharing in
ADM → Settings → Hardware → UPS, and confirm this Mac's IP is on the allowed list.

## `Connected to NUT server ... in SSL` / `Certificate verification (by client) is disabled`

Informational, not an error. The NAS's upsd offers SSL; the client encrypts but
does not verify the NAS's self-signed certificate. Acceptable on a trusted LAN.

## No macOS notifications on power events

1. `terminal-notifier` installed? (`which terminal-notifier` → `/opt/homebrew/bin/`)
2. macOS System Settings → Notifications → **terminal-notifier**: allowed?
3. `notify.sh` executable? (`ls -l /opt/homebrew/etc/nut/notify.sh`)
4. Test manually:

```bash
sudo NOTIFYTYPE=ONLINE /opt/homebrew/etc/nut/notify.sh "test message"
```

Events also always go to syslog (`logger -t upsmon`).

## Daemon not running

```bash
sudo launchctl print system/org.networkupstools.upsmon | head -8
```

Expect `state = running` and two `upsmon -F` processes in `ps aux` (root parent +
`nobody` child — that's NUT's normal privilege separation, not a duplicate).
Restart with:

```bash
sudo launchctl kickstart -k system/org.networkupstools.upsmon
```

## Reading the values

`upsc` talks straight to the NAS on every call — values are live.
`battery.runtime` is in **seconds**. `ups.status: OL` = on line, `OB` = on battery,
`LB` = low battery. `outlet.power` (where supported) is the measured draw in watts.
