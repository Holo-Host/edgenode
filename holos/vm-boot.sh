#!/bin/sh
qemu-system-x86_64 -enable-kvm \
	-smp 2 \
	-m 3G \
	-name "holos" \
	-cpu host \
	-drive file=tmp/vm_system.qcow2,if=virtio \
	-drive file=tmp/vm_data.qcow2,if=virtio \
	-drive file=tmp/holos-0.0.10.iso,format=raw,if=none,id=usb \
	-device usb-storage,drive=usb \
	-nic user,model=virtio \
	-vga virtio \
	-display gtk \
	-boot menu=on \
	-usb
