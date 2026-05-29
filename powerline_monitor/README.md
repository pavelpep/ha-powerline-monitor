# Powerline Monitor (Home Assistant add-on)

Reads powerline link rates from TP-Link / HomePlug AV2 adapters using
[open-plc-utils](https://github.com/qca/open-plc-utils) and publishes them to
Home Assistant over MQTT. Works with the plain Ethernet-only adapters (TL-PA
series) that have no web portal, which the existing HA integrations can't reach.

## Requirements

- Home Assistant **OS** or **Supervised** (add-ons need the Supervisor).
- The **Mosquitto broker** add-on, or any MQTT broker you point it at.
- The HA machine must be on the **same Layer 2 segment** as one powerline
  adapter. Same switch is fine. A router between them is not, because the
  management frames are raw Ethernet (EtherType 0x88E1), not IP.

## What you get

Per remote adapter (its own device in HA):

- **TX Rate** and **RX Rate** sensors (Mbit/s, with history).
- **Link Degraded** binary sensor (device class `problem`), on when the lower of
  TX/RX drops below `degraded_threshold`. Good for automations/alerts.
- Optional **Firmware**, **Hardware**, **TEI** diagnostic sensors.

Plus a **Powerline Network** device with **Stations** (count) and **Worst Link
Rate** for a single number to alert on.

## Configuration

| Option | What it does |
|---|---|
| `interface` | Host NIC the adapter is reachable on. **Leave blank to auto-detect** — the add-on probes each NIC and picks the one a powerline adapter answers on. Set it manually (e.g. `eth0`, `end0` on a Pi) only if detection picks wrong. |
| `adapter_mac` | MAC of the adapter plugged into your switch. Leave blank to auto-detect. **Set this if no stations show up** (see below). |
| `poll_interval` | Seconds between polls (default 60). |
| `degraded_threshold` | Mbit/s below which a link is flagged degraded (default 50). |
| `station_names` | List of `MAC=Name` entries to label adapters, e.g. `AA:BB:CC:DD:EE:FF=Office`. |
| `expose_diagnostics` | Also publish firmware / hardware / TEI sensors (default off). |
| `discovery_prefix` | MQTT discovery prefix (default `homeassistant`). |
| `diagnostic` | Logs the interface list and raw `plcstat` output each cycle. Turn off once it's working. |
| `mqtt_host` / `port` / `user` / `password` | Only needed if you're not using the Mosquitto add-on. Leave blank to auto-connect. |

## First run

Start the add-on and open the **Log** tab. You should see:

- which interface was auto-detected (or the list of NICs if you set it manually),
- the raw `plcstat` output,
- a line per remote station like `Station Office (AA:BB:..) TX=180 RX=165 Mbit/s degraded=OFF`.

## "No remote stations seen"

This is the switch caveat from open-plc-utils' own docs. Auto-detection relies
on the adapter answering a broadcast management address, and some switches don't
flood that to every port. The fix is to name the adapter directly:

1. Find the MAC of the adapter plugged into your switch (printed on the label,
   or in your switch/router MAC table).
2. Put it in `adapter_mac` and restart.

A unicast frame to a known MAC passes through the switch normally.

## Notes

- Rates are the average PHY link rates the adapter reports, the same numbers
  TP-Link's tpPLC tool shows. Real throughput is lower.
- This is read-only monitoring. LED and QoS control are not implemented.
- Built against open-plc-utils `plcstat -t` output. If your firmware formats it
  differently, turn on `diagnostic` and share a few `REM` lines.
