# Edge Node

This repo contains the tooling needed to participate in the decentralized support network for Holochain hApps, and (when operational) accounting for services provided using Unyt payment currency.

The tooling consists of:

1. A Docker container specification for running Holochain with hApps in an OCI-compliant containerized environment.
2. A streamlined Linux ISO for making it easy to deploy this container on physical or virtual hardware (especially HoloPorts)

For a detailed overview and usage instructions [see here](/USAGE.md).

## Repo Components:

### Container Build System

A [Docker-based container](docker/README.md) that delivers a Holochain runtime environment ready to run hApps:

- Holochain binary configured to automatically run via `tini`.
- WIP: Tools for installing and managing hApps from configuration files provided by hApp publishers.
- TBD: Log-harvesting and publishing for connecting to HoloFuel/Unyt accounts.

### Holos Build System

A [specialized OS builder](holos/README.md) for creating custom ISO images using Buildroot, featuring:

- Optimized Linux kernel.
- Integrated Holochain services and dependencies (via `runc`-deployed container).
- Custom init scripts for automatic network configuration.
- Ready-to-burn disk images for deployment.

### Tools

- A CLI utility for creating and validating [hApp config files](tools/happ_config_file/README.md).

## Quick Start

### To test the container:

1. Pull the Docker image:

```sh
docker pull ghcr.io/holo-host/trailblazer
```

2. Launch with persistent storage:

```sh
docker run --name trailblazer -dit -v $(pwd)/holo-data:/data ghcr.io/holo-host/trailblazer
```

3. Access the container and check for a running hApp-ready `holochain` process:

```sh
docker exec -it trailblazer su - nonroot
ps -ef
```

### For Holos Users

1. Download a release of the iso from our releases page: TBD
2. Burn a USB stick, to install on your own hardware or install it in a virtualized environment of your choosing.
3. Follow the instructions provided to choose persistence, container instance, and other configuration options for the machine.
4. Follow [these](TBD) instructions to install and manage hApp instances you will be running on your node.

## Documentation

- [Trailblazer Toolkit Instructions](docker/README.md)
- [Holos Build System Guide](holos/README.md)
- [Detailed overview and usage instructions](/USAGE.md)