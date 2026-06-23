#!/usr/bin/env python3
"""
fl-bridge: Conductor API bridge for edgenode-flower.

Coordinates between the Holochain pollen hApp and the local Flower process.
On startup it optionally pip-installs the ClientApp, installs the pollen hApp,
writes machine and org identity records, then launches either a Flower SuperNode
(participant role) or SuperLink (designated aggregator role in Mode C).
It monitors process output for round-completion events and appends a
ContributionRecord to the local audit log after each round.

Deployment modes (FLOWER_DEPLOYMENT_MODE):
  overlay       - Flower connects to an existing external SuperLink.
                  Bridge records audit trail locally; DHT commitment
                  requires the pollen hApp to be deployed (see TODO below).
  augmented     - As overlay, but the bridge validates that strategy
                  changes have been ratified on-chain before they are
                  passed to the SuperNode. (Not yet implemented.)
  decentralized - No external SuperLink. Round start/stop is signalled
                  by the round_coordination zome via the DHT. The
                  designated-aggregator address is resolved from DHT
                  state before the SuperNode is launched, or this machine
                  activates a SuperLink if elected aggregator.
                  (Aggregator election not yet implemented.)
"""

import json
import logging
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [fl-bridge] %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger(__name__)

# File handler added after /data/logs is guaranteed to exist (see main()).
_file_handler: Optional[logging.FileHandler] = None

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

HC_ADMIN_PORT        = os.environ.get("HC_ADMIN_PORT", "4444")
HC_APP_PORT          = os.environ.get("HC_APP_PORT", "4445")
FL_APP_ID            = os.environ.get("FL_APP_ID", "fl-happ")
FL_HAPP_URL          = os.environ.get("FL_HAPP_URL", "")
FL_HAPP_PATH         = os.environ.get("FL_HAPP_PATH", "")
NETWORK_SEED         = os.environ.get("HC_NETWORK_SEED", "fl-network")
SUPERLINK_URL        = os.environ.get("SUPERLINK_URL", "")
DEPLOYMENT_MODE      = os.environ.get("FLOWER_DEPLOYMENT_MODE", "overlay")

# Machine-level identity (one edgenode per participating machine)
FL_MACHINE_NAME      = os.environ.get("FL_MACHINE_NAME", "")

# Org-level identity (governance principal; one vote per org regardless of machine count)
ORG_NAME             = os.environ.get("FL_ORG_NAME", "")
JURISDICTION         = os.environ.get("FL_JURISDICTION", "")

# ClientApp — user-provided training code
FL_CLIENT_APP_MODULE = os.environ.get("FL_CLIENT_APP_MODULE", "")  # e.g. myapp:FlowerClient
FL_CLIENT_APP_URL    = os.environ.get("FL_CLIENT_APP_URL", "")     # pip-installable URL/package

# TLS
FLOWER_INSECURE      = os.environ.get("FLOWER_INSECURE", "false").lower() == "true"
FLOWER_ROOT_CERT     = os.environ.get("FLOWER_ROOT_CERT", "")

# Ports
FLOWER_SUPERLINK_PORT = os.environ.get("FLOWER_SUPERLINK_PORT", "9093")

DATA_DIR           = Path("/data/flower")
CONTRIBUTIONS_PATH = DATA_DIR / "contributions.jsonl"
IDENTITY_PATH      = DATA_DIR / "identity.json"
FL_HAPP_CACHE      = Path("/app/fl-happ.happ")

# ---------------------------------------------------------------------------
# Conductor helpers
# ---------------------------------------------------------------------------

def _hc(*args: str, check: bool = False) -> subprocess.CompletedProcess:
    """Run an `hc sandbox call` subcommand against the local conductor."""
    cmd = ["hc", "sandbox", "call", "--running", HC_ADMIN_PORT, *args]
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def wait_for_conductor(timeout: int = 300) -> None:
    log.info("Waiting for Holochain conductor on port %s ...", HC_ADMIN_PORT)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if _hc("list-apps").returncode == 0:
            log.info("Holochain conductor is ready.")
            return
        time.sleep(5)
    log.error("Conductor did not become ready within %ds — aborting.", timeout)
    sys.exit(1)


def is_happ_installed() -> bool:
    result = _hc("list-apps")
    return FL_APP_ID in result.stdout


def install_fl_happ() -> None:
    """Download (if needed) and install the pollen hApp into the local conductor."""
    if is_happ_installed():
        log.info("pollen hApp '%s' already installed — skipping.", FL_APP_ID)
        return

    happ_path = FL_HAPP_PATH
    if not happ_path and FL_HAPP_URL:
        if not FL_HAPP_CACHE.exists():
            log.info("Downloading pollen hApp from %s ...", FL_HAPP_URL)
            result = subprocess.run(
                ["wget", "-q", "-O", str(FL_HAPP_CACHE), FL_HAPP_URL],
                capture_output=True,
            )
            if result.returncode != 0:
                log.error("Failed to download pollen hApp: %s", result.stderr.decode())
                sys.exit(1)
        happ_path = str(FL_HAPP_CACHE)

    if not happ_path:
        log.warning(
            "No FL_HAPP_URL or FL_HAPP_PATH configured — skipping hApp installation. "
            "Audit trail will be local only until the pollen hApp is deployed."
        )
        return

    log.info("Installing pollen hApp '%s' from %s ...", FL_APP_ID, happ_path)
    _hc("install-app", happ_path, "--app-id", FL_APP_ID, NETWORK_SEED, check=True)
    _hc("enable-app", FL_APP_ID, check=True)
    log.info("pollen hApp '%s' installed and enabled.", FL_APP_ID)


# ---------------------------------------------------------------------------
# ClientApp installation
# ---------------------------------------------------------------------------

def install_client_app() -> None:
    """
    Pip-install the Flower ClientApp package if FL_CLIENT_APP_URL is set.

    This allows the operator to supply federation-specific training code
    without rebuilding the image. The installed package is then referenced
    via FL_CLIENT_APP_MODULE when starting the SuperNode.
    """
    if not FL_CLIENT_APP_URL:
        return
    log.info("Installing ClientApp from %s ...", FL_CLIENT_APP_URL)
    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--quiet", FL_CLIENT_APP_URL],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        log.error("Failed to install ClientApp: %s", result.stderr)
        sys.exit(1)
    log.info("ClientApp installed successfully.")


# ---------------------------------------------------------------------------
# Identity record
# ---------------------------------------------------------------------------

def write_identity() -> None:
    """
    Persist machine and org identity to /data/flower/identity.json.

    Records both levels of the two-level identity model:
      - Machine agent: this specific edgenode (participation principal)
      - Organisation:  the owning org (governance principal)

    In a full deployment the same data would be committed to the
    participant_registry zome via a `call_zome` on the app WebSocket —
    that path is left as a TODO pending pollen hApp deployment.
    """
    if IDENTITY_PATH.exists():
        return
    identity = {
        "machine": {
            "name":            FL_MACHINE_NAME,
            "deployment_mode": DEPLOYMENT_MODE,
            "registered_at":   datetime.now(timezone.utc).isoformat(),
        },
        "org": {
            "name":         ORG_NAME,
            "jurisdiction": JURISDICTION,
        },
        "app_id": FL_APP_ID,
    }
    IDENTITY_PATH.write_text(json.dumps(identity, indent=2))
    log.info("Identity written to %s", IDENTITY_PATH)


# ---------------------------------------------------------------------------
# Contribution audit
# ---------------------------------------------------------------------------

def record_contribution(
    round_num: int,
    model_in_hash: str = "",
    update_hash: str = "",
    data_size: int = 0,
) -> None:
    """
    Append a ContributionRecord to the local JSONL audit log.

    Records are attributed at machine level (FL_MACHINE_NAME) within an
    org (FL_ORG_NAME), reflecting the two-level identity model. The local
    log is always written; in a full deployment with the pollen hApp active,
    the same record would additionally be committed to this machine agent's
    Holochain source chain via:

        contribution_audit.commit_record(ContributionRecord { ... })

    TODO: implement source-chain commitment once pollen zomes are deployed
    and an authenticated app WebSocket client is available.
    """
    record = {
        "round_number":    round_num,
        "app_id":          FL_APP_ID,
        "machine_name":    FL_MACHINE_NAME,
        "org_name":        ORG_NAME,
        "model_in_hash":   model_in_hash,
        "update_hash":     update_hash,
        "data_size":       data_size,
        "timestamp":       datetime.now(timezone.utc).isoformat(),
        "deployment_mode": DEPLOYMENT_MODE,
    }
    with CONTRIBUTIONS_PATH.open("a") as f:
        f.write(json.dumps(record) + "\n")
    log.info("ContributionRecord appended (round=%d, machine=%s)", round_num, FL_MACHINE_NAME)


# ---------------------------------------------------------------------------
# Flower process log parsing
# ---------------------------------------------------------------------------

# Patterns observed in Flower 1.x SuperNode stdout
_ROUND_PATTERNS = [
    re.compile(r"fit progress.*?(\d+),", re.IGNORECASE),       # fit progress: (N, ...)
    re.compile(r"FL round[:\s]+(\d+)", re.IGNORECASE),         # FL round: N
    re.compile(r"round\s+(\d+)\s+finished", re.IGNORECASE),    # round N finished
]


def parse_round_number(line: str) -> Optional[int]:
    """Return the round number from a Flower log line, or None."""
    for pattern in _ROUND_PATTERNS:
        m = pattern.search(line)
        if m:
            return int(m.group(1))
    return None


# ---------------------------------------------------------------------------
# Flower process management
# ---------------------------------------------------------------------------

def build_flower_cmd() -> tuple[Optional[list[str]], str]:
    """
    Build the Flower command for this machine's current role.

    Returns (cmd, role) where role is 'supernode' or 'superlink'.
    Returns (None, '') if no process should be started yet.

    In Mode C the role is determined by whether this machine is the
    designated aggregator for the current round. Aggregator election
    via the round_coordination zome is not yet implemented; the SuperNode
    path is always taken for now, with SUPERLINK_URL as a fallback.
    """
    if DEPLOYMENT_MODE == "decentralized":
        # TODO: query round_coordination zome to determine if this machine
        # is the designated aggregator for the current round.
        #   if is_designated_aggregator():
        #       return _build_superlink_cmd(), "superlink"
        # For now fall back to SuperNode if SUPERLINK_URL is set.
        if not SUPERLINK_URL:
            log.warning(
                "Decentralized mode: aggregator election not yet implemented — "
                "Flower will not start. Set SUPERLINK_URL to test SuperNode behaviour."
            )
            return None, ""

    return _build_supernode_cmd(), "supernode"


def _build_supernode_cmd() -> Optional[list[str]]:
    """Build a `flwr supernode` command for the participant role."""
    if not SUPERLINK_URL:
        log.warning(
            "SUPERLINK_URL not set — Flower SuperNode will not start. "
            "Set SUPERLINK_URL=<host>:<port> and restart the container."
        )
        return None

    cmd = ["flwr", "supernode", "--superlink", SUPERLINK_URL]

    if FL_CLIENT_APP_MODULE:
        cmd += ["--clientapp", FL_CLIENT_APP_MODULE]
    else:
        log.warning(
            "FL_CLIENT_APP_MODULE not set — SuperNode will start without a ClientApp "
            "and will not perform training. Set FL_CLIENT_APP_MODULE=<module>:<class>."
        )

    if FLOWER_INSECURE:
        log.warning("TLS disabled (FLOWER_INSECURE=true) — do not use in production.")
        cmd.append("--insecure")
    elif FLOWER_ROOT_CERT:
        cmd += ["--root-certificates", FLOWER_ROOT_CERT]
    else:
        log.warning(
            "Neither FLOWER_INSECURE nor FLOWER_ROOT_CERT is set. "
            "The SuperNode may fail TLS handshake against the SuperLink."
        )

    return cmd


def _build_superlink_cmd() -> list[str]:
    """
    Build a `flwr superlink` command for the designated aggregator role (Mode C).

    The SuperLink binds on FLOWER_SUPERLINK_PORT. After the command is built
    the caller is responsible for publishing the address to the pollen
    round_coordination zome so that other machines' SuperNodes can connect.

    TODO: populate SSL cert/key args for production TLS.
    """
    cmd = [
        "flwr", "superlink",
        f"--fleet-api-address=0.0.0.0:{FLOWER_SUPERLINK_PORT}",
    ]
    if FLOWER_INSECURE:
        log.warning("SuperLink TLS disabled (FLOWER_INSECURE=true) — dev only.")
        # TODO: add correct insecure flag for flwr superlink when available
    return cmd


def start_flower_process() -> tuple[Optional[subprocess.Popen], str]:
    """Start the appropriate Flower process and return (proc, role)."""
    cmd, role = build_flower_cmd()
    if cmd is None:
        return None, ""
    log.info("Starting Flower %s: %s", role, " ".join(cmd))
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    return proc, role


# ---------------------------------------------------------------------------
# Bridge main loop
# ---------------------------------------------------------------------------

def run_bridge_loop(proc: subprocess.Popen, role: str) -> None:
    """Tail Flower process output, echoing to stdout and recording round events."""
    log_path = f"/data/logs/flower-{role}.log"
    flower_log = open(log_path, "a")
    try:
        for line in proc.stdout:
            sys.stdout.write(f"[flower-{role}] {line}")
            sys.stdout.flush()
            flower_log.write(line)
            flower_log.flush()

            round_num = parse_round_number(line)
            if round_num is not None:
                record_contribution(round_num=round_num)
    finally:
        flower_log.close()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    log.info(
        "fl-bridge starting (mode=%s, machine=%s, org=%s)",
        DEPLOYMENT_MODE, FL_MACHINE_NAME or "<unset>", ORG_NAME or "<unset>",
    )

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    Path("/data/logs").mkdir(parents=True, exist_ok=True)

    global _file_handler
    _file_handler = logging.FileHandler("/data/logs/fl-bridge.log")
    _file_handler.setFormatter(
        logging.Formatter("%(asctime)s [fl-bridge] %(levelname)s %(message)s")
    )
    log.addHandler(_file_handler)

    install_client_app()
    wait_for_conductor()
    install_fl_happ()
    write_identity()

    proc, role = start_flower_process()

    if proc is None:
        log.info("No Flower process started — bridge idling.")
        signal.pause()
        return

    def _shutdown(signum, _frame):
        log.info("Received signal %d — terminating Flower %s.", signum, role)
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    run_bridge_loop(proc, role)

    rc = proc.wait()
    log.info("Flower %s exited with code %d.", role, rc)
    sys.exit(rc)


if __name__ == "__main__":
    main()
