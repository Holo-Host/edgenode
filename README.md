# Edge Node

This repo contains the tooling needed to deploy and operate Holochain Edge Nodes and run decentralized hApps on them!

The tooling consists of:

1. A Docker container specification for running Holochain with hApps in an OCI-compliant containerized environment.
2. A streamlined Linux ISO that enables the deployment of this container on physical or virtual hardware (especially HoloPorts).

For a detailed overview and usage instructions [see here](/USAGE.md).

## For Support:

- [Edge Node Support Telegram](https://t.me/+8JV9ibBHBDpmOTg0)
- [Schedule Live-Support](https://calendly.com/rob-lyon-holo/holo-huddle-edge-node-support)
- [Holo Host Forum](https://forum.holo.host/)

## Repo Components:

### Container Build System

A [Docker-based container](docker/README.md) that delivers a Holochain Edge Node ready to run hApps:

- Holochain conductor configured to automatically run via `tini`.
- Tools for installing and managing hApps from configuration files provided by hApp publishers.

### HolOS Build System

A [specialized OS builder](holos/README.md) for creating custom ISO images using Buildroot, featuring:

- Optimized Linux kernel.
- Integrated Holochain services and dependencies (via `runc`-deployed Edge Node container).
- Custom init scripts for automatic network configuration.
- Generates ready-to-burn disk images for deployment.

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

### For HolOS Users

1. Download a release of the iso from our releases page: TBD
2. Burn a USB stick, to install on your own hardware or install it in a virtualized environment of your choosing.
3. Follow the instructions provided to choose persistence, container instance, and other configuration options for the machine.
4. Follow [these](TBD) instructions to install and manage hApp instances you will be running on your node.

## Documentation

- [Detailed overview and usage instructions](/USAGE.md)
- [Edge Node Container Instructions](docker/README.md)
- [HolOS Build System Guide](holos/README.md)
- [Tools for working with Edge Nodes](tools/README.md)