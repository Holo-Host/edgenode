#!/bin/sh

echo "All your distro are belong to us!"

# Module dependencies are calculated before buildroot compresses the modules
# so all the filenames end up being wrong. Hoping this fixes it.
for kernel in "$1"/lib/modules/*
do
	ver="`basename $kernel`"
	echo "Calculating module dependencies for kernel $ver"
	/sbin/depmod -av -b "$1" "$ver"
done

# Prevent us from trying to mount cgroupfs twice.
rm -f "$1"/etc/init.d/S30cgroupfs
