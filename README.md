# FlexBIT Local Adapter

FlexBIT Local Adapter receives device telemetry over HTTP or MQTT, stores accepted events in a local SQLite database, maps device payloads to FlexBIT asset fields, and publishes mapped telemetry to FlexBIT.

## Docs

The documentation is available at [https://cetp-flexbit.github.io/local-adapter/](https://cetp-flexbit.github.io/local-adapter/)

The installation, configuration, and testing guide is also available as [Word](docs/guides/local-adapter-guide.docx), [PDF](docs/guides/local-adapter-guide.pdf), and [Markdown](docs/guides/local-adapter-guide.md).

## Requirements

- Docker mode: a host with Docker Engine and the Docker Compose plugin
- Standalone mode: 64-bit Linux on ARM64 or AMD64, glibc 2.28 or newer, and libstdc++ 6.0.25 or newer. A Raspberry Pi needs a 64-bit OS. Alpine Linux and 32-bit Raspberry Pi OS are not supported.
- Standalone downloads need `curl`, `unzip`, and `sha256sum`. Node 24 is included in the ZIP.
- Network access to GitHub, and to `ghcr.io` for Docker mode
- A FlexBIT site ID, API ID, API secret, and agent endpoint to publish telemetry

## Install

Run the installer from a terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/CETP-FlexBIT/local-adapter/main/install.sh | sh
```

The installer asks whether to use Docker. Choose no to download the matching standalone ZIP and run only the adapter. Optional MQTT, history, and monitoring services require Docker mode; standalone installations can connect to separately managed services through `config/mqtt.yaml` and `QUESTDB_HTTP_URL` in `.env`.

For an unattended standalone installation, export your FlexBIT credentials first, then run:

```sh
sh install.sh --without-docker --install-dir "$HOME/flexbit-local-adapter" --no-start
cd "$HOME/flexbit-local-adapter"
./start-adapter.sh
```

You can also download `local-adapter-1.0.4-linux-arm64.zip` or `local-adapter-1.0.4-linux-amd64.zip` from [GitHub Releases](https://github.com/CETP-FlexBIT/local-adapter/releases/tag/v1.0.4), extract it, and run its `install.sh --without-docker`. Downloaded packages are verified against the release's `SHA256SUMS`. The ZIP includes `.output`, Node, default mappings, the installer, `start-adapter.sh`, `test-telemetry.sh`, and `flexbit-adapter`; no dependency installation or build is needed on the host.

Use `--with-docker` or `--without-docker` to select the mode without a prompt, and `--version X.Y.Z` to select a release when downloading. Without a terminal, Docker remains the default.

## Configure FlexBIT

During installation, choose the FlexBIT environment, then enter the site ID, API ID, and API secret when prompted. Existing values from `.env` or exported environment variables are offered as defaults; leaving the secret blank during a reinstall keeps its current value.

After installation, open `http://127.0.0.1:4000/settings` on the host to review or change:

- Site ID
- Client ID
- Agent endpoint
- API ID
- API secret

Settings saved in the UI are stored in SQLite and override corresponding `.env` values. The publisher is disabled until the agent endpoint, API ID, and API secret are set. A site ID is also required for a valid FlexBIT destination topic.

Under **Local data**, the optional **Send interval in seconds** limits telemetry sending independently for each device ID. Leave it empty to send every record, which is the default. With an interval set, the first record is queued for delivery, records received within the interval are retained with a grey **Skipped** badge, and the next record received at or after the interval is queued. The interval uses arrival times and persists across restarts. All raw and mapped records remain subject to retention, and skipped records are never sent later. Changes apply to newly mapped records; already queued deliveries keep their retry behavior. To set a deployment default, use `FLEXBIT_SEND_INTERVAL_SECONDS`.

Before sending, mapped telemetry is checked against the Zod schemas copied into `adapter/packages/schemas`. Invalid UUIDs, field types, enum values, ranges, unknown fields, and unsupported asset types block sending. Invalid records remain queued under the existing retry policy, with the validation error saved in delivery history. Expand a record on the Events page to see the current schema validation result and individual field errors in its right panel. This check also runs for older and skipped records and does not indicate whether they were previously sent.

The publisher client ID defaults to `flexbit-adapter`. Export `FLEXBIT_CLIENT_ID` before running the installer to override it.

The installer writes `.env` with mode `0600`. Keep that file private.

## Manage the adapter from a terminal

Downloads include a `flexbit-adapter` executable command. Installation and update copy it into the installation directory and link it from `/usr/local/bin`, using sudo when that directory requires it. Use `--bin-dir "$HOME/.local/bin"` with the installer for a user-local command directory; add that directory to `PATH` if needed. The chosen directory is remembered for updates.

```sh
flexbit-adapter help
flexbit-adapter start
flexbit-adapter stop
flexbit-adapter restart
flexbit-adapter status
flexbit-adapter update
flexbit-adapter uninstall
```

The command works from any directory. Systemd installations use their existing `flexbit-local-adapter.service` unit. Docker actions target only the adapter; optional services keep running. Uninstall disables and removes the systemd service, or removes the adapter container, while keeping credentials, configuration, data, and the management command.

For a standalone foreground installation, `flexbit-adapter start` runs the existing launcher. Stop it with Ctrl-C. Choose `--with-service` during installation for background start/stop control. `-h` and `--help` also display command help.

## Start and inspect

Standalone mode binds to `127.0.0.1:4000` by default. Set `HOST` and `PORT` in `.env` to change this. `./start-adapter.sh` runs in the foreground and stops with Ctrl-C.

The standalone installer asks whether to install and manage the adapter as a system service. Choose yes, or pass `--with-service`, to install `flexbit-local-adapter.service` with systemd, enable startup on boot, and restart after failures. This requires systemd and root or sudo access. The service runs as the user running the installer.

Use `--without-service` to keep foreground mode; unattended installations default to foreground mode. `--no-start` enables the service on boot without starting it now. The setup recap prints commands to start, stop, restart, inspect, and view service logs. For example:

```sh
sudo systemctl status flexbit-local-adapter.service
sudo systemctl restart flexbit-local-adapter.service
sudo journalctl -u flexbit-local-adapter.service -f
```

For Docker mode:

```sh
cd /path/to/adapter/installation
docker compose up -d
docker compose logs -f adapter
```

When optional services are needed, include their profiles:

```sh
docker compose --profile mqtt --profile history --profile monitoring up -d
```

Profile selection is not saved by the installer. Include the required `--profile` flags when recreating those services.

Default local endpoints:

| Service | Address |
| --- | --- |
| Adapter UI and API | `http://127.0.0.1:4000` |
| QuestDB (history profile) | `http://127.0.0.1:9000` |
| Prometheus (monitoring profile) | `http://127.0.0.1:9090` |
| Grafana (monitoring profile) | `http://127.0.0.1:3001` |
| Mosquitto (MQTT profile) | `mqtt://127.0.0.1:1883` |

The adapter exposes `/healthz`, `/readyz`, `/v1/status`, and `/metrics`. Telemetry can be submitted as a JSON object to `POST /v1/ingest`; use the `X-Mapping-Id` header to choose a configured mapping. The current HTTP intake route does not authenticate requests. To restrict an installed Docker deployment to loopback, set `ADAPTER_PORT=127.0.0.1:4000` in `.env` before starting it.

Use the installed telemetry helper to submit sample BESS, EV charger, or PV telemetry. Specify `rest` when no MQTT broker is configured; with no arguments the helper tries both transports. Run it in a second terminal while the adapter is running:

```sh
# Docker installation
./scripts/test-telemetry.sh rest pv
./scripts/test-telemetry.sh mqtt ev-charger

# Standalone installation
./test-telemetry.sh rest bess
./test-telemetry.sh rest pv
# Requires a separately managed broker and adapter subscriptions
MQTT_HOST=127.0.0.1 ./test-telemetry.sh mqtt ev-charger
```

Set `ADAPTER_URL=http://127.0.0.1:5050` for a custom HTTP port, or `MQTT_HOST` and `MQTT_PORT` for an external broker. The helper does not load `.env`; export overrides explicitly. HTTP acceptance and MQTT acknowledgement confirm intake or broker delivery, respectively. Check the Events page and FlexBIT destination to confirm mapping and publication. Map the demo device IDs to assets belonging to your site before testing publication.

On macOS, the installer uses Homebrew to install Mosquitto when `mosquitto_pub` is missing and `brew` is available.

## Installed files and data

Docker installations contain:

- `.env`: Compose settings and FlexBIT connection defaults
- `compose.yaml`: deployment definition copied from the image
- `config/`: mappings, device IDs, MQTT connections, and command targets (all YAML)
- `deploy/`: Mosquitto, Prometheus, and Grafana configuration
- `scripts/`: operational helper scripts and `uninstall.sh` shipped with the image
- `data/adapter/`: SQLite database files
- `data/questdb/`: QuestDB data when history is enabled
- `data/grafana/`: Grafana data when monitoring is enabled

Runtime data uses bind-mounted directories under `data/`, not Docker named volumes. The `config/` directory is also mounted into the adapter, and changes made in the operator UI are persisted there. The installer creates the data directories with mode `0777` so the containers can write to them; restrict access at the host or filesystem layer as appropriate for the deployment.

Standalone installations contain `.env`, `.output/`, `runtime/`, `config/`, `start-adapter.sh`, `test-telemetry.sh`, `flexbit-adapter`, and `data/adapter/`. Reinstalling preserves `.env`, configuration, and SQLite data while replacing the application, bundled runtime, and managed commands. Stop the adapter before replacing a running installation. Keep Docker and standalone installations in separate directories.

## Update an existing installation

Run `flexbit-adapter update` to download and install the latest published version while preserving configuration and data.

For older installations without this command, download the current installer and run its update mode:

```sh
cd ~/flexbit-local-adapter
curl -fsSL https://raw.githubusercontent.com/CETP-FlexBIT/local-adapter/main/install.sh -o update-installer.sh
sh ./update-installer.sh --update
```

Updates use the latest published release by default. To choose a specific release, add `--version X.Y.Z`. Use `--install-dir /path/to/installation` when running from another directory. The updater detects Docker or standalone mode and does not ask for credentials again. It preserves `.env`, `config/`, `deploy/`, and `data/`, including settings saved through the UI. Docker updates change only `FLEXBIT_ADAPTER_IMAGE` in `.env`.

Docker updates pull the selected image and recreate only the adapter, leaving optional services running. Standalone updates always download the selected Linux ZIP, verify its checksum and bundled Node runtime, then replace the application, runtime, launcher, and telemetry helper. A systemd installation stops and restarts its existing service without replacing the unit. Stop a foreground adapter with Ctrl-C before updating; it starts again in the foreground when the update finishes.

Add `--no-start` to leave a standalone service stopped after replacing its files, or to update Docker's configured image without recreating the running container. The recap prints the command to start the updated adapter. Keep using `--update` for future upgrades, so an old bundled application is never reused.

## Build and publish releases

The `Release adapter` GitHub Action runs manually from the private repository. Select **Run workflow** and enter a version such as `1.0.4` without the `v` prefix. All authored workflows run manually in the private repository. Public Pages serves the generated `gh-pages` branch; no workflow files are exported to the public repository. It tests both Linux ZIPs, pushes `ghcr.io/cetp-flexbit/local-adapter:X.Y.Z` for `linux/amd64` and `linux/arm64`, then attaches the ZIPs, `SHA256SUMS`, and versioned installer to the GitHub release. Builds and tests run in the private `nextmultiservice/local-adapter` repository. Documentation and installer changes are maintained there and exported to this public repository. Releases and the GHCR package remain public at the existing URLs. Maintainers configure cross-repository publishing credentials in the private repository; set the GHCR package visibility to public for unauthenticated installer pulls.

With access to the private source repository, build and push the image from its root:

```sh
docker buildx build --platform linux/amd64,linux/arm64 \
  --target runtime -f adapter/Dockerfile \
  -t ghcr.io/cetp-flexbit/local-adapter:1.0.4 --push .
```

To export a standalone bundle locally:

```sh
docker buildx build --platform linux/arm64 --target standalone \
  -f adapter/Dockerfile --output type=local,dest=./bundle .
```

## Uninstall

For standalone mode, stop the foreground process. For an installed systemd service, run `sudo systemctl disable --now flexbit-local-adapter.service`, remove `/etc/systemd/system/flexbit-local-adapter.service`, and run `sudo systemctl daemon-reload`. Remove the installation directory only if you also want to delete its configuration and data.

To stop every installed profile without deleting bind-mounted data:

```sh
~/flexbit-local-adapter/scripts/uninstall.sh
```

## Operational notes

The adapter, its Compose healthcheck, and the bundled Prometheus scrape target all use container port 4000. When reinstalling over an older deployment, files under `deploy/` are preserved; verify that an existing `deploy/prometheus/prometheus.yml` targets `adapter:4000`.

The backup, restore, and reset helpers support the development Compose named-volume layout. They refuse installed deployments that use bind-mounted `data/` directories. For a file-based backup, stop the services and copy `.env`, `config/`, and `data/` from the installation directory before starting the services again.

The bundled Mosquitto configuration allows anonymous clients. Compose publishes its port on loopback by default. Set `MQTT_BIND_ADDRESS` to the required interface when remote devices need direct access, and configure broker authentication before exposing it on an untrusted network.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup and validation commands.
The adapter uses Node 24 and Vite+; the documentation is a separate Next.js project.

The operator UI, RPC API, and command routes have no built-in authentication.
Use them on a trusted network or behind an authenticated proxy. See
[SECURITY.md](SECURITY.md) for deployment boundaries and vulnerability reporting.

## License

Licensed under [Apache-2.0](LICENSE).
