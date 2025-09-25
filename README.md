# Trailblazer

This repo contains the the tooling needed to participate in the decentralized "DIY" Holo Hosting network for decentralized hApps, and (when released) accounting for hosting provided using HoloFuel.

The tooling consists of:

1. a docker container specification for running Holochain in an OCI containerized environment
2. a streamlined Linux ISO for making it easy to deploy this container, physical or virtual hardware (including Holoports)

## Core Components

### Container Build System
A Docker-based environment that delivers a Holochain runtime environment:
- Holochain binary configured to automatically run via systemd
- Tools for installing and managing hApp from configuration files provided by hApp publishers.
- Log-harvesting and publishing for connecting to HoloFuel accounts.

### Holos Build System
A specialized OS builder for creating custom ISO images using Buildroot, featuring:
- Optimized Linux kernel
- Integrated Holochain services and dependencies
- Custom init scripts for automatic network configuration
- Ready-to-burn disk images for deployment

## Quick Start

### To test the container:
1. Pull the Docker image:
   ```sh
   docker pull ghcr.io/holo-host/trailblazer
   ```
2. Launch with persistent storage:
   ```sh
   docker run -v $(pwd)/holo-data:/data ghcr.io/holo-host/trailblazer
   ```
3. Access the container and create a sandbox:
   ```sh
   docker exec -it trailblazer su - nonroot
   hc sandbox create
   ```

### For Holos Users

1. Download a release of the iso from our releases page: TBD
2. Burn a USB stick, to install on your own hardware or install it in a virtualized environment of your choosing.
3. Follow the instructions provided to choose persistence, container instance, and other configuration options for the machine.
4. Follow [these](TBD) instructions to install and manage hApp instances you will be hosting.

## Documentation
- [`Trailblazer Toolkit Instructions`](docker/README.md)
- [`Holos Build System Guide`](holos/README.md)