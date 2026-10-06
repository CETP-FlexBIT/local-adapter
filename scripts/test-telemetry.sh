#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: scripts/test-telemetry.sh [rest|mqtt|all] [bess|ev-charger|pv]
Standalone bundle: ./test-telemetry.sh [rest|mqtt|all] [bess|ev-charger|pv]

With no arguments, tests both REST and MQTT. Use rest if no broker is configured.

Environment variables:
  ADAPTER_URL       REST base URL (default: http://127.0.0.1:4000)
  MQTT_HOST         MQTT broker host (default: 127.0.0.1)
  MQTT_PORT         MQTT broker port (default: 1883)
  MQTT_USERNAME     Optional MQTT username
  MQTT_PASSWORD     Optional MQTT password
  DEVICE_ID         External asset ID (default: demo-<asset>)

Examples:
  scripts/test-telemetry.sh rest bess
  ADAPTER_URL=http://127.0.0.1:5050 scripts/test-telemetry.sh rest pv
  scripts/test-telemetry.sh mqtt ev-charger
  scripts/test-telemetry.sh all pv
EOF
}

transport=${1:-all}
asset=${2:-bess}

case "$transport" in -h|--help|help) usage; exit 0 ;; esac

case "$transport" in rest|mqtt|all) ;; *) usage >&2; exit 2 ;; esac
case "$asset" in bess|ev-charger|pv) ;; *) usage >&2; exit 2 ;; esac

adapter_url=${ADAPTER_URL:-http://127.0.0.1:4000}
mqtt_host=${MQTT_HOST:-127.0.0.1}
mqtt_port=${MQTT_PORT:-1883}
device_id=${DEVICE_ID:-demo-$asset}
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

case "$asset" in
  bess)
    mapping_id=demo-bess
    topic=devices/bess/telemetry
    payload=$(printf '{"device":{"id":"%s"},"timestamp":"%s","measurements":{"soc":67.5,"soh":98.2,"active_power":-4250,"dc_voltage":720.4,"battery_temperature":26.1,"status":"charge"}}' "$device_id" "$timestamp")
    ;;
  ev-charger)
    mapping_id=demo-ev-charger
    topic=devices/ev-charger/telemetry
    payload=$(printf '{"device":{"id":"%s"},"timestamp":"%s","measurements":{"vehicle_soc":54,"active_power":11000,"voltage_l1":230.4,"current_l1":15.9,"energy_consumed":18.7,"charger_status":"charge","connector_status":"occupied"}}' "$device_id" "$timestamp")
    ;;
  pv)
    mapping_id=demo-pv
    topic=devices/pv/telemetry
    payload=$(printf '{"device":{"id":"%s"},"timestamp":"%s","measurements":{"inverter_power":8450,"nominal_power":10000,"grid_export":6120,"grid_import":0,"grid_voltage_l1":231.2,"energy_produced":42.8,"grid_frequency":50.01,"inverter_status":"producing"}}' "$device_id" "$timestamp")
    ;;
esac

send_rest() {
  command -v curl >/dev/null 2>&1 || { echo "curl is required for REST tests" >&2; exit 1; }
  echo "POST $adapter_url/v1/ingest (mapping: $mapping_id, device: $device_id)"
  curl --fail-with-body --silent --show-error \
    --request POST "$adapter_url/v1/ingest" \
    --header 'Content-Type: application/json' \
    --header "X-Mapping-Id: $mapping_id" \
    --data "$payload"
  printf '\n'
}

send_mqtt() {
  command -v mosquitto_pub >/dev/null 2>&1 || {
    echo "mosquitto_pub is required for MQTT tests (install the Mosquitto clients)" >&2
    exit 1
  }
  set -- -h "$mqtt_host" -p "$mqtt_port" -V mqttv5 -q 1 -t "$topic" -m "$payload"
  [ -z "${MQTT_USERNAME:-}" ] || set -- "$@" -u "$MQTT_USERNAME"
  [ -z "${MQTT_PASSWORD:-}" ] || set -- "$@" -P "$MQTT_PASSWORD"
  echo "PUBLISH mqtt://$mqtt_host:$mqtt_port/$topic (QoS 1, device: $device_id)"
  if ! mosquitto_pub "$@"; then
    echo "MQTT publish failed. Verify the broker address and credentials." >&2
    echo "For an installed Docker deployment, start the bundled broker:" >&2
    echo "  docker compose --profile mqtt up -d mosquitto" >&2
    echo "For standalone mode, start your separately managed MQTT broker." >&2
    echo "Configure matching subscriptions in the adapter MQTT page or config/mqtt.yaml." >&2
    exit 1
  fi
  echo "MQTT publish acknowledged"
}

case "$transport" in
  rest) send_rest ;;
  mqtt) send_mqtt ;;
  all) send_rest; send_mqtt ;;
esac
