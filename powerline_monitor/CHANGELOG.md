# Changelog

## 0.4.0

- `adapter_mac` now auto-fills: when left blank, the add-on reads the local
  adapter's MAC (via the local management address) and uses it as an explicit
  unicast device. This handles switches that don't flood the broadcast
  management address, so stations appear without manual configuration.

## 0.3.1

- Set `init: false` so the base image's bundled s6-overlay runs as PID 1,
  fixing the `s6-overlay-suexec: fatal: can only run as pid 1` startup error.

## 0.3.0

- `interface` now auto-detects by default: with it left blank, the add-on probes
  each host NIC and picks the one a powerline adapter responds on. Falls back to
  `eth0` with a warning if none answer. Set it manually to override.
- `interface` and `adapter_mac` are now optional in the schema.

## 0.2.2

- Fixed malformed JSON in the "Stations" sensor MQTT discovery payload (stray
  quote) that prevented the sensor from being created.

## 0.2.1

- Removed deprecated `build.yaml`; base images now resolve from Home Assistant
  defaults, with a `BUILD_FROM` default in the Dockerfile for standalone builds.

## 0.2.0

- Added a "Link Degraded" binary sensor per station (device_class problem),
  triggered when the lower of TX/RX falls below `degraded_threshold`.
- Added a Powerline Network device with "Stations" count and "Worst Link Rate".
- Added `station_names` so adapters can be labelled (e.g. AA:BB:..=Kitchen).
- Added optional diagnostic sensors (firmware, hardware, TEI) via
  `expose_diagnostics`.
- Added `discovery_prefix` and `expire_after` handling for robustness.

## 0.1.0

- Initial release.
- Polls `plcstat -t` and publishes per-station TX/RX link rates over MQTT.
- MQTT discovery so each remote adapter appears as a device automatically.
- Diagnostic mode logs interfaces and raw tool output.
