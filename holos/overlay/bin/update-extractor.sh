#!/bin/zsh
# Ideally, this would be baked into the Rust code that is `holos-config`, but in the interest
# of time, we'll do this here for now.

. /usr/share/holos/shell-functions.sh

source_media="$1"
destination_directory="$2"

# Do a little input sanity checking to prevent people from accidentially shooting themselves in
# the foot.

# args present?
[ -z "$source_media" ] && die "Need to specify source media\nUsage: $0 <source_media> <destination_directory"
[ -z "$destination_directory" ] && die "Need to specify destination directory\nUsage: $0 <source_media> <destination_directory"

# Is the source media likely one of ours?
eval `blkid -o export -p "$source_media"`
if [ "$LABEL" != "HolOS-install" ]
then
	die "Source media has label '$LABEL', when we were expecting 'HolOS-install'"
fi

block_dev="`grep \" $destination_directory \" /proc/mounts 2>/dev/null | cut -f 1 -d ' '`"
echo "Block device: $block_dev"
# is the destination the root of a filesystem?
[ -z "$block_dev" ] && die "Directory \"$destination_directory\" should be a mounted filesystem root, and not a subdirectory"

# This is a hack that assumes flip and flop are on the same root filesystem. It would be
# better to assume UEFI and manage bootable operating systems that way.
boot_dev=`echo $block_dev | sed -e 's/[0-9]*$//'`

# We also label the system flip and system flip volumes as destinations for the HolOS
# root filesystem. Let's check that we're being told to use one of those before we try to 
# remove or overwrite anything.
eval `blkid -o export -p $block_dev`
if [ "$LABEL" != "HolOS-sys-flip" -a "$LABEL" != "HolOS-sys-flop" ]
then
	die "Destination filesystem has label '$LABEL'. Was expecting HolOS-sys-flip or HolOS-sys-flop."
fi

echo "Writing update to $LABEL filesystem"

# Handle the flip-vs-flop partitions. This isn't ideal. It makes assumptions about the GRUB
# naming of the BIOS devices. This will work fine while the filesystem layout remains on the
# first drive and the first two partitions are the flip and flop partitions.
#
# Once we allow the installer to select which drives have which partitions are created on,
# we'll need to update this to be more sophisticated.
if [ "$LABEL" == "HolOS-sys-flip" ]
then
	PREVIOUS_LABEL="HolOS-sys-flop"
	BOOT_DEV="hd0,1"
	PREVIOUS_BOOT_DEV="hd0,2"

else
	PREVIOUS_LABEL="HolOS-sys-flip"
	BOOT_DEV="hd0,2"
	PREVIOUS_BOOT_DEV="hd0,1"
fi

modprobe loop ; modprobe iso9660
mkdir -p /tmp/mnt
mount -o loop -t iso9660 "$source_media" /tmp/mnt &&
rm -rf "$destination_directory"/* &&
bzcat "/tmp/mnt/boot/rootfs.cpio.bz2" | cpio -di -D "$destination_directory" --quiet &&
cp "/tmp/mnt/boot/bzImage" "$destination_directory/boot/" ||
die "Failed to unpack update source media."

# Here, we set up GRUB on the updated root filesystem to boot the updated version by default,
# but also provide a secondary menu option to boot into the previous version on the previous
# root filesystem.
cat > $destination_directory/boot/grub/grub.cfg <<EOF
set default="0"
set timeout="5"

menuentry "HolOS `cat $destination_directory/etc/holos-version`" {
	set root($BOOT_DEV)
	linux /boot/bzImage root=LABEL="$LABEL" ro vga=791
	initrd /boot/holos-initrd.img
}
menuentry "HolOS `cat /etc/holos-version`" {
	set root($PREVIOUS_BOOT_DEV)
	linux /boot/bzImage root=LABEL="$PREVIOUS_LABEL" ro vga=791
	initrd /boot/holos-initrd.img
}
EOF

for i in dev proc sys
do
	mount --bind /$i $destination_directory/$i
done

# Copy any local config changes over.
(
cp /etc/holos/configs/local.yaml $destination_directory/holos/configs/local.yaml
cp -a /root/.ssh $destination_directory/root
) 2>/dev/null

chroot $destination_directory depmod -a
chroot $destination_directory grub-install $boot_dev
(
	cd $destination_directory
	holos_mkinitrd
)

for i in dev proc sys
do
	umount $destination_directory/$i
done
umount /tmp/mnt

echo "Done"
