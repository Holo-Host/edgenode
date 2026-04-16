# Edge Node

This repo contains the tooling needed to deploy and operate always-on nodes for Holochain applications (hApps).

The tooling consists of:

Edge Node - A Docker container specification for running Holochain with hApps in an OCI-compliant containerized environment.

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

- Holochain conductor configured to automatically run via `tini`.
- Tools for installing and managing hApps from configuration files.

### Tools

- A CLI utility for creating and validating [hApp config files](tools/happ_config_file/README.md).


## Quick Start

### To test the Edge Node container:

1. Pull the Docker image:

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

## Documentation

- [Detailed overview and usage instructions](/USAGE.md)
- [Edge Node Container Instructions](docker/README.md)
- [Tools for working with Edge Nodes](tools/README.md)
