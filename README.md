# Trailblazer

Trailblazer is the comprehensive suite for Holo ecosystem contributors, providing integrated tools for Holochain application development and HoloPort deployment. This repository contains two core components that work together to streamline the path from local development to production deployment.

## Core Components

### 🐳 Trailblazer Toolkit
A Docker-based environment that delivers a complete Holochain development workspace with:
- Pre-configured Holochain and hc CLI tools
- Persistent storage for conductor configurations and data
- Sandbox environments for safe hApp testing
- WebRTC networking for peer-to-peer communication

### 🖥️ holos Build System
A specialized OS builder for creating custom HoloPort firmware images using Buildroot, featuring:
- Optimized Linux kernel for HoloPort hardware
- Integrated Holochain services and dependencies
- Custom init scripts for automatic network configuration
- Ready-to-burn disk images for HoloPort deployment

## Quick Start

### For Application Developers
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

### For OS Contributors
1. Build the Holo OS:
   ```sh
   cd [`holos`](holos/Makefile:1)
   make
   ```
2. Find the generated image in `output/images/`

## Why This Matters
Trailblazer solves the critical challenge of environment consistency across the development lifecycle. By providing identical tooling and configurations from your laptop to production HoloPorts, it eliminates "works on my machine" issues and accelerates time-to-deployment.

## Documentation
- [`Trailblazer Toolkit Instructions`](docker/README.md)
- [`Holos Build System Guide`](holos/README.md)