# Holo Operating System

## Overview

This module consists of tools to build an operating system dedicated to running Holochain containers. It is currently x86_64 only, but could easily be ported to other architectures. It ought to run on most x86_64 systems, but the primary platforms tested are:

* Holoport
* Holoport Plus
* KVM on Linux

Under the hood, this Makefile will:
1. Download the [Buildroot](https://buildroot.org) build system,
2. Configure it with a Holo-specific configuration (`holos-buildroot-2025.08.config`)
3. Build everything from source, including a Linux kernel using a Holo-specific kernel config (`kernel-config-x86_64.config`)

Once the kernel and initrd are built, the Makefile then assembles it into a hybrid-bootable ISO image (meaning that it can be booted as an ISO9660 CD-ROM image, or as an x86 MBR image on a USB stick or other block device).

## Booting

This Linux distribution can be booted and run in the same way as any other Linux distribution. Write the ISO image to a CD-ROM, an MMC card, USB stick or other block device and tell your hardware to boot from that device. The kernel and initrd in the `boot/` directory could also be used to PXE boot the OS, for those familiar with that process.

This initial commit also doesn't set a root password, which is blank while we're developing and testing.

The operating system runs entirely in memory, and does not currently install or write to any permanent storage. This will change in the near future.

## Configure Networking

As of this initial commit, there is no automatic configuration present. In the meantime, to bring up the network on a Holoport or Holoport Plus, the following commands ought to suffice:

```
modprobe r8169 && ifconfig eth0 up && udhcpc eth0
```

This loads the kernel driver for the network interface, and uses DHCP to configure it. The same can also be done for KVM VMs with:

```
modprobe virtio_net && ifconfig eth0 up && udhcpc eth0
```

Other hypervisors or hardware platforms will likely work if you can identify your network interface driver.

### Wi-Fi

The `wpa_supplicant` package is present, but we haven't yet included any automatic configuration of Wi-Fi networks. This will come soon, but those familiar with `wpa_supplicant` will likely find success.

## Development

### Make Targets

```
Make targets:

	- help		This output
	- all		Build whole set of artifacts
	- iso		Build hybrid-boot ISO
	- run		Boot the ISO image inside KVM with QEMU on Linux
	- distclean	Remove all build artifacts
	- clean		Remove build artifacts, keeping downloaded sources
```

### Modifying OS Userspace

This operating system is deliberately minimal, and uses the MUSL C library for size and portability. It can be extended to include other packages and tools. The easiest way to make changes is to:

1. Build the current version using `make iso`
2. Use the buildroot `menuconfig` target to make the desired changes using `make -C tmp/buildroot-2025.08 O=../br-build menuconfig`.
3. Replace the holos configuration file with the buildroot-generated configuration file using `cp tmp/br-build/.config holos-buildroot-2025.08.config`
4. Build the changes using `make iso`

