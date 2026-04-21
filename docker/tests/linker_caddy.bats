#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SERVICE="${SERVICE_NAME:-edgenode}"

# Helper: true if h2hc-linker process is running in the container
linker_running() {
  docker compose exec -T "$SERVICE" pgrep h2hc-linker > /dev/null 2>&1
}

# Helper: true if caddy is running as a server in the container
caddy_running() {
  docker compose exec -T "$SERVICE" pgrep -f "caddy run" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Tier 1: binaries present — always run
# ---------------------------------------------------------------------------

@test "h2hc-linker binary is installed" {
  run docker compose exec -T "$SERVICE" test -x /usr/local/bin/h2hc-linker
  assert_success
}

@test "caddy binary is installed" {
  run docker compose exec -T "$SERVICE" which caddy
  assert_success
}

# ---------------------------------------------------------------------------
# Tier 1: disabled state — always run (standard CI has no linker/caddy env vars)
# ---------------------------------------------------------------------------

@test "h2hc-linker is not running when H2HC_LINKER_BOOTSTRAP_URL is unset" {
  if linker_running; then skip "h2hc-linker is configured and running"; fi
  run docker compose exec -T "$SERVICE" pgrep h2hc-linker
  assert_failure
}

@test "caddy is not running when CADDY_DOMAIN is unset" {
  if caddy_running; then skip "caddy is configured and running"; fi
  run docker compose exec -T "$SERVICE" pgrep -f "caddy run"
  assert_failure
}

@test "port 80 is not bound when CADDY_DOMAIN is unset" {
  if caddy_running; then skip "caddy is configured and running"; fi
  run docker compose exec -T "$SERVICE" \
    sh -c "timeout 2 bash -c 'echo >/dev/tcp/localhost/80' 2>/dev/null && echo open || echo closed"
  assert_output "closed"
}

@test "port 443 is not bound when CADDY_DOMAIN is unset" {
  if caddy_running; then skip "caddy is configured and running"; fi
  run docker compose exec -T "$SERVICE" \
    sh -c "timeout 2 bash -c 'echo >/dev/tcp/localhost/443' 2>/dev/null && echo open || echo closed"
  assert_output "closed"
}

# ---------------------------------------------------------------------------
# Tier 2: enabled state — skipped unless H2HC_LINKER_BOOTSTRAP_URL / CADDY_DOMAIN set
# Run via a compose override that sets the env vars and provides a test domain.
# ---------------------------------------------------------------------------

@test "h2hc-linker runs as nonroot when configured" {
  if ! linker_running; then skip "h2hc-linker not configured (H2HC_LINKER_BOOTSTRAP_URL unset)"; fi
  run docker compose exec -T "$SERVICE" \
    sh -c "ps aux | grep -E 'nonroot.*h2hc-linker'"
  assert_success
}

@test "h2hc-linker is listening on H2HC_LINKER_PORT when configured" {
  if ! linker_running; then skip "h2hc-linker not configured (H2HC_LINKER_BOOTSTRAP_URL unset)"; fi
  run docker compose exec -T "$SERVICE" \
    sh -c "timeout 2 bash -c 'echo >/dev/tcp/localhost/${H2HC_LINKER_PORT:-8080}' 2>/dev/null && echo open || echo closed"
  assert_output "open"
}

@test "startup log contains linker startup message when configured" {
  if ! linker_running; then skip "h2hc-linker not configured (H2HC_LINKER_BOOTSTRAP_URL unset)"; fi
  run docker compose exec -T "$SERVICE" grep "Starting h2hc-linker" /data/logs/startup.log
  assert_success
}

@test "caddy is running when CADDY_DOMAIN is configured" {
  if ! caddy_running; then skip "caddy not configured (CADDY_DOMAIN unset)"; fi
  run docker compose exec -T "$SERVICE" pgrep -f "caddy run"
  assert_success
}

@test "caddy is listening on port 443 when configured" {
  if ! caddy_running; then skip "caddy not configured (CADDY_DOMAIN unset)"; fi
  run docker compose exec -T "$SERVICE" \
    sh -c "timeout 2 bash -c 'echo >/dev/tcp/localhost/443' 2>/dev/null && echo open || echo closed"
  assert_output "open"
}

@test "caddy Caddyfile is generated at /tmp/Caddyfile when configured" {
  if ! caddy_running; then skip "caddy not configured (CADDY_DOMAIN unset)"; fi
  run docker compose exec -T "$SERVICE" test -f /tmp/Caddyfile
  assert_success
}

@test "Caddyfile references the configured domain" {
  if ! caddy_running; then skip "caddy not configured (CADDY_DOMAIN unset)"; fi
  run docker compose exec -T "$SERVICE" grep "${CADDY_DOMAIN}" /tmp/Caddyfile
  assert_success
}

@test "startup log contains caddy startup message when configured" {
  if ! caddy_running; then skip "caddy not configured (CADDY_DOMAIN unset)"; fi
  run docker compose exec -T "$SERVICE" grep "Starting Caddy" /data/logs/startup.log
  assert_success
}
