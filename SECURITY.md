# Security

## Deployment boundaries

This adapter is intended for local, trusted deployments. The operator UI, RPC
API, HTTP intake, and command endpoints do not authenticate callers. Anyone who
can reach them can read telemetry and change configuration. Keep the adapter on
loopback or behind a firewall and an authenticated proxy.

The Compose files publish the adapter and MQTT broker on loopback by default.
An `ADAPTER_PORT` value such as `4000` publishes the adapter on all host interfaces;
use `127.0.0.1:4000` to restrict it. Check existing `.env` values when upgrading.
The example Mosquitto broker permits anonymous access. Configure authentication
and TLS before allowing remote clients.

FlexBIT API secrets can be stored in `.env` and in the local SQLite settings.
MQTT passwords are stored in connection YAML. Restrict access to configuration,
database files, and backups. Treat telemetry as potentially private data.

TLS certificate verification uses Node's defaults. For a private certificate
authority, configure `NODE_EXTRA_CA_CERTS` with its PEM certificate and make the
file available to the process or container.

## Reporting a vulnerability

Use the repository's GitHub **Security > Report a vulnerability** form when
private vulnerability reporting is enabled. If it is unavailable, ask maintainers
for a private contact channel without posting exploit details or credentials in
a public issue.

Include the affected revision, deployment mode, reproduction steps, and impact.
Security fixes target the current development branch. No response-time commitment
or backport policy is currently defined.
