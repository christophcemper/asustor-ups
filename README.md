# asustor-ups

Monitor a UPS attached to an **Asustor NAS** from your **Macs** — using
[NUT (Network UPS Tools)](https://networkupstools.org/), with macOS Notification
Center alerts and automatic shutdown on low battery.

Tested with an **Eaton Ellipse ECO 1600** on an Asustor NAS running ADM, and Macs
on Apple Silicon (Homebrew under `/opt/homebrew`). Any UPS that ADM recognizes over
USB should work the same way, since ADM's UPS support is NUT under the hood.

## How it works

```
                 mains power
                      │
        ┌─────────────▼─────────────┐
        │  UPS (e.g. Eaton Ellipse) │
        └─────────────┬─────────────┘
                      │ USB
        ┌─────────────▼─────────────┐
        │  Asustor NAS (ADM)        │  built-in NUT server (upsd, SSL)
        │  e.g. 192.168.1.100       │  serves UPS as: ASUSTOR-UPS-<HOSTNAME>
        └─────────────┬─────────────┘
                      │ TCP 3493 (NUT protocol)
        ┌─────────────▼─────────────┐
        │  Macs (LAN clients)       │  Homebrew NUT: upsmon LaunchDaemon
        │                           │  + `ups` alias + notifications
        └───────────────────────────┘
```

- The **NAS** owns the UPS: ADM detects it over USB and (once enabled) shares it on
  the network via NUT on TCP 3493. No manual config files on the NAS.
- Each **Mac** runs `upsmon` as a system LaunchDaemon: it polls the NAS, sends
  every power event to Notification Center (with per-severity alert sounds), and
  shuts the Mac down cleanly on low battery.
- A `ups` shell alias gives you the full live status in one keystroke-friendly
  command.

## Quick start

See [INSTALL.md](INSTALL.md) for the full walkthrough. Short version:

1. On the NAS: plug in the UPS via USB, then ADM → **Settings → Hardware → UPS** →
   enable the network UPS server and allow your Macs' IPs.
2. On each Mac:

```bash
brew install nut terminal-notifier
```

```bash
./scripts/install-mac.sh ASUSTOR-UPS-MYNAS@192.168.1.100
```

3. Check it:

```bash
ups
```

To discover the UPS name your NAS exports:

```bash
upsc -l 192.168.1.100
```

## Repo layout

- [INSTALL.md](INSTALL.md) — NAS setup + Mac client setup, step by step
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — common failure modes and fixes
- [.bash_aliases](.bash_aliases) — `ups`, `ups-charge`, `ups-watch`, `ups-all` &
  friends; auto-detects the UPS from the installed `upsmon.conf`, supports
  multiple UPSes via `UPS_TARGETS`
- [config/](config/) — template configs (`upsmon.conf`, `notify.sh`, LaunchDaemon plist)
- [scripts/install-mac.sh](scripts/install-mac.sh) — automated Mac-side install
- [scripts/status.sh](scripts/status.sh) — one-shot health check

## What you get

- `ups` → live battery charge, runtime (seconds), load, voltages, UPS status
  (`OL` on line / `OB` on battery / `LB` low battery)
- Notification Center alerts on ONBATT / LOWBATT / FSD / COMMBAD (Basso sound) and
  ONLINE / COMMOK (Glass sound)
- Clean `shutdown -h now` when the battery runs low — even with nobody logged in,
  because upsmon runs as a system LaunchDaemon, not a login agent

## Ideas / roadmap

- **Multi-UPS monitoring via a dedicated NUT host**: a Raspberry Pi with a USB hub
  can run one `upsd` with a `usbhid-ups` driver instance per connected UPS
  (distinguished by serial number in `ups.conf`) — aggregating several UPSes that
  protect different equipment into a single NUT server the Macs and NAS boxes all
  query. Removes the "one NAS per UPS" coupling.
- **Home Assistant as the UPS hub**: HA (e.g. on a Pi with a USB hub) with the
  [NUT add-on](https://github.com/hassio-addons/addon-nut) serving multiple USB
  UPSes, plus the native NUT integration for dashboards, history graphs, and
  automations (alerts, smart-plug load shedding) — while regular NUT clients keep
  working against the add-on's upsd. The `ups-all` helper in
  [.bash_aliases](.bash_aliases) already handles multiple targets client-side.
- Prometheus/Grafana metrics via a NUT exporter
- Push notifications (ntfy / Pushover) in addition to Notification Center
- `upssched`-based delayed/tiered shutdown policies
- Scheduled self-test / "pull the plug" drill checklist

## License

[MIT](LICENSE)
