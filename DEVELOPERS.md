# Edge Node Developers Guide
## Development Environment Setup

**Container Setup**

This guide provides step-by-step instructions for setting up a development environment for the Holochain Edge Node container. The container is built using Wolfi Base and includes all necessary tools for developing, testing, and running Holochain applications.

**Prerequisites**

- Docker installed and running on your system
- Git (for cloning the repository)
- Basic knowledge of Docker commands and containers

**Development Environment Setup**

1. **Clone the Repository**

```bash
git clone https://github.com/Holo-Host/edgenode.git
cd edgenode
```

2. **Build the Docker Image**

The container is defined in [`docker/Dockerfile`](docker/Dockerfile:1). To build the image locally:

```bash
cd docker
docker build -t local-edgenode .
cd ..
```

3. **Run the Container in Development Mode**

For development, you'll want to run the container with interactive shell access and persistent storage:

```bash
# Create a directory for persistent data
mkdir -p ./holo-data-dev

# Run the container in interactive mode
docker run --name edgenode-dev -it \
  -v $(pwd)/holo-data-dev:/data \
  -p 4444:4444 \
  local-edgenode
```

4. **Access the Container Shell**

Once the container is running, access it interactively:

```bash
docker exec -it edgenode-dev /bin/sh
```

Inside the container, switch to the nonroot user:

```bash
su - nonroot
```

**ISO Setup**

HolOS is a minimal Linux distribution specifically designed to run Holochain containers. It's built using the Buildroot system, creating a complete Linux system from source code.

**Prerequisites**

- Basic knowledge of Makefiles and the build process.

**Development Environment Setup**

The Makefile automates the following steps:

1. Downloads Buildroot source
2. Builds the Rust-based `holos-config` tool
3. Copies configuration files and overlays
4. Builds the Linux kernel with custom configuration
5. Creates initramfs (rootfs.cpio.gz)
6. Assembles everything into a hybrid ISO image

The system can be used in several ways:

1. **Boot from USB/CD**: Write the ISO to a bootable device
2. **PXE Boot**: Use the kernel and initrd from the boot/ directory
3. **Virtual Machine**: Use `make run` to boot in KVM with QEMU

__happ_config_file Utility Setup__

**Prerequisites**

1. **Rust Programming Language**: The project requires Rust to be installed on your system. You can install Rust by following the instructions at [rustup.rs](https://rustup.rs/).
2. **Cargo**: Cargo is Rust's package manager and build tool. It comes bundled with the Rust installation.

**Setup Steps**

1. **Navigate to the project directory**:

```bash
cd tools/happ_config_file
```

2. **Build the project**:

```bash
cargo build --release
```

This will compile the project and create the binary at `target/release/happ_config_file`.