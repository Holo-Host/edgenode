# High Availability Proposal for Holochain "Always On Nodes"

## Executive Summary
This proposal addresses the need for robust process supervision and automatic restarts of the `holochain` process to support "Always On Nodes" for Holochain hApps. The solutions are designed to work out-of-the-box without requiring additional configuration from the hoster deploying the container. We target two scenarios:

1. **Docker Deployments**: The most common runtime, using Docker's ecosystem.
2. **HolOS ISO Deployments**: Custom Buildroot-based OS using runc as the OCI runtime, with OpenRC init.

Current setup analysis reveals that tini (used in Docker entrypoint) does not provide restarts on crash—it exits the container on child failure, relying on external orchestration. For HA, we integrate lightweight internal supervisors to ensure the `holochain` process auto-restarts within the container, providing resilience against crashes while maintaining a clean state.

Key principles:
- **Fail-fast but Recover**: Restart on crash (non-zero exit), but limit retries to avoid infinite loops (e.g., max 5 attempts with exponential backoff).
- **Minimal Overhead**: Use lightweight tools compatible with the project's minimalistic design (Wolfi base for Docker, Buildroot for HolOS).
- **Out-of-the-Box**: Bake supervision into the image/OS build; no runtime flags or host changes needed.
- **Testing**: Include unit/integration tests for crash simulation and restart verification.

## Current Setup Analysis
### Docker (from `docker/Dockerfile` and `docker/entrypoint.sh`)
- **Base Image**: Chainguard Wolfi (minimal, secure Alpine-like distro).
- **Key Components**:
  - Installs `tini`, `holochain` (v0.5.6 binary), `hc`, `lair-keystore`.
  - Copies `happ_tool`, `happ_config_file` (new binary for hApp config generation/validation), `entrypoint.sh`, config templates, logrotate.
  - ENTRYPOINT: `/usr/local/bin/entrypoint.sh`.
- **Entrypoint Logic**:
  - Sets up persistent dirs (`/data`), symlinks, ownership (nonroot user).
  - Validates conductor config (port 4444, lair_server_in_proc keystore).
  - Runs background logrotate cron.
  - If `CONDUCTOR_MODE=false`: `tini -- tail -f /dev/null` (keeps container alive).
  - If `CONDUCTOR_MODE=true` (default implied): `tini -- gosu nonroot yes '' | holochain --piped --config-path /etc/holochain/conductor-config.yaml | tee /data/logs/holochain.log 2>&1`.
  - Enhanced testing via `test_default_conductor.sh` for conductor mode validation.
- **HA Gaps**:
  - Tini acts as PID 1 for zombie reaping/signals but does not restart `holochain` on crash/exit.
  - The pipe (`yes | holochain | tee`) keeps stdin open but fails the container on `holochain` crash.
  - No internal supervision; relies on external Docker restart policies (e.g., `--restart=on-failure`), which require hoster config—not out-of-the-box.
  - Logs are captured, but restarts would lose state unless persisted (already using `/data` VOLUME).
  - New `happ_config_file` tool may require integration for config setup in supervised runs.

### HolOS (from `holos/` files)
- **Build System**: Buildroot 2025.08 with custom config (`holos-buildroot-2025.08.config`); uses OpenRC skeleton for init. Enables runc and openrc-supervise-daemon packages.
- **Kernel/Boot**: Custom kernel (`kernel-config-x86_64.config`), hybrid ISO with isolinux.cfg (updated for boot menu); boots to minimal userspace. Makefile integrates holos-config tool build.
- **Init System**: OpenRC; overlay includes `/etc/init.d/S05platform` script and new boot init scripts:
  - S05platform: Loads platform drivers (PCI/USB via modprobe from sysfs uevents).
  - S06holos-config: Runs `holos-config` Rust tool for hardware/platform-specific setup (e.g., generates configs from YAML contrib files for Holoport/Dell XPS13).
  - S70interfaces: Configures networking (e.g., DHCP/static IPs via /etc/conf.d/net).
  - S75ssh-keys: Sets up SSH authorized_keys from GitHub users.
  - S77etc-issue: Generates MOTD (/etc/issue) with version, IPs, trusted users.
  - Supports start/stop/restart but no container-specific logic yet.
- **Container Management**: runc (OCI runtime, now explicitly enabled); holos-config tool aids boot configs (e.g., network/SSH). Overlay focuses on hardware/platform setup, not app-level HA.
- **HA Gaps**:
  - No built-in service for running/supervising runc containers.
  - OpenRC can manage services, but `holochain` container launch/restart needs a custom service script with dependencies on new init scripts (e.g., after networking/SSH).
  - Runs in RAM (no persistent storage yet); supervision must handle ephemeral restarts.
  - No current integration with runc exec or bundle management for auto-restart; holos-config outputs may need supervision if service-like.

## Proposed Solutions
### 1. Docker HA Solution: Integrate s6-overlay for Internal Supervision
**Rationale**: s6-overlay is lightweight (~1-2MB), designed for containers, and provides PID 1 init with automatic restarts. It replaces tini for supervision while retaining signal handling/zombie reaping. Out-of-the-box: Bake into Dockerfile; `holochain` auto-restarts on crash without Docker flags.

**High-Level Design**:
- Layer s6-overlay on Wolfi base.
- Define s6 service for `holochain` with `restart-policy = yes` (auto-restart on exit !=0, max retries=5, backoff).
- Modify entrypoint to use s6's `/init` as PID 1, launching `holochain` as supervised service.
- Preserve current logic (dirs, validation, logging) in a wrapper script; integrate `happ_config_file` if needed for hApp config generation/validation during startup.

**Pros**:
- Zero host config; works with plain `docker run`.
- Handles multi-process (e.g., logrotate + holochain + happ_config_file).
- Integrates with existing piping/logging.

**Cons**:
- Adds minor build complexity (multi-stage Dockerfile for s6).
- Overkill if external orchestration is always used, but ensures standalone HA.

### 2. HolOS/runc HA Solution: Add OpenRC Service for Supervised Runc Container
**Rationale**: OpenRC supports `supervise-daemon` for auto-restarts (now enabled in Buildroot). Create a custom OpenRC service (`/etc/init.d/holochain-container`, e.g., S90 in boot order) that launches the runc container bundle and supervises it. Enable at boot via OpenRC defaults. Out-of-the-box: Include in Buildroot overlay; auto-starts on HolOS boot after new init scripts.

**High-Level Design**:
- Assume runc bundle in `/opt/holochain-bundle` (pre-built with config, binaries from Docker image; use holos-config to generate platform-specific configs from YAML contrib files).
- Service script: Uses `runc run` to start container; `supervise-daemon` wraps for restarts (extra_commands for stop/kill).
- Set dependencies: `depend() { need net S70interfaces S75ssh-keys; after S06holos-config S77etc-issue; }`.
- Persist state via tmpfs mounts or future disk support; integrate holos-config outputs (e.g., network/SSH) for bundle prep in Makefile/overlay.

**Pros**:
- Leverages OpenRC's dependency management (e.g., after new boot scripts for hardware/net/SSH).
- Minimal footprint; no full supervisor like systemd.
- Ensures HA from OS boot, ideal for dedicated HolOS hardware; aligns with holos-config for platform setups.

**Cons**:
- Requires defining runc bundle in HolOS build (e.g., copy Docker image layers, run holos-config for configs).
- Less flexible than Docker for multi-container; assumes single holochain instance; added boot steps increase complexity slightly.

## Implementation Details
### Docker Changes
1. **Update Dockerfile** (multi-stage for s6-overlay):
   ```
   # Stage 1: Build s6-overlay (use official or build from source)
   FROM alpine:3.19 AS s6-builder
   RUN apk add --no-cache build-base linux-headers s6-overlay
   # ... (build s6 if needed; or COPY pre-built)

   # Stage 2: Main image
   FROM cgr.dev/chainguard/wolfi-base
   COPY --from=s6-builder /usr/bin/s6* /usr/bin/
   # Install existing packages + s6 tools
   RUN apk update && apk add --no-cache ... tini logrotate shadow gosu s6 s6-linux-utils happ_config_file
   # Existing RUN wget for binaries...
   # Copy files as before, including happ_config_file
   # New: Copy s6 service dir
   RUN mkdir -p /etc/s6-overlay/s6-rc.d/holochain
   COPY holochain-service.sh /etc/s6-overlay/s6-rc.d/holochain/run  # Wrapper script
   RUN chmod +x /etc/s6-overlay/s6-rc.d/holochain/run
   # Update entrypoint to s6 init
   ENTRYPOINT ["/init"]  # s6's PID 1
   ```
2. **New `holochain-service.sh` (in repo)**: Wrapper for current entrypoint logic + holochain launch.
   ```
   #!/bin/sh
   set -eu
   # Setup dirs, validation, logrotate as in current entrypoint.sh
   # Optionally run happ_config_file for hApp config validation/generation if needed
   # Launch holochain
   exec gosu nonroot holochain --piped --config-path /etc/holochain/conductor-config.yaml
   ```
3. **s6 Config** (`/etc/s6-overlay/s6-rc.d/holochain/dependencies.d/start`): Depend on logrotate service.
   - Set `s6-svscan` to scan services; enable auto-restart in `/etc/s6-overlay/s6-rc.conf`.
4. **Testing**:
   - Build image: `docker build -t holochain-ha .`
   - Run: `docker run -e CONDUCTOR_MODE=true -v /path/to/data:/data holochain-ha`
   - Simulate crash: `docker exec <id> kill -9 $(pgrep holochain)`
   - Verify: Logs show restart; process respawns within 5s, up to 5 retries.
   - Integration: Use enhanced `test_default_conductor.sh` + crash simulation, including happ_config_file if integrated.

### HolOS Changes
1. **Update Buildroot Config** (`holos-buildroot-2025.08.config`): runc and openrc-supervise-daemon already enabled.
   ```
   BR2_PACKAGE_RUNC=y
   BR2_PACKAGE_OPENRC_SUPERVISE_DAEMON=y
   # Existing networking/SSH deps if needed
   ```
2. **New OpenRC Service** (`holos/overlay/etc/init.d/S90holochain-container`):
   ```
   #!/sbin/openrc-run
   name="holochain-container"
   description="Supervised Holochain runc container"
   command="/usr/bin/runc run -b /opt/holochain-bundle holochain-instance"
   command_background=true
   pidfile="/run/${name}.pid"
   supervisord_start() {
       start-stop-daemon --start --exec $command --background --pidfile $pidfile
   }
   # Use supervise-daemon for restarts
   supervise_daemon_args="--start --retry 5 --backoff 10"
   depend() {
       need net S70interfaces S75ssh-keys
       after S06holos-config S77etc-issue
   }
   ```
   - Make executable, add to `/etc/init.d/` in overlay as S90 (after new init scripts).
3. **Runc Bundle Setup**: In HolOS Makefile/overlay, extract Docker image to `/opt/holochain-bundle` (use `docker save | tar` in build); run holos-config to generate platform configs (e.g., from contrib YAML for network/SSH).
   - Config: Mount `/data` to persistent dir (future: add fstab for disk); integrate holos-config outputs.
4. **Boot Integration**: Add to OpenRC defaults (`/etc/conf.d/holochain-container`): `holochain-container_enable="YES"`.
   - holos-config already built/integrated in Makefile for S06holos-config.
5. **Testing**:
   - Build ISO: `make iso`
   - Boot in QEMU: `make run`; verify service starts post-init scripts (`rc-service holochain-container start`).
   - Crash sim: Kill inside container; check OpenRC logs (`/var/log/rc.log`), verify restart after dependencies.
   - Persistence: Test with simulated disk mount; verify holos-config integration (e.g., network/SSH setup).

## Mermaid Diagram: HA Architecture
```mermaid
graph TD
    A[HolOS Boot / Docker Run] --> B{PID 1 Init}
    B -->|Docker| C[s6-overlay Init]
    B -->|HolOS| D[OpenRC Init]
    C --> E[Service Scan: holochain-service.sh]
    D --> G[S06holos-config: Hardware via holos-config]
    G --> H[S70interfaces: Networking]
    H --> I[S75ssh-keys: SSH from GitHub]
    I --> J[S77etc-issue: MOTD with IPs/version]
    J --> F[Service: S90holochain-container]
    E --> K[holochain Launch + Validation + Logging + happ_config_file if needed]
    F --> L[runc run /opt/holochain-bundle (holos-config generated configs)]
    K --> M{holochain Crash?}
    L --> N{holochain Crash?}
    M -->|Yes| O[s6 Restart Policy: Retry 5x, Backoff]
    N -->|Yes| P[supervise-daemon: Retry 5x, Backoff]
    O --> K
    P --> L
    M -->|No| Q[Always On Node Running]
    N -->|No| R[Always On Node Running]
    style Q fill:#90EE90
    style R fill:#90EE90
```

## Pros/Cons and Rationale
- **Overall Pros**: Ensures HA without hoster intervention; aligns with "Always On" by restarting on transient crashes (e.g., network blips). Minimal changes to existing code.
- **Overall Cons**: Internal supervision adds ~5-10MB; potential for restart loops on persistent bugs (mitigated by retry limits). Requires build updates.
- **Rationale**: s6 for Docker (container-native, replaces tini seamlessly). OpenRC/supervise-daemon for HolOS (native to Buildroot, no external deps). Both support logging/persistence via `/data`. Prioritizes simplicity over full orchestrators (e.g., no Kubernetes assumption).

This proposal can be implemented in ~3-4 days, accounting for new boot dependencies and holos-config integration (start with Docker). Total impact: Enhanced reliability for hApps, with improved platform-specific setup via holos-config.