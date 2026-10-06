#!/bin/sh
set -eu

IMAGE="ghcr.io/cetp-flexbit/local-adapter"
VERSION="1.0.0"
RELEASE_URL="https://github.com/CETP-FlexBIT/local-adapter/releases/download"
USE_DOCKER=1
MODE_SET=0
BUNDLE_DIR="$(pwd)"
if [ -f "$0" ]; then
  BUNDLE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
fi
TESTING_AGENT_ENDPOINT="app.testing.cetp-flexbit.eu:9092"
PRODUCTION_AGENT_ENDPOINT="app.cetp-flexbit.eu:9092"
DEFAULT_ENVIRONMENT="testing"
INSTALL_DIR="$(pwd)"
WITH_MQTT=0
WITH_HISTORY=0
WITH_MONITORING=0
START=1
ENVIRONMENT="${FLEXBIT_ENVIRONMENT:-}"
INSTALL_DIR_SET=0
MQTT_SET=0
HISTORY_SET=0
MONITORING_SET=0
START_SET=0
ENVIRONMENT_SET=0
WITH_SERVICE=0
SERVICE_SET=0
SERVICE_NAME="flexbit-local-adapter.service"
SERVICE_SUDO=""

RESET=''
BOLD_CYAN=''
BLUE=''
YELLOW=''
DIM=''
RED=''
GREEN=''
MAGENTA=''

usage() {
  cat <<EOF
Usage: install.sh [options]

Options:
  --with-docker           Run with Docker Compose (default)
  --without-docker        Run only the adapter using the standalone Linux ZIP
  --with-service          Install standalone adapter as a systemd service
  --without-service       Run standalone adapter in the foreground (default)
  --version VERSION       Release version (default: 1.0.0)
  --install-dir PATH      Installation directory (default: current directory)
  --with-mqtt             Enable the MQTT profile
  --with-history          Enable the history profile
  --with-monitoring       Enable the monitoring profile
  --environment NAME      FlexBIT environment: testing or production
  --no-start              Configure without starting the services
  -h, --help              Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-docker) USE_DOCKER=1; MODE_SET=1; shift ;;
    --without-docker) USE_DOCKER=0; MODE_SET=1; shift ;;
    --with-service) WITH_SERVICE=1; SERVICE_SET=1; shift ;;
    --without-service) WITH_SERVICE=0; SERVICE_SET=1; shift ;;
    --version) [ "$#" -ge 2 ] || { echo "--version requires a value" >&2; exit 2; }; VERSION="$2"; shift 2 ;;
    --install-dir) [ "$#" -ge 2 ] || { echo "--install-dir requires a value" >&2; exit 2; }; INSTALL_DIR="$2"; INSTALL_DIR_SET=1; shift 2 ;;
    --with-mqtt) WITH_MQTT=1; MQTT_SET=1; shift ;;
    --with-history) WITH_HISTORY=1; HISTORY_SET=1; shift ;;
    --with-monitoring) WITH_MONITORING=1; MONITORING_SET=1; shift ;;
    --environment) [ "$#" -ge 2 ] || { echo "--environment requires a value" >&2; exit 2; }; ENVIRONMENT="$2"; ENVIRONMENT_SET=1; shift 2 ;;
    --no-start) START=0; START_SET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

prompt_value() {
  label="$1"
  default="$2"
  printf '%s%s%s [%s%s%s]: ' "$BLUE" "$label" "$RESET" "$YELLOW" "$default" "$RESET" >&2
  IFS= read -r answer <&3 || answer=""
  [ -z "$answer" ] && answer="$default"
  printf '%s' "$answer"
}

prompt_required_value() {
  label="$1"
  default="$2"

  while :; do
    value="$(prompt_value "$label" "$default")"
    if [ -n "$value" ]; then
      printf '%s' "$value"
      return
    fi
    printf '%s%s is required.%s\n' "$RED" "$label" "$RESET" >&2
  done
}

prompt_yes_no() {
  label="$1"
  default="$2"
  description="$3"
  printf '  %s%s%s\n' "$DIM" "$description" "$RESET" >&2
  while :; do
    if [ "$default" -eq 1 ]; then hint='Y/n'; else hint='y/N'; fi
    printf '%s%s%s [%s%s%s]: ' "$BLUE" "$label" "$RESET" "$YELLOW" "$hint" "$RESET" >&2
    IFS= read -r answer <&3 || answer=""
    case "$answer" in
      '') printf '%s' "$default"; return ;;
      y|Y|yes|YES|Yes) printf '1'; return ;;
      n|N|no|NO|No) printf '0'; return ;;
      *) printf '%sPlease answer yes or no.%s\n' "$RED" "$RESET" >&2 ;;
    esac
  done
}

prompt_environment() {
  default="$1"

  while :; do
    printf '  %sSelects the FlexBIT app and agent endpoint used for credentials and telemetry.%s\n' "$DIM" "$RESET" >&2
    printf '%sFlexBIT environment%s [%s%s%s]: ' "$BLUE" "$RESET" "$YELLOW" "$default" "$RESET" >&2
    IFS= read -r answer <&3 || answer=""
    [ -z "$answer" ] && answer="$default"
    case "$answer" in
      testing|test) printf 'testing'; return ;;
      production|prod) printf 'production'; return ;;
      *) printf '%sPlease enter testing or production.%s\n' "$RED" "$RESET" >&2 ;;
    esac
  done
}

normalize_environment() {
  case "$1" in
    ''|testing|test) printf 'testing' ;;
    production|prod) printf 'production' ;;
    *) echo "FLEXBIT environment must be testing or production" >&2; exit 2 ;;
  esac
}

agent_endpoint_for_environment() {
  case "$1" in
    production) printf '%s' "$PRODUCTION_AGENT_ENDPOINT" ;;
    *) printf '%s' "$TESTING_AGENT_ENDPOINT" ;;
  esac
}

existing_value() {
  env_file="$INSTALL_DIR/.env"
  [ -f "$env_file" ] || return 0
  sed -n "s/^$1=//p" "$env_file" | tail -1
}

require_config_value() {
  key="$1"
  value="$2"

  if [ -z "$value" ]; then
    printf '%s%s is required.%s\n' "$RED" "$key" "$RESET" >&2
    printf '%sProvide it interactively, through the existing .env file, or as an environment variable.%s\n' "$YELLOW" "$RESET" >&2
    exit 1
  fi
}

print_credentials_notice() {
  agent_endpoint="${1:-$(agent_endpoint_for_environment "$DEFAULT_ENVIRONMENT")}"
  agent_host="$(printf '%s' "$agent_endpoint" | sed -e 's#^[[:alpha:]][[:alnum:].+-]*://##' -e 's#/.*$##' -e 's/:[0-9][0-9]*$//')"
  credentials_url="https://${agent_host}/connect-local-adapter"
  border='────────────────────────────────────────────────────────────────────'

  printf '\n%s╭%s╮%s\n' "$MAGENTA" "$border" "$RESET" >&2
  printf '%s│%s %-66s %s│%s\n' "$MAGENTA" "$BOLD_CYAN" "FlexBIT Local Adapter credentials" "$MAGENTA" "$RESET" >&2
  printf '%s│%s %-66s %s│%s\n' "$MAGENTA" "$RESET" "Open this page to get your Site ID, API ID, and API secret:" "$MAGENTA" "$RESET" >&2
  printf '%s│%s %-66s %s│%s\n' "$MAGENTA" "$BLUE" "$credentials_url" "$MAGENTA" "$RESET" >&2
  printf '%s╰%s╯%s\n' "$MAGENTA" "$border" "$RESET" >&2
}

print_recap() {
  adapter_port="${ADAPTER_PORT:-4000}"
  [ "$USE_DOCKER" -eq 1 ] || adapter_port="$(existing_value PORT)"
  ADAPTER_URL="http://127.0.0.1:${adapter_port:-4000}"

  MQTT_HOST="${MQTT_BIND_ADDRESS:-127.0.0.1}"
  [ "$MQTT_HOST" = "0.0.0.0" ] && MQTT_HOST="127.0.0.1"

  printf '\n%sSetup recap%s\n' "$BOLD_CYAN" "$RESET"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────────${RESET}"
  printf '%s%-22s %s%s\n' "$BOLD_CYAN" "Service" "Link / endpoint" "$RESET"
  printf '%s\n' "${DIM}────────────────────────────────────────────────────────────${RESET}"

  printf '%s%-22s%s %s\n' "$GREEN" "Adapter API/Dashboard" "$RESET" "${BLUE}${ADAPTER_URL}${RESET}"

  if [ "$WITH_MQTT" -eq 1 ]; then
    printf '%s%-22s%s %s\n' "$GREEN" "MQTT broker" "$RESET" "${BLUE}mqtt://${MQTT_HOST}:${MQTT_PORT:-1883}${RESET}"
  fi

  if [ "$WITH_HISTORY" -eq 1 ]; then
    printf '%s%-22s%s %s\n' "$GREEN" "QuestDB console" "$RESET" "${BLUE}http://127.0.0.1:${QUESTDB_HTTP_PORT:-9000}${RESET}"
  fi

  if [ "$WITH_MONITORING" -eq 1 ]; then
    printf '%s%-22s%s %s\n' "$GREEN" "Prometheus" "$RESET" "${BLUE}http://127.0.0.1:${PROMETHEUS_PORT:-9090}${RESET}"
    printf '%s%-22s%s %s\n' "$GREEN" "Grafana" "$RESET" "${BLUE}http://127.0.0.1:${GRAFANA_PORT:-3001}${RESET}"
  fi

  printf '%s\n' "${DIM}────────────────────────────────────────────────────────────${RESET}"
  printf '%s%-22s%s %s\n' "$MAGENTA" "Install directory" "$RESET" "${YELLOW}${INSTALL_DIR}${RESET}"
  if [ "$USE_DOCKER" -eq 1 ]; then
    printf '%s%-22s%s %s\n' "$MAGENTA" "Compose file" "$RESET" "${YELLOW}${INSTALL_DIR}/compose.yaml${RESET}"
  elif [ "$WITH_SERVICE" -eq 1 ]; then
    printf '%s%-22s%s %s\n' "$MAGENTA" "System service" "$RESET" "$SERVICE_NAME (enabled on boot)"
    for action in start stop restart status; do
      printf '%s%-22s%s %s\n' "$MAGENTA" "Service $action" "$RESET" "${SERVICE_SUDO:+sudo }systemctl $action $SERVICE_NAME"
    done
    printf '%s%-22s%s %s\n' "$MAGENTA" "Service logs" "$RESET" "${SERVICE_SUDO:+sudo }journalctl -u $SERVICE_NAME -f"
  fi
  printf '%s%-22s%s %s\n' "$MAGENTA" "Environment file" "$RESET" "${YELLOW}${INSTALL_DIR}/.env${RESET}"

  if [ "$START" -eq 1 ]; then
    status="Services started"
    [ "$USE_DOCKER" -eq 1 ] || status="Starting adapter in foreground"
    [ "$WITH_SERVICE" -eq 0 ] || status="System service started"
    printf '%s%-22s%s %s\n' "$GREEN" "Status" "$RESET" "${GREEN}${status}${RESET}"
  else
    printf '%s%-22s%s %s\n' "$YELLOW" "Status" "$RESET" "${YELLOW}Configured only, not started${RESET}"
    if [ "$WITH_SERVICE" -eq 1 ]; then
      printf '%s%-22s%s %s\n' "$MAGENTA" "Start command" "$RESET" "${BLUE}${START_COMMAND}${RESET}"
    else
      printf '%s%-22s%s %s\n' "$MAGENTA" "Start command" "$RESET" "${BLUE}cd $INSTALL_DIR && $START_COMMAND${RESET}"
    fi
  fi

  printf '%s\n' "${DIM}────────────────────────────────────────────────────────────${RESET}"
}

SITE_ID="${FLEXBIT_SITE_ID:-}"
API_ID="${FLEXBIT_API_ID:-}"
API_SECRET="${FLEXBIT_API_SECRET:-}"

# /dev/tty keeps prompts working when the installer itself is piped from curl.
if ( : </dev/tty ) 2>/dev/null; then
  exec 3</dev/tty
  if [ -z "${NO_COLOR:-}" ]; then
    ESC="$(printf '\033')"
    RESET="${ESC}[0m"
    BOLD_CYAN="${ESC}[1;36m"
    BLUE="${ESC}[34m"
    YELLOW="${ESC}[33m"
    DIM="${ESC}[2m"
    RED="${ESC}[31m"
    GREEN="${ESC}[32m"
    MAGENTA="${ESC}[35m"
  fi

  printf '%sFlexBIT Local Adapter installation%s\n\n' "$BOLD_CYAN" "$RESET" >&2

  [ "$INSTALL_DIR_SET" -eq 1 ] || INSTALL_DIR="$(prompt_value "Installation directory" "$INSTALL_DIR")"
  [ "$MODE_SET" -eq 1 ] || USE_DOCKER="$(prompt_yes_no "Run with Docker" 1 "Choose no to run only the adapter from a standalone Linux ZIP.")"
  if [ "$USE_DOCKER" -eq 1 ]; then
    [ "$MQTT_SET" -eq 1 ] || WITH_MQTT="$(prompt_yes_no "Enable MQTT" 0 "Accept telemetry from devices over MQTT.")"
    [ "$HISTORY_SET" -eq 1 ] || WITH_HISTORY="$(prompt_yes_no "Enable history" 0 "Store time-series telemetry in QuestDB.")"
    [ "$MONITORING_SET" -eq 1 ] || WITH_MONITORING="$(prompt_yes_no "Enable monitoring" 0 "Run Prometheus and Grafana for metrics and dashboards.")"
    start_description="Launch the selected Docker Compose services now."
  else
    [ "$SERVICE_SET" -eq 1 ] || WITH_SERVICE="$(prompt_yes_no "Install and manage as a system service" 0 "Use systemd to start on boot and restart after failures. Requires root or sudo.")"
    if [ "$WITH_SERVICE" -eq 1 ]; then
      start_description="Start the systemd service now in the background."
    else
      start_description="Run the adapter in the foreground. Press Ctrl-C to stop it."
    fi
  fi
  [ "$START_SET" -eq 1 ] || START="$(prompt_yes_no "Start after installation" 1 "$start_description")"

  [ -n "$ENVIRONMENT" ] || ENVIRONMENT="$(existing_value FLEXBIT_ENVIRONMENT)"
  ENVIRONMENT="$(normalize_environment "${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}")"
  [ "$ENVIRONMENT_SET" -eq 1 ] || ENVIRONMENT="$(prompt_environment "$ENVIRONMENT")"

  [ -n "$SITE_ID" ] || SITE_ID="$(existing_value FLEXBIT_SITE_ID)"
  [ -n "$API_ID" ] || API_ID="$(existing_value FLEXBIT_API_ID)"
  [ -n "$API_SECRET" ] || API_SECRET="$(existing_value FLEXBIT_API_SECRET)"
  [ -n "${FLEXBIT_AGENT_ENDPOINT:-}" ] || FLEXBIT_AGENT_ENDPOINT="$(existing_value FLEXBIT_AGENT_ENDPOINT)"

  AGENT_ENDPOINT="${FLEXBIT_AGENT_ENDPOINT:-$(agent_endpoint_for_environment "$ENVIRONMENT")}"

  print_credentials_notice "$AGENT_ENDPOINT"
  printf '\n%sFlexBIT API credentials%s\n' "$BOLD_CYAN" "$RESET" >&2
  SITE_ID="$(prompt_required_value "Site ID" "$SITE_ID")"
  API_ID="$(prompt_required_value "API ID" "$API_ID")"
  API_SECRET="$(prompt_required_value "API secret" "$API_SECRET")"

  exec 3<&-
else
  printf '%sNo terminal available; using defaults for options not provided.%s\n' "$YELLOW" "$RESET" >&2
fi

ENVIRONMENT="$(normalize_environment "${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}")"
AGENT_ENDPOINT="${FLEXBIT_AGENT_ENDPOINT:-$(agent_endpoint_for_environment "$ENVIRONMENT")}"

[ -n "$SITE_ID" ] || SITE_ID="$(existing_value FLEXBIT_SITE_ID)"
[ -n "$API_ID" ] || API_ID="$(existing_value FLEXBIT_API_ID)"
[ -n "$API_SECRET" ] || API_SECRET="$(existing_value FLEXBIT_API_SECRET)"
require_config_value FLEXBIT_SITE_ID "$SITE_ID"
require_config_value FLEXBIT_API_ID "$API_ID"
require_config_value FLEXBIT_API_SECRET "$API_SECRET"

if [ "$USE_DOCKER" -eq 1 ]; then
  [ "$WITH_SERVICE" -eq 0 ] || { echo "--with-service requires --without-docker" >&2; exit 2; }
  command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "docker compose is required" >&2; exit 1; }
  if [ "$(uname -s)" = "Darwin" ] && ! command -v mosquitto_pub >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      printf '%sInstalling Mosquitto client with Homebrew%s\n' "$MAGENTA" "$RESET"
      brew install mosquitto
    else
      printf '%smosquitto_pub is unavailable and Homebrew is not installed; MQTT demo scripts will not work.%s\n' "$YELLOW" "$RESET" >&2
    fi
  fi
else
  [ "$WITH_MQTT$WITH_HISTORY$WITH_MONITORING" = "000" ] || {
    echo "Optional service profiles require --with-docker. Configure external services in .env and config/ for standalone mode." >&2
    exit 2
  }
  [ "$(uname -s)" = "Linux" ] || { echo "Standalone packages support Linux only" >&2; exit 1; }
  case "$(uname -m)" in
    aarch64|arm64) ARCH=arm64 ;;
    x86_64|amd64) ARCH=amd64 ;;
    *) echo "Standalone packages require 64-bit ARM or AMD64 Linux" >&2; exit 1 ;;
  esac
  if [ "$WITH_SERVICE" -eq 1 ]; then
    command -v systemctl >/dev/null || { echo "System service installation requires systemd" >&2; exit 1; }
    if [ "$(id -u)" -ne 0 ]; then
      command -v sudo >/dev/null || { echo "System service installation requires root or sudo" >&2; exit 1; }
      SERVICE_SUDO="sudo"
      sudo -v
    fi
    # Fail before downloading or replacing files if systemd is not running.
    $SERVICE_SUDO systemctl show --property=Version --value >/dev/null
  fi
fi

IMAGE_REF="${IMAGE}:${VERSION}"
mkdir -p "$INSTALL_DIR"
INSTALL_DIR="$(CDPATH= cd -- "$INSTALL_DIR" && pwd)"

if [ "$USE_DOCKER" -eq 1 ]; then
printf '%sPulling %s%s\n' "$MAGENTA" "$IMAGE_REF" "$RESET"
docker pull "$IMAGE_REF"

# The image contains the small deployment bundle needed by Compose. Preserve
# operator-owned configuration while refreshing managed operational scripts.
docker run --rm \
  --entrypoint sh \
  -v "$INSTALL_DIR:/install" \
  "$IMAGE_REF" \
  -c '
    cp /opt/flexbit/compose.yaml /install/compose.yaml
    [ ! -f /opt/flexbit/LICENSE ] || cp /opt/flexbit/LICENSE /install/LICENSE
    rm -f /install/uninstall.sh
    rm -rf /install/scripts
    cp -R /opt/flexbit/scripts /install/scripts
    mkdir -p /install/config/mappings /install/deploy
    for file in /opt/flexbit/config/mappings/*.yaml; do
      target="/install/config/mappings/$(basename "$file")"
      [ -f "$target" ] || cp "$file" "$target"
    done
    for name in device-mappings.yaml command-targets.example.yaml; do
      [ -f "/install/config/$name" ] || cp "/opt/flexbit/config/$name" "/install/config/$name"
    done
    cp -R -a /opt/flexbit/deploy/. /install/deploy/
    chmod +x /install/scripts/*
  '

else
  if [ ! -f "$BUNDLE_DIR/.output/server/index.mjs" ] || [ ! -x "$BUNDLE_DIR/runtime/node" ]; then
    command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
    command -v unzip >/dev/null || { echo "unzip is required" >&2; exit 1; }
    command -v sha256sum >/dev/null || { echo "sha256sum is required" >&2; exit 1; }
    PACKAGE="local-adapter-${VERSION}-linux-${ARCH}.zip"
    TEMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
    printf 'Downloading %s\n' "$PACKAGE"
    curl -fSL "$RELEASE_URL/v$VERSION/$PACKAGE" -o "$TEMP_DIR/$PACKAGE"
    curl -fsSL "$RELEASE_URL/v$VERSION/SHA256SUMS" -o "$TEMP_DIR/SHA256SUMS"
    awk -v package="$PACKAGE" '$2 == package { print }' "$TEMP_DIR/SHA256SUMS" > "$TEMP_DIR/checksum"
    [ -s "$TEMP_DIR/checksum" ] || { echo "Package checksum is missing" >&2; exit 1; }
    (cd "$TEMP_DIR" && sha256sum -c checksum)
    unzip -q "$TEMP_DIR/$PACKAGE" -d "$TEMP_DIR/bundle"
    BUNDLE_DIR="$TEMP_DIR/bundle"
  fi
  "$BUNDLE_DIR/runtime/node" -e 'if (process.versions.node.split(".")[0] !== "24") process.exit(1)' || {
    echo "Cannot run bundled Node 24. Use the matching ZIP on Linux with glibc 2.28+ and libstdc++ installed." >&2
    exit 1
  }
  if [ "$BUNDLE_DIR" != "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR/.output" "$INSTALL_DIR/runtime"
    cp -R "$BUNDLE_DIR/.output" "$BUNDLE_DIR/runtime" "$INSTALL_DIR/"
    cp "$BUNDLE_DIR/start-adapter.sh" "$INSTALL_DIR/start-adapter.sh"
    cp "$BUNDLE_DIR/test-telemetry.sh" "$INSTALL_DIR/test-telemetry.sh"
    [ ! -f "$BUNDLE_DIR/LICENSE" ] || cp "$BUNDLE_DIR/LICENSE" "$INSTALL_DIR/LICENSE"
  fi
  chmod +x "$INSTALL_DIR/start-adapter.sh" "$INSTALL_DIR/test-telemetry.sh" "$INSTALL_DIR/runtime/node"
  mkdir -p "$INSTALL_DIR/config/mappings" "$INSTALL_DIR/data/adapter"
  for file in "$BUNDLE_DIR"/config/mappings/*.yaml "$BUNDLE_DIR"/config/*.yaml; do
    target="$INSTALL_DIR/config/$(basename "$file")"
    case "$file" in */mappings/*) target="$INSTALL_DIR/config/mappings/$(basename "$file")" ;; esac
    [ -f "$target" ] || cp "$file" "$target"
  done
  [ -f "$INSTALL_DIR/config/mqtt.yaml" ] || printf '[]\n' > "$INSTALL_DIR/config/mqtt.yaml"
fi

cd "$INSTALL_DIR"

localize_storage() {
  awk '
    $0 == "      - adapter_data:/data" { print "      - ./data/adapter:/data"; next }
    $0 == "      - questdb_data:/var/lib/questdb" { print "      - ./data/questdb:/var/lib/questdb"; next }
    $0 == "      - grafana_data:/var/lib/grafana" { print "      - ./data/grafana:/var/lib/grafana"; next }
    $0 == "volumes:" { exit }
    { print }
  ' compose.yaml > compose.yaml.tmp
  mv compose.yaml.tmp compose.yaml
  mkdir -p data/adapter data/questdb data/grafana
  chmod 0777 data/adapter data/questdb data/grafana
}

prepare_deploy_file() {
  path="$1"
  if [ -d "$path" ]; then
    rmdir "$path" || {
      echo "Cannot replace non-empty directory $path with the required file" >&2
      exit 1
    }
  fi
  mkdir -p "$(dirname "$path")"
}

if [ "$USE_DOCKER" -eq 1 ]; then
localize_storage

if [ ! -f deploy/prometheus/prometheus.yml ]; then
  prepare_deploy_file deploy/prometheus/prometheus.yml
  cat > deploy/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: flexbit-local-adapter
    static_configs:
      - targets: ["adapter:4000"]
    metrics_path: /metrics
EOF
fi

if [ ! -f deploy/mosquitto/mosquitto.conf ]; then
  prepare_deploy_file deploy/mosquitto/mosquitto.conf
  cat > deploy/mosquitto/mosquitto.conf <<'EOF'
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
EOF
fi

fi

ENV_FILE=.env
touch "$ENV_FILE"

get_value() {
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -1
}

set_missing() {
  [ -n "$(get_value "$1")" ] || printf '%s=%s\n' "$1" "$2" >> "$ENV_FILE"
}

set_value() {
  awk -v key="$1" -v value="$2" '
    BEGIN { found = 0 }
    $0 ~ "^" key "=" { if (!found) print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$ENV_FILE" > "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
}

write_default_mqtt_config() {
  cat > config/mqtt.yaml <<'EOF'
- id: local
  url: mqtt://mosquitto:1883
  clientId: flexbit-local-adapter
  subscriptions:
    - { topic: devices/bess/telemetry, mappingId: demo-bess, qos: 1, retained: ignore }
    - { topic: devices/ev-charger/telemetry, mappingId: demo-ev-charger, qos: 1, retained: ignore }
    - { topic: devices/pv/telemetry, mappingId: demo-pv, qos: 1, retained: ignore }
EOF
}

[ -n "$SITE_ID" ] || SITE_ID="$(get_value FLEXBIT_SITE_ID)"
[ -n "$API_ID" ] || API_ID="$(get_value FLEXBIT_API_ID)"
[ -n "$API_SECRET" ] || API_SECRET="$(get_value FLEXBIT_API_SECRET)"

require_config_value FLEXBIT_SITE_ID "$SITE_ID"
require_config_value FLEXBIT_API_ID "$API_ID"
require_config_value FLEXBIT_API_SECRET "$API_SECRET"

if [ "$USE_DOCKER" -eq 1 ]; then
  set_value FLEXBIT_ADAPTER_IMAGE "$IMAGE_REF"
else
  set_missing HOST 127.0.0.1
  set_missing PORT "${ADAPTER_PORT:-4000}"
  set_value FLEXBIT_DATABASE_PATH data/adapter/adapter.db
  set_value FLEXBIT_MAPPING_PATHS config/mappings
  set_value FLEXBIT_DEVICE_MAPPINGS_PATH config/device-mappings.yaml
  set_value FLEXBIT_MQTT_CONNECTIONS_PATH config/mqtt.yaml
  set_value FLEXBIT_COMMAND_TARGETS_PATH config/command-targets.yaml
fi
set_missing FLEXBIT_ENVIRONMENT "$ENVIRONMENT"
set_missing FLEXBIT_AGENT_ENDPOINT "$AGENT_ENDPOINT"
set_value FLEXBIT_SITE_ID "$SITE_ID"
set_missing FLEXBIT_CLIENT_ID "${FLEXBIT_CLIENT_ID:-flexbit-adapter}"
set_value FLEXBIT_API_ID "$API_ID"
set_value FLEXBIT_API_SECRET "$API_SECRET"

if [ "$WITH_MQTT" -eq 1 ]; then
  if [ ! -f config/mqtt.yaml ]; then
    if [ -f config/mqtt.example.yaml ]; then
      cp config/mqtt.example.yaml config/mqtt.yaml
    else
      write_default_mqtt_config
    fi
  fi
fi

chmod 600 "$ENV_FILE"

PROFILES=""
[ "$WITH_MQTT" -eq 0 ] || PROFILES="$PROFILES --profile mqtt"
[ "$WITH_HISTORY" -eq 0 ] || { PROFILES="$PROFILES --profile history"; set_missing QUESTDB_HTTP_URL http://questdb:9000; }
[ "$WITH_MONITORING" -eq 0 ] || PROFILES="$PROFILES --profile monitoring"

START_COMMAND="./start-adapter.sh"
if [ "$USE_DOCKER" -eq 1 ]; then
  START_COMMAND="docker compose$PROFILES up -d"
  docker compose config --quiet
  [ "$START" -eq 0 ] || sh -c "$START_COMMAND"
elif [ "$WITH_SERVICE" -eq 1 ]; then
  # WorkingDirectory is a literal path, while ExecStart uses quoted arguments.
  # Escape specifiers in both and preserve literal dollars in ExecStart.
  case "$INSTALL_DIR" in
    *'
'*) echo "System service installation paths cannot contain newlines" >&2; exit 1 ;;
  esac
  unit_directory="$(printf '%s' "$INSTALL_DIR" | sed 's/%/%%/g')"
  unit_launcher="$(printf '%s' "$unit_directory/start-adapter.sh" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/$$/g')"
  # A final slash prevents a literal trailing backslash becoming a continuation.
  cat > "$SERVICE_NAME" <<EOF
[Unit]
Description=FlexBIT Local Adapter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$(id -un)
WorkingDirectory=$unit_directory/
ExecStart=/bin/sh "$unit_launcher"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  $SERVICE_SUDO install -m 644 "$SERVICE_NAME" "/etc/systemd/system/$SERVICE_NAME"
  $SERVICE_SUDO systemctl daemon-reload
  $SERVICE_SUDO systemctl enable "$SERVICE_NAME"
  START_COMMAND="${SERVICE_SUDO:+sudo }systemctl start $SERVICE_NAME"
  [ "$START" -eq 0 ] || $SERVICE_SUDO systemctl restart "$SERVICE_NAME"
fi

printf '%sFlexBIT Local Adapter configured in %s%s\n' "$GREEN" "$INSTALL_DIR" "$RESET"
print_recap

if [ -n "${TEMP_DIR:-}" ]; then
  rm -rf "$TEMP_DIR"
  trap - EXIT HUP INT TERM
fi

if [ "$USE_DOCKER" -eq 0 ] && [ "$WITH_SERVICE" -eq 0 ] && [ "$START" -eq 1 ]; then
  printf 'Starting the adapter in the foreground. Press Ctrl-C to stop.\n'
  exec ./start-adapter.sh
fi
