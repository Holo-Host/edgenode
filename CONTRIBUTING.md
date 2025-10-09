# Contributing Guide

* [New Contributor Guide](#contributing-guide)
   * [Ways to Contribute](#ways-to-contribute)
   * [Find an Issue](#find-an-issue)
   * [Ask for Help](#ask-for-help)
   * [Pull Request Lifecycle](#pull-request-lifecycle)
   * [Development Environment Setup](#development-environment-setup)
   * [Sign Your Commits](#sign-your-commits)
   * [Pull Request Checklist](#pull-request-checklist)

Welcome! We are glad that you want to contribute to our project! 💖

As you get started, you are in the best position to give us feedback on areas of
our project that we need help with including:

* Problems found during setting up a new developer environment
* Gaps in our Quickstart Guide or documentation
* Bugs in our automation scripts

If anything doesn't make sense, or doesn't work when you run it, please open a
bug report and let us know!

## Ways to Contribute

[Instructions](https://contribute.cncf.io/maintainers/github/templates/required/contributing/#ways-to-contribute)

We welcome many different types of contributions including:

* New features
* Builds, CI/CD
* Bug fixes
* Documentation
* Issue Triage
* Answering questions on the [Holo Forum](https://forum.holo.host/)
* Web design
* Communications / Social Media / Blog Posts
* Release management

Not everything happens through a GitHub pull request. Please come to our
[Holo Huddles](https://calendly.com/rob-lyon-holo/holo-huddle-edge-node-support) or [contact us on the Holo Forum](https://forum.holo.host/) and let's discuss how we can work
together.

### Come to Meetings

Absolutely everyone is welcome to come to any of our meetings. You never need an
invite to join us. In fact, we want you to join us, even if you don’t have
anything you feel like you want to contribute. Just being there is enough!

You can find out more about our meetings [here](https://forum.holo.host/t/regular-holo-huddle-holo-forge-calls-with-rob/7713). You don’t have to turn on
your video. The first time you come, introducing yourself is more than enough.
Over time, we hope that you feel comfortable voicing your opinions, giving
feedback on others’ ideas, and even sharing your own ideas, and experiences.

## Find an Issue

We have good first issues for new contributors and help wanted issues suitable
for any contributor. [good first issue](https://github.com/Holo-Host/edgenode/issues?q=is%3Aissue%20state%3Aopen%20label%3A%22good%20first%20issue%22) has extra information to
help you make your first contribution. [help wanted](https://github.com/Holo-Host/edgenode/issues?q=state%3Aopen%20label%3A%22help%20wanted%22) are issues
suitable for someone who isn't a core maintainer and is good to move onto after
your first pull request.

Sometimes there won’t be any issues with these labels. That’s ok! There is
likely still something for you to work on. If you want to contribute but you
don’t know where to start or can't find a suitable issue, you can [submit an issue](https://github.com/Holo-Host/edgenode/issues/new) introducing yourself with your skillsets and interests so we can find a good fit for you.

Once you see an issue that you'd like to work on, please post a comment saying
that you want to work on it. Something like "I want to work on this" is fine.

## Ask for Help

The best way to reach us with a question when contributing is to ask on:

* The original github issue

## Pull Request Lifecycle

[Instructions](https://contribute.cncf.io/maintainers/github/templates/required/contributing/#pull-request-lifecycle)

- Please comment on an existing issue or create a new one to let us know what it is you want to work on and outline your proposed solution, so we can ensure your pull request will match the requirements for our project.
- Fork the repo, and submit a pull request when you are ready.
- We will review the pull request and may ask for revisions before we approve it.
- Once we approve it, we will merge the pull request.

## Development Environment Setup

**Container Setup**

This guide provides step-by-step instructions for setting up a development environment for the Holochain Edge Node container. The container is built using Wolfi Base and includes all necessary tools for developing, testing, and running Holochain applications.

**Prerequisites**

- Docker installed and running on your system
- Git (for cloning the repository)
- Basic knowledge of Docker commands and containers

**Development Environment Setup**

1.  **Clone the Repository**

    ```bash
    git clone https://github.com/Holo-Host/edgenode.git
    cd edgenode
    ```

2.  **Build the Docker Image**

    The container is defined in [`docker/Dockerfile`](docker/Dockerfile:1). To build the image locally:

    ```bash
    cd docker
    docker build -t local-edgenode .
    cd ..
    ```

3.  **Run the Container in Development Mode**

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

4.  **Access the Container Shell**

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
1.  Downloads Buildroot source
2.  Builds the Rust-based `holos-config` tool
3.  Copies configuration files and overlays
4.  Builds the Linux kernel with custom configuration
5.  Creates initramfs (rootfs.cpio.gz)
6.  Assembles everything into a hybrid ISO image

The system can be used in several ways:
1.  **Boot from USB/CD**: Write the ISO to a bootable device
2.  **PXE Boot**: Use the kernel and initrd from the boot/ directory
3.  **Virtual Machine**: Use `make run` to boot in KVM with QEMU

**happ_config_file Utility Setup**

**Prerequisites**

1.  **Rust Programming Language**: The project requires Rust to be installed on your system. You can install Rust by following the instructions at [rustup.rs](https://rustup.rs/).
2.  **Cargo**: Cargo is Rust's package manager and build tool. It comes bundled with the Rust installation.

**Setup Steps**

1.  **Navigate to the project directory**:

    ```bash
    cd tools/happ_config_file
    ```

2.  **Build the project**:

    ```bash
    cargo build --release
    ```

    This will compile the project and create the binary at `target/release/happ_config_file`.

## Sign Your Commits

[Instructions](https://contribute.cncf.io/maintainers/github/templates/required/contributing/#sign-your-commits)

⚠️ **Keep either the DCO or CLA section depending on which you use**

### DCO

Licensing is important to open source projects. It provides some assurances that
the software will continue to be available based under the terms that the
author(s) desired. We require that contributors sign off on commits submitted to
our project's repositories. The [Developer Certificate of Origin
(DCO)](https://probot.github.io/apps/dco/) is a way to certify that you wrote and
have the right to contribute the code you are submitting to the project.

You sign-off by adding the following to your commit messages. Your sign-off must
match the git user and email associated with the commit.

    This is my commit message
    
    Signed-off-by: Your Name <your.name@example.com>

Git has a `-s` command line option to do this automatically:

    git commit -s -m 'This is my commit message'

If you forgot to do this and have not yet pushed your changes to the remote
repository, you can amend your commit with the sign-off by running

    git commit --amend -s 

### CLA

We require that contributors have signed our Contributor License Agreement (CLA).

⚠️ **Explain how to sign the CLA**

## Pull Request Checklist

When you submit your pull request, or you push new commits to it, our automated
systems will run some checks on your new code. We require that your pull request
passes these checks, but we also have more criteria than just that before we can
accept and merge it. We recommend that you check the following things locally
before you submit your code:

⚠️ **Create a checklist that authors should use before submitting a pull request**