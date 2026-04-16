#!/usr/bin/env python3
"""
fl-bridge: Conductor API bridge for edgenode-flower.

Coordinates between the Holochain FL hApp and a Flower SuperNode.
On startup it installs the FL hApp (if configured), writes a participant
identity record, then launches the Flower SuperNode as a managed subprocess.
It monitors SuperNode output for round-completion events and appends a
ContributionRecord to the local audit log after each round.

Deployment modes (FLOWER_DEPLOYMENT_MODE):
  overlay       - Flower connects to an existing external SuperLink.
                  Bridge records audit trail locally; DHT commitment
                  requires the FL hApp to be deployed (see TODO below).
  augmented     - As overlay, but the bridge validates that strategy
                  changes have been ratified on-chain before they are
                  passed to the SuperNode. (Not yet implemented.)
  decentralized - No external SuperLink. Round start/stop is signalled
                  by the round_coordination zome via the DHT. The
                  designated-aggregator address is resolved from DHT
                  state before the SuperNode is launched. (Not yet
                  implemented.)
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

HC_ADMIN_PORT     = os.environ.get("HC_ADMIN_PORT", "4444")
HC_APP_PORT       = os.environ.get("HC_APP_PORT", "4445")
FL_APP_ID         = os.environ.get("FL_APP_ID", "fl-happ")
FL_HAPP_URL       = os.environ.get("FL_HAPP_URL", "")
FL_HAPP_PATH      = os.environ.get("FL_HAPP_PATH", "")
NETWORK_SEED      = os.environ.get("HC_NETWORK_SEED", "fl-network")
SUPERLINK_URL     = os.environ.get("SUPERLINK_URL", "")
DEPLOYMENT_MODE   = os.environ.get("FLOWER_DEPLOYMENT_MODE", "overlay")
ORG_NAME          = os.environ.get("FL_ORG_NAME", "")
JURISDICTION      = os.environ.get("FL_JURISDICTION", "")
FLOWER_INSECURE   = os.environ.get("FLOWER_INSECURE", "false").lower() == "true"
FLOWER_ROOT_CERT  = os.environ.get("FLOWER_ROOT_CERT", "")

DATA_DIR           = Path("/data/flower")
CONTRIBUTIONS_PATH = DATA_DIR / "contributions.jsonl"
PARTICIPANT_PATH   = DATA_DIR / "participant.json"
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
    """Download (if needed) and install the FL hApp into the local conductor."""
    if is_happ_installed():
        log.info("FL hApp '%s' already installed — skipping.", FL_APP_ID)
        return

    happ_path = FL_HAPP_PATH
    if not happ_path and FL_HAPP_URL:
        if not FL_HAPP_CACHE.exists():
            log.info("Downloading FL hApp from %s ...", FL_HAPP_URL)
            result = subprocess.run(
                ["wget", "-q", "-O", str(FL_HAPP_CACHE), FL_HAPP_URL],
                capture_output=True,
            )
            if result.returncode != 0:
                log.error("Failed to download FL hApp: %s", result.stderr.decode())
                sys.exit(1)
        happ_path = str(FL_HAPP_CACHE)

    if not happ_path:
        log.warning(
            "No FL_HAPP_URL or FL_HAPP_PATH configured — skipping hApp installation. "
            "Audit trail will be local only until the FL hApp is deployed."
        )
        return

    log.info("Installing FL hApp '%s' from %s ...", FL_APP_ID, happ_path)
    _hc("install-app", happ_path, "--app-id", FL_APP_ID, NETWORK_SEED, check=True)
    _hc("enable-app", FL_APP_ID, check=True)
    log.info("FL hApp '%s' installed and enabled.", FL_APP_ID)


# ---------------------------------------------------------------------------
# Participant identity
# ---------------------------------------------------------------------------

def write_participant_identity() -> None:
    """
    Persist participant metadata to /data/flower/participant.json.

    This is the local record.  In a full deployment the same data would be
    committed to the participant_registry zome via a `call_zome` on the app
    WebSocket — that path is left as a TODO pending FL hApp deployment.
    """
    if PARTICIPANT_PATH.exists():
        return
    identity = {
        "app_id":          FL_APP_ID,
        "org_name":        ORG_NAME,
        "jurisdiction":    JURISDICTION,
        "deployment_mode": DEPLOYMENT_MODE,
        "registered_at":   datetime.now(timezone.utc).isoformat(),
    }
    PARTICIPANT_PATH.write_text(json.dumps(identity, indent=2))
    log.info("Participant identity written to %s", PARTICIPANT_PATH)


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

    Each record captures who participated in which round and when.  The
    local log is a fallback that is always written; in a full deployment
    with the FL hApp active, the same record would additionally be committed
    to the participant's Holochain source chain via:

        contribution_audit.commit_record(ContributionRecord { ... })

    TODO: implement the source-chain commitment once the FL hApp zomes are
    deployed and an authenticated app WebSocket client is available.
    """
    record = {
        "round_number":    round_num,
        "app_id":          FL_APP_ID,
        "org_name":        ORG_NAME,
        "model_in_hash":   model_in_hash,
        "update_hash":     update_hash,
        "data_size":       data_size,
        "timestamp":       datetime.now(timezone.utc).isoformat(),
        "deployment_mode": DEPLOYMENT_MODE,
    }
    with CONTRIBUTIONS_PATH.open("a") as f:
        f.write(json.dumps(record) + "\n")
    log.info(
        "ContributionRecord appended (round=%d)", round_num
    )


# ---------------------------------------------------------------------------
# Flower SuperNode log parsing
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
# Flower SuperNode process management
# ---------------------------------------------------------------------------

def build_supernode_cmd() -> Optional[list[str]]:
    """
    Build the `flwr supernode` command for the configured deployment mode.

    Returns None if the SuperNode should not be started (e.g. decentralised
    mode with no aggregator address resolved yet).
    """
    if DEPLOYMENT_MODE == "decentralized":
        # TODO: resolve the current round's designated aggregator address
        # from the round_coordination zome before building the command.
        # For now, fall back to SUPERLINK_URL if set (useful for testing).
        if not SUPERLINK_URL:
            log.warning(
                "Decentralized mode: no SUPERLINK_URL and aggregator election not "
                "yet implemented — SuperNode will not start until an address is "
                "available."
            )
            return None

    if not SUPERLINK_URL:
        log.warning(
            "SUPERLINK_URL not set — Flower SuperNode will not start. "
            "Set SUPERLINK_URL=<host>:<port> and restart the container."
        )
        return None

    cmd = ["flwr", "supernode", "--superlink", SUPERLINK_URL]

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


def start_flower_supernode() -> Optional[subprocess.Popen]:
    cmd = build_supernode_cmd()
    if cmd is None:
        return None
    log.info("Starting Flower SuperNode: %s", " ".join(cmd))
    return subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )


# ---------------------------------------------------------------------------
# Bridge main loop
# ---------------------------------------------------------------------------

def run_bridge_loop(proc: subprocess.Popen) -> None:
    """Tail SuperNode output, echoing to stdout and recording round events."""
    flower_log = open("/data/logs/flower-supernode.log", "a")
    try:
        for line in proc.stdout:
            sys.stdout.write(f"[flower] {line}")
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
    log.info("fl-bridge starting (mode=%s)", DEPLOYMENT_MODE)

    DATA_DIR.mkdir(parents=True, exist_ok=True)
    Path("/data/logs").mkdir(parents=True, exist_ok=True)

    # Add file handler now that /data/logs is guaranteed to exist
    global _file_handler
    _file_handler = logging.FileHandler("/data/logs/fl-bridge.log")
    _file_handler.setFormatter(
        logging.Formatter("%(asctime)s [fl-bridge] %(levelname)s %(message)s")
    )
    log.addHandler(_file_handler)

    wait_for_conductor()
    install_fl_happ()
    write_participant_identity()

    proc = start_flower_supernode()

    if proc is None:
        log.info("No SuperNode process started — bridge idling.")
        # Keep the s6 service alive so the container doesn't restart in a loop
        signal.pause()
        return

    def _shutdown(signum, _frame):
        log.info("Received signal %d — terminating Flower SuperNode.", signum)
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    run_bridge_loop(proc)

    rc = proc.wait()
    log.info("Flower SuperNode exited with code %d.", rc)
    sys.exit(rc)


if __name__ == "__main__":
    main()
