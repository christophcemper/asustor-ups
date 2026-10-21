# INSTALL

Two halves: the **NAS** (owns the UPS, runs the NUT server) and each **Mac**
(network client: alias, `upsmon` daemon, notifications, auto-shutdown).

Throughout, replace the examples with your values:

- `192.168.1.100` → your NAS's LAN IP (a fixed IP or DHCP reservation is strongly
  recommended)
- `ASUSTOR-UPS-MYNAS` → the UPS name your NAS exports (discover it with
  `upsc -l <nas-ip>` after enabling the server; ADM typically derives it from the
  NAS hostname)

---

## 1. Asustor NAS — NUT server

1. **Connect the UPS**: plug the UPS's USB cable into the NAS, and power the NAS
   from the UPS's battery-protected outlets.
2. **ADM web UI** → **External Devices → UPS → Preferences** (ADM 5.1.x; older ADM
   versions put it under Settings → Hardware):
   - The UPS should be detected automatically (NUT's `usbhid-ups` driver handles
     most Eaton/APC/CyberPower models).
   - Set the NAS behaviour on power loss (shutdown or safe mode, and the wait time).
3. **Enable network UPS sharing** (same window): tick **"Enable network UPS
   Support"**. This starts `upsd` on **TCP 3493**, on all interfaces. ADM 5.1 has
   **no allowed-IP list** (the IP grid only shows the NAS's own addresses); restrict
   the port with ADM Defender → Firewall if you need to. In the same window ADM lets
   you set the NUT **user name and password** (it has exactly one account, and ships a
   well-known default password): change it, and use that account in each Mac's
   `MONITOR` line (§2.2).
4. **Verify from an allowed machine** (after §2.1):

```bash
upsc -l 192.168.1.100
```

```bash
upsc ASUSTOR-UPS-MYNAS@192.168.1.100
```

   Expect ~50 variables including `device.model`, `battery.charge`,
   `battery.runtime`, and `ups.status: OL`.

> ADM manages the NUT configs on the NAS — there is nothing to edit by hand there.
> If the NAS IP or the allowed-IP list changes, revisit step 3.

---

## 2. Any Mac — NUT client

Automated: [scripts/install-mac.sh](scripts/install-mac.sh) does everything below
(needs sudo for the LaunchDaemon):

```bash
./scripts/install-mac.sh ASUSTOR-UPS-MYNAS@192.168.1.100
```

Manual steps:

### 2.1 Install packages

```bash
brew install nut terminal-notifier
```

This provides `/opt/homebrew/bin/upsc`, `/opt/homebrew/sbin/upsmon`, and the
notifier used for Notification Center alerts.

### 2.2 Configs

Copy the two files from [config/](config/) into `/opt/homebrew/etc/nut/`, then edit
the `MONITOR` line in `upsmon.conf` for your UPS:

```bash
cp config/upsmon.conf config/notify.sh /opt/homebrew/etc/nut/ && chmod +x /opt/homebrew/etc/nut/notify.sh
```

- `upsmon.conf` — the line that matters:
  `MONITOR <upsname>@<nas-ip> 1 <user> <password> secondary`
  plus `SHUTDOWNCMD "/sbin/shutdown -h now"` and NOTIFYCMD/NOTIFYFLAG wiring so every
  event (ONBATT, LOWBATT, FSD, COMMOK/COMMBAD, …) goes to syslog **and** `notify.sh`.
  Use the NUT user name and password you set in ADM (§1 step 3); with any other value
  the login is rejected — see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#login-failed) for
  why that is usually harmless, and how to fix it.
  Instead of typing the password into the file, you can let
  [scripts/nut-credential.sh](scripts/nut-credential.sh) handle it: `init` generates a
  random password into `~/.config/asustor-ups/nut-credential.env` (mode 600), `copy`
  puts it on the clipboard for ADM, and `apply` writes it into the live `MONITOR` line
  (root-only, with a backup) and restarts upsmon — only while the UPS is on line power.
  `check` tells you whether the NAS accepted the login; `rollback` restores the backup.
  `install-mac.sh` runs `apply` automatically when that file exists.
- `notify.sh` — bridges NUT events to macOS Notification Center via
  `terminal-notifier`, resolving the console user with `stat -f%Su /dev/console`
  and picking an alert sound per event class (bad → Basso, good → Glass, other →
  Submarine). Also logs each event via `logger -t upsmon`.

### 2.3 LaunchDaemon (runs upsmon at boot)

```bash
sudo cp config/org.networkupstools.upsmon.plist /Library/LaunchDaemons/ && sudo chown root:wheel /Library/LaunchDaemons/org.networkupstools.upsmon.plist && sudo chmod 644 /Library/LaunchDaemons/org.networkupstools.upsmon.plist && sudo launchctl bootstrap system /Library/LaunchDaemons/org.networkupstools.upsmon.plist
```

The plist runs `/opt/homebrew/sbin/upsmon -F` (foreground, launchd-managed),
`RunAtLoad` + `KeepAlive`, logging to `/var/log/upsmon.log`. upsmon starts as root
and drops its polling child to `nobody` — two processes in `ps` is normal.

> Don't use `brew services start nut` — a system LaunchDaemon is deliberate, so
> monitoring runs before login and has the rights to shut the machine down.

### 2.4 Shell alias

Either the single alias — for bash:

```bash
echo 'alias ups="upsc ASUSTOR-UPS-MYNAS@192.168.1.100"' >> ~/.bash_profile
```

(for zsh, macOS's default, append the same line to `~/.zshrc`) — or source the
full helper set from [.bash_aliases](.bash_aliases), which adds `ups-charge`,
`ups-runtime`, `ups-watch`, `ups-log`, `ups-all` (multi-UPS), and more, and
auto-detects the UPS from the installed `upsmon.conf`:

```bash
cp .bash_aliases ~/.bash_aliases_ups && printf '%s\n' '[ -f "$HOME/.bash_aliases_ups" ] && . "$HOME/.bash_aliases_ups"' >> ~/.bash_profile
```

### 2.5 On the NAS

Add this Mac's IP to the allowed list in ADM (§1 step 3), or connections will be
refused.

### 2.6 Verify

```bash
ups
```

```bash
sudo launchctl print system/org.networkupstools.upsmon | head -8
```

```bash
tail -20 /var/log/upsmon.log
```

Healthy output ends with `Communications with UPS ... established`. Optionally pull
the UPS's mains plug for a few seconds — you should get an ONBATT notification with
the Basso sound, then ONLINE/Glass when re-plugged.

---

## 3. Uninstall (Mac)

```bash
sudo launchctl bootout system/org.networkupstools.upsmon; sudo rm /Library/LaunchDaemons/org.networkupstools.upsmon.plist; brew uninstall nut
```

Then remove the alias line from your shell profile and the files in
`/opt/homebrew/etc/nut/`.
