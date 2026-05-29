#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
set -o pipefail

# Plain echo (no bashio) so it shows even if bashio/with-contenv is broken.
echo "[powerline_monitor] run.sh started" >&2

IFACE="$(bashio::config 'interface')"
ADAPTER_MAC="$(bashio::config 'adapter_mac')"
INTERVAL="$(bashio::config 'poll_interval')"
THRESHOLD="$(bashio::config 'degraded_threshold')"
DIAG="$(bashio::config 'diagnostic')"
EXPOSE_DIAG="$(bashio::config 'expose_diagnostics')"
PREFIX="$(bashio::config 'discovery_prefix')"
echo "[powerline_monitor] config read: iface='${IFACE}' mac='${ADAPTER_MAC}' interval='${INTERVAL}'" >&2

EXPIRE=$(( INTERVAL * 3 + 10 ))
AVAIL_TOPIC="powerline_monitor/status"

# ---------------------------------------------------------------------------
# Interface auto-detection: probe each up host NIC for a powerline adapter by
# reading its hardware/firmware revision. The NIC the adapter answers on wins.
# ---------------------------------------------------------------------------
detect_interface() {
    local cand
    for cand in $(ip -o link show up 2>/dev/null \
                  | awk -F': ' '{print $2}' | sed 's/@.*//' \
                  | grep -E '^(eth|enp|ens|eno|end)'); do
        if plctool -i "${cand}" -r -t 300 2>/dev/null \
           | grep -qiE '[0-9a-f]{2}(:[0-9a-f]{2}){5}'; then
            echo "${cand}"
            return 0
        fi
    done
    return 1
}

if [ -z "${IFACE}" ]; then
    bashio::log.info "No interface set; probing host NICs for a powerline adapter..."
    if IFACE="$(detect_interface)"; then
        bashio::log.info "Auto-detected powerline adapter on interface: ${IFACE}"
    else
        IFACE="eth0"
        bashio::log.warning "No adapter auto-detected; falling back to '${IFACE}'. Set 'interface' manually if this is wrong (turn on diagnostic to list NICs)."
    fi
fi
echo "[powerline_monitor] interface resolved: '${IFACE}'" >&2

# ---------------------------------------------------------------------------
# Adapter MAC auto-fill: the local management address (00:B0:52:00:00:01) is
# answered only by the directly-attached adapter. Grab its real MAC and use it
# as the explicit device, so unicast topology queries cross switches that don't
# flood the broadcast management address.
# ---------------------------------------------------------------------------
detect_adapter_mac() {
    plctool -i "${IFACE}" -r -t 300 2>/dev/null \
      | grep -oiE '[0-9a-f]{2}(:[0-9a-f]{2}){5}' \
      | grep -ivE '^(00:b0:52:00:00:01|ff:ff:ff:ff:ff:ff|00:00:00:00:00:00)$' \
      | head -1
}

if [ -z "${ADAPTER_MAC}" ]; then
    DETECTED_MAC="$(detect_adapter_mac)"
    if [ -n "${DETECTED_MAC}" ]; then
        ADAPTER_MAC="${DETECTED_MAC}"
        bashio::log.info "Auto-detected local adapter MAC: ${ADAPTER_MAC}"
    else
        bashio::log.info "No local adapter MAC detected; querying with the broadcast address. Set 'adapter_mac' manually if no stations appear."
    fi
fi
echo "[powerline_monitor] adapter_mac resolved: '${ADAPTER_MAC}'" >&2

# ---------------------------------------------------------------------------
# Friendly names: station_names entries look like  AA:BB:CC:DD:EE:FF=Kitchen
# ---------------------------------------------------------------------------
declare -A NAMES
while IFS= read -r pair; do
    [ -z "${pair}" ] && continue
    key="${pair%%=*}"
    val="${pair#*=}"
    key="$(echo "${key}" | tr 'a-z' 'A-Z' | tr -d ' ')"
    [ -n "${key}" ] && [ "${key}" != "${val}" ] && NAMES["${key}"]="${val}"
done < <(jq -r '.station_names[]?' /data/options.json 2>/dev/null)

# ---------------------------------------------------------------------------
# Resolve MQTT broker: prefer manual settings, else the Mosquitto add-on.
# Wait for a broker instead of crash-looping, so installing Mosquitto after the
# add-on is started just works without an error loop.
# ---------------------------------------------------------------------------
resolve_mqtt() {
    if bashio::config.has_value 'mqtt_host'; then
        MQTT_HOST="$(bashio::config 'mqtt_host')"
        MQTT_PORT="$(bashio::config 'mqtt_port')"
        MQTT_USER="$(bashio::config 'mqtt_user')"
        MQTT_PASS="$(bashio::config 'mqtt_password')"
        bashio::log.info "Using MQTT broker from add-on options: ${MQTT_HOST}:${MQTT_PORT}"
        return 0
    elif bashio::services.available 'mqtt'; then
        MQTT_HOST="$(bashio::services 'mqtt' 'host')"
        MQTT_PORT="$(bashio::services 'mqtt' 'port')"
        MQTT_USER="$(bashio::services 'mqtt' 'username')"
        MQTT_PASS="$(bashio::services 'mqtt' 'password')"
        bashio::log.info "Using MQTT broker from Home Assistant service: ${MQTT_HOST}:${MQTT_PORT}"
        return 0
    fi
    return 1
}

echo "[powerline_monitor] resolving MQTT broker..." >&2
until resolve_mqtt; do
    echo "[powerline_monitor] no MQTT broker yet; will retry" >&2
    bashio::log.warning "No MQTT broker yet. Install/start the Mosquitto add-on, or set mqtt_host in options. Retrying in 30s..."
    sleep 30
done
echo "[powerline_monitor] MQTT resolved: ${MQTT_HOST}:${MQTT_PORT}" >&2

mqtt() {
    local args=(-h "${MQTT_HOST}" -p "${MQTT_PORT}")
    [ -n "${MQTT_USER}" ] && args+=(-u "${MQTT_USER}")
    [ -n "${MQTT_PASS}" ] && args+=(-P "${MQTT_PASS}")
    mosquitto_pub "${args[@]}" "$@"
}

trap 'mqtt -r -t "${AVAIL_TOPIC}" -m offline 2>/dev/null; exit 0' SIGTERM SIGINT

if [ "${DIAG}" = "true" ]; then
    bashio::log.info "Diagnostic mode on. Network interfaces visible to the add-on:"
    ip -o link | awk -F': ' '{print "  - " $2}'
    bashio::log.info "interface=${IFACE} adapter_mac='${ADAPTER_MAC:-auto}' threshold=${THRESHOLD} Mbit/s"
fi

# Shared availability + device blocks ----------------------------------------
COMMON='"avty_t":"'"${AVAIL_TOPIC}"'","exp_aft":'"${EXPIRE}"
HUB_DEV='"device":{"identifiers":["powerline_network"],"name":"Powerline Network","manufacturer":"Powerline"}'

station_dev() {  # $1 raw mac  $2 id  $3 friendly name
    echo '"device":{"identifiers":["powerline_'"$2"'"],"name":"'"$3"'","manufacturer":"Powerline","via_device":"powerline_network"}'
}

publish_station_discovery() {  # $1 mac  $2 id  $3 name
    local mac="$1" id="$2" name="$3" dev
    dev="$(station_dev "${mac}" "${id}" "${name}")"
    mqtt -r -t "${PREFIX}/sensor/powerline_${id}_tx/config" -m \
        '{"name":"TX Rate","uniq_id":"powerline_'"${id}"'_tx","stat_t":"powerline_monitor/'"${id}"'/tx","unit_of_meas":"Mbit/s","dev_cla":"data_rate","stat_cla":"measurement",'"${COMMON}"','"${dev}"'}'
    mqtt -r -t "${PREFIX}/sensor/powerline_${id}_rx/config" -m \
        '{"name":"RX Rate","uniq_id":"powerline_'"${id}"'_rx","stat_t":"powerline_monitor/'"${id}"'/rx","unit_of_meas":"Mbit/s","dev_cla":"data_rate","stat_cla":"measurement",'"${COMMON}"','"${dev}"'}'
    mqtt -r -t "${PREFIX}/binary_sensor/powerline_${id}_degraded/config" -m \
        '{"name":"Link Degraded","uniq_id":"powerline_'"${id}"'_degraded","stat_t":"powerline_monitor/'"${id}"'/degraded","dev_cla":"problem","pl_on":"ON","pl_off":"OFF",'"${COMMON}"','"${dev}"'}'
    if [ "${EXPOSE_DIAG}" = "true" ]; then
        mqtt -r -t "${PREFIX}/sensor/powerline_${id}_fw/config" -m \
            '{"name":"Firmware","uniq_id":"powerline_'"${id}"'_fw","stat_t":"powerline_monitor/'"${id}"'/fw","ent_cat":"diagnostic",'"${COMMON}"','"${dev}"'}'
        mqtt -r -t "${PREFIX}/sensor/powerline_${id}_hw/config" -m \
            '{"name":"Hardware","uniq_id":"powerline_'"${id}"'_hw","stat_t":"powerline_monitor/'"${id}"'/hw","ent_cat":"diagnostic",'"${COMMON}"','"${dev}"'}'
        mqtt -r -t "${PREFIX}/sensor/powerline_${id}_tei/config" -m \
            '{"name":"TEI","uniq_id":"powerline_'"${id}"'_tei","stat_t":"powerline_monitor/'"${id}"'/tei","ent_cat":"diagnostic",'"${COMMON}"','"${dev}"'}'
    fi
}

publish_hub_discovery() {
    mqtt -r -t "${PREFIX}/sensor/powerline_network_stations/config" -m \
        '{"name":"Stations","uniq_id":"powerline_network_stations","stat_t":"powerline_monitor/network/stations","stat_cla":"measurement","icon":"mdi:lan",'"${COMMON}"','"${HUB_DEV}"'}'
    mqtt -r -t "${PREFIX}/sensor/powerline_network_worst/config" -m \
        '{"name":"Worst Link Rate","uniq_id":"powerline_network_worst","stat_t":"powerline_monitor/network/worst","unit_of_meas":"Mbit/s","dev_cla":"data_rate","stat_cla":"measurement",'"${COMMON}"','"${HUB_DEV}"'}'
}

echo "[powerline_monitor] entering poll loop" >&2
bashio::log.info "Starting Powerline poll loop every ${INTERVAL}s on ${IFACE}"
publish_hub_discovery

while true; do
    OUT="$(plcstat -t -i "${IFACE}" ${ADAPTER_MAC} 2>&1)"
    RC=$?

    if [ "${DIAG}" = "true" ]; then
        bashio::log.info "--- raw plcstat output (rc=${RC}) ---"
        echo "${OUT}"
        bashio::log.info "--- end raw output ---"
    fi

    # Remote stations -> MAC|RX|TX|TEI|HW|FW   (firmware may contain spaces)
    REMOTES="$(echo "${OUT}" | awk '$1=="REM" {
        hw=$8; fw="";
        for (i=9; i<=NF; i++) fw = fw (i>9 ? " " : "") $i;
        print $4"|"$6"|"$7"|"$3"|"hw"|"fw
    }')"

    if [ -z "${REMOTES}" ]; then
        bashio::log.warning "No remote stations seen. If using a switch, set adapter_mac to the local adapter's MAC."
        mqtt -r -t "${AVAIL_TOPIC}" -m offline
        sleep "${INTERVAL}"
        continue
    fi

    mqtt -r -t "${AVAIL_TOPIC}" -m online
    COUNT=0
    WORST=999999

    while IFS='|' read -r MAC RX TX TEI HW FW; do
        [ -z "${MAC}" ] && continue
        COUNT=$(( COUNT + 1 ))
        ID="$(echo "${MAC}" | tr -d ':' | tr 'A-Z' 'a-z')"
        KEY="$(echo "${MAC}" | tr 'a-z' 'A-Z')"
        NAME="${NAMES[${KEY}]:-Powerline ${MAC}}"

        # Numeric guards
        case "${RX}" in (*[!0-9]*|'') RX=0;; esac
        case "${TX}" in (*[!0-9]*|'') TX=0;; esac
        RX=$((10#${RX})); TX=$((10#${TX}))

        LOW=${TX}; [ "${RX}" -lt "${LOW}" ] && LOW=${RX}
        [ "${LOW}" -lt "${WORST}" ] && WORST=${LOW}
        if [ "${LOW}" -lt "${THRESHOLD}" ]; then DEG="ON"; else DEG="OFF"; fi

        publish_station_discovery "${MAC}" "${ID}" "${NAME}"
        mqtt -r -t "powerline_monitor/${ID}/tx" -m "${TX}"
        mqtt -r -t "powerline_monitor/${ID}/rx" -m "${RX}"
        mqtt -r -t "powerline_monitor/${ID}/degraded" -m "${DEG}"
        if [ "${EXPOSE_DIAG}" = "true" ]; then
            mqtt -r -t "powerline_monitor/${ID}/fw" -m "${FW:-unknown}"
            mqtt -r -t "powerline_monitor/${ID}/hw" -m "${HW:-unknown}"
            mqtt -r -t "powerline_monitor/${ID}/tei" -m "${TEI:-0}"
        fi
        bashio::log.info "Station ${NAME} (${MAC}): TX=${TX} RX=${RX} Mbit/s degraded=${DEG}"
    done <<< "${REMOTES}"

    [ "${WORST}" -eq 999999 ] && WORST=0
    mqtt -r -t "powerline_monitor/network/stations" -m "${COUNT}"
    mqtt -r -t "powerline_monitor/network/worst" -m "${WORST}"

    sleep "${INTERVAL}"
done
