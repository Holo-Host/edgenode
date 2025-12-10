# Holo Operating System

## Overview

This module consists of tools to build an operating system dedicated to running Holochain containers. It is currently x86_64 only, but could easily be ported to other architectures. It ought to run on most x86_64 systems, but the primary platforms tested are:

* HoloPort
* HoloPort Plus
* KVM on Linux

Under the hood, this Makefile will:
1. Download the [Buildroot](https://buildroot.org) build system,
2. Configure it with a Holo-specific configuration (`holos-buildroot-2025.08.config`)
3. Build everything from source, including a Linux kernel using a Holo-specific kernel config (`kernel-config-x86_64.config`)

Once the kernel and initrd are built, the Makefile then assembles it into a hybrid-bootable ISO image (meaning that it can be booted as an ISO9660 CD-ROM image, or as an x86 MBR image on a USB stick or other block device).

## Booting

This Linux distribution can be booted and run in the same way as any other Linux distribution. Burn the ISO image to a USB, an MMC card, USB stick or other block device and tell your hardware to boot from that device. The kernel and initrd in the `boot/` directory could also be used to PXE boot the OS, for those familiar with that process.

HolOS doesn't set a root password, which is blank.

### Via Make Target

There is a `make run` target in the Makefile that will use kvm/qemu on Linux to boot the image in a small VM, using the _curses_ display driver. This gives you the VM console in your terminal window, making is suitable over things like `ssh(1)`. To quit and shut the VM down, hit _Alt+2_ to change to the qemu monitor, and then type `quit` and hit enter. For this, you will want to boot using the `text` isolinux boot target. The default starts a VGA framebuffer console at 1024x768.

### Wi-Fi

The `wpa_supplicant` package is present. We've also added a whole host of new WLAN drivers, especially for Realtek chipsets. While a full, user-friendly interface for configuring WiFi this is not, this critical background work paves the way for much broader hardware support in the near future.

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


## Known Issues

1. The Makefile dependencies could use some fixing. After a full and complete build, re-running `make iso`, or even `make run` will still see certain targets re-run.
2. The Makefile has some copy/pasted boilerplate code for copying files that could probably be replaced

