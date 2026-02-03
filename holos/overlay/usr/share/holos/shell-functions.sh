#!/bin/zsh
# This is just a small collection of common shell code used by things like the HolOS
# installer script and updater script. Will eventually (hopefully) be replaced with
# Rust code directly added to holos-config.

# Common barf code.
die(){
	echo "$*" 1>&2
	exit 1
}

holos_log(){
	logger -t "$1" "$@"
}

# This creates an initrd image for an installed system. It is currently overkill and copies
# all kernel modules into the initrd (and not the firmware required by certain modules)
# instead of just the bare minimum required to get to the root filesystem.
#
# This assumes that it's run from the root of the filesystem it's creating the initrd for.
holos_mkinitrd() {
	# This is executed from the root directory of the destination
	mkdir tmp/initrd-root
	for i in bin dev etc lib mnt proc sbin sys usr usr/bin usr/sbin
	do
		mkdir tmp/initrd-root/$i
	done
	cp bin/busybox tmp/initrd-root/bin
	cp -a lib/{ld-musl-x86_64,libc}* tmp/initrd-root/lib
	chroot tmp/initrd-root /bin/busybox --install

	cp bin/ramdisk-init tmp/initrd-root/init && chmod a+rx tmp/initrd-root/init

	# We actually only need the storage drivers. That can be an optimisation for later.
	echo "Copying kernel modules"
	cp -a lib/modules tmp/initrd-root/lib

	echo "Packing initial ramdisk"
	( cd tmp/initrd-root ; find . -print0 | cpio --null --create --format=newc | bzip2 -zc > ../../boot/holos-initrd.img )
}

