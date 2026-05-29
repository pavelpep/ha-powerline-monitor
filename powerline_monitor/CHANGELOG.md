# Changelog

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
