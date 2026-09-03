# Edge Node

This repo contains the tooling needed to deploy and operate always-on nodes for Holochain applications (hApps).

The tooling consists of:

Edge Node - Docker container specifications for running Holochain with hApps in an OCI-compliant containerized environment. Two variants: `edgenode` (standard, with log-sender) and `edgenode-harvester` (with log-harvester for Unyt invoice aggregation).

For a detailed overview and usage instructions [see here](/USAGE.md).

## For Support

- [hackmd - How To Set Up Always-On Nodes for Your Holochain Apps](https://hackmd.io/BIgfIdV3Q3uuCsSpazsRig)
- [gdoc - How To Set Up Always-On Nodes for Your Holochain Apps](https://docs.google.com/document/d/1f3_5Ddff50pFIuzRJAmqGwT9nE873TKQC182LKyJJ4k/edit?tab=t.0#heading=h.ik0z3qmvpegt)
- [Edge Node Support Telegram](https://t.me/+8JV9ibBHBDpmOTg0)
- [Schedule Live-Support](https://calendly.com/rob-lyon-holo/30min)
- [Holo Host Forum](https://forum.holo.host/)

## Repo Components

### Container Build System

A [Docker-based container](docker/README.md) that delivers Edge Node, ready to run hApps:

- Holochain 0.7.0 conductor managed by s6-overlay, starting automatically on container launch.
- Tools for installing and managing hApps from configuration files.
- Two variants: standard (`edgenode`) and harvester (`edgenode-harvester`).

### Tools

- A CLI utility for creating and validating [hApp config files](tools/happ_config_file/README.md).


## Quick Start

### Standard Edge Node

1. Pull the image:

```sh
docker pull ghcr.io/holo-host/edgenode
```

2. Launch with persistent storage:

```sh
docker run --name edgenode -dit -v $(pwd)/holo-data:/data ghcr.io/holo-host/edgenode
```

3. Access the container and check for a running hApp-ready `holochain` process:

```sh
docker exec -it edgenode su - nonroot
ps -ef
```

### Harvester Edge Node

1. Pull the image:

```sh
docker pull ghcr.io/holo-host/edgenode-harvester
```

2. Launch with your log-collector credentials:

```sh
docker run --name harvester -dit \
  -v $(pwd)/holo-data:/data \
  -p 4444:4444 \
  -p 4445:4445 \
  -e COLLECTOR_URL=https://your-log-collector.unyt.dev \
  -e ADMIN_SECRET=your-admin-secret \
  -e LAIR_PASSWORD=your-lair-password \
  ghcr.io/holo-host/edgenode-harvester
```

See [docker/LOG_HARVESTER_QUICKSTART.md](docker/LOG_HARVESTER_QUICKSTART.md) for full setup instructions.


## Documentation

- [Detailed overview and usage instructions](/USAGE.md)
- [Edge Node Container Instructions](docker/README.md)
- [Log-Sender Quickstart (Unyt resource accounting)](docker/LOG_SENDER_QUICKSTART.md)
- [Log-Harvester Quickstart (Unyt invoice aggregation)](docker/LOG_HARVESTER_QUICKSTART.md)
- [Tools for working with Edge Nodes](tools/README.md)
