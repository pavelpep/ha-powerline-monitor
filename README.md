# Powerline Add-ons for Home Assistant

A Home Assistant add-on repository. Currently contains:

- **[Powerline Monitor](./powerline_monitor)** — reads link rates from TP-Link /
  HomePlug AV2 powerline adapters (including the WiFi-less TL-PA models with no
  web portal) via [open-plc-utils](https://github.com/qca/open-plc-utils) and
  publishes them to Home Assistant over MQTT.

## Install

[![Open your Home Assistant instance and add this add-on repository.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fpavelpep%2Fha-powerline-monitor)

Or add it manually:

1. In Home Assistant: **Settings > Add-ons > Add-on Store**.
2. Open the **⋮** menu (top right) > **Repositories**.
3. Paste `https://github.com/pavelpep/ha-powerline-monitor` and click **Add**.
4. Close the dialog. The add-on appears in the store. Open it and install.

> Requires Home Assistant OS or Supervised. Add-ons are not installed through
> HACS; this is the native add-on repository mechanism.

## Requirements

- The MQTT integration / Mosquitto broker add-on.
- The HA machine must share a Layer 2 segment with one powerline adapter (same
  switch is fine, a router in between is not, because the management traffic is
  raw Ethernet rather than IP).

## Troubleshooting

**"No remote stations seen" in the log.** Auto-detection relies on the adapter
answering a broadcast management address, and some switches don't flood that to
every port. Fix it by naming the adapter directly: find the MAC printed on the
adapter plugged into your switch, put it in the `adapter_mac` option, and
restart. A unicast frame to a known MAC passes through any switch.

**Wrong interface.** Leave `diagnostic` on for the first run. The log lists every
network interface the add-on can see, so you can confirm whether yours is `eth0`,
`end0`, or something else, and set `interface` accordingly.

**No rates / sensors look wrong.** With `diagnostic` on, the log prints the raw
`plcstat -t` output. Open an issue and paste a couple of the `REM` lines so the
parser can be matched to your firmware's output.

**Add-on stops immediately.** Usually no MQTT broker. Install the Mosquitto
broker add-on, or set `mqtt_host` in the options.

See the [add-on README](./powerline_monitor/README.md) for the full option list.

## License

MIT. Contributions welcome.

## Attribution & trademarks

This add-on builds and runs [open-plc-utils](https://github.com/qca/open-plc-utils)
(Qualcomm Atheros Open Powerline Toolkit), licensed under the Clear BSD license.
See [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).

TP-Link, Qualcomm, Atheros, and HomePlug are trademarks of their respective
owners and are used here only to describe hardware compatibility. This project is
independent and not affiliated with or endorsed by any of them.
