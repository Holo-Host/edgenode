# Version string
HOLOS_VERSION := 0.0.1

# We need some temporary scratch space for build artifacts. Everything generated
# by this build process will be under this tree and we shouldn't be modifying
# anything outside that tree.
#
# It defaults to a relative path to keep the whole build self-contained.
TMPDIR := tmp

# We use buildroot to handle building all of our packages and kernel from a 
# single configuration file that we maintain. Some work is involved in updating
# the configuration from one version to the next, but generally not a lot.
BUILDROOT_VERSION := 2025.08
BUILDROOT_URL := https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz
BUILDROOT_CONFIG := holos-buildroot-${BUILDROOT_VERSION}.config
BR_BUILD_DIR := ${TMPDIR}/br-build

help:
	@echo "Make targets:"
	@echo "	- all		Build whole set of artifacts"
	@echo "	- iso		Build hybrid-boot ISO"
	@echo "	- distclean	Remove all build artifacts"

# Make sure various directories and configuration files are all in the right place
${TMPDIR}:
	mkdir -p ${TMPDIR}

${TMPDIR}/buildroot-${BUILDROOT_VERSION}.tar.xz: ${TMPDIR}
	curl -q -o $@ ${BUILDROOT_URL}

${TMPDIR}/buildroot-${BUILDROOT_VERSION}: ${TMPDIR}/buildroot-${BUILDROOT_VERSION}.tar.xz
	tar Jxf $< -C ${TMPDIR}

${BR_BUILD_DIR}: ${TMPDIR}
	mkdir -p ${BR_BUILD_DIR}

# TODO: This shouldn't just copy the file. There are things we want to modify within.
${BR_BUILD_DIR}/.config: ${BR_BUILD_DIR} ${BUILDROOT_CONFIG}
	cp ${BUILDROOT_CONFIG} $@

# The kernel is one of the artifacts built
${BR_BUILD_DIR}/images/bzImage: ${BR_BUILD_DIR}/.config ${TMPDIR}/buildroot-${BUILDROOT_VERSION}
	make -C tmp/buildroot-${BUILDROOT_VERSION} O=../br-build

${TMPDIR}/isoroot/boot: ${TMPDIR}
	mkdir -p $@

# There's probably some GNU Make magic incantation to handle this in one target, but I'm
# too lazy to read the docs. We need the kernel and initrd artifacts from the buildroot
# build, and also some of the host-side syslinux binaries (guest-side binaries would also
# work too, but this is a version-independent source path).
${TMPDIR}/isoroot/boot/bzImage: ${BR_BUILD_DIR}/images/bzImage
	cp $< $@
${TMPDIR}/isoroot/boot/rootfs.cpio.gz: ${BR_BUILD_DIR}/images/rootfs.cpio.gz
	cp $< $@
${TMPDIR}/isoroot/boot/isolinux.bin: ${BR_BUILD_DIR}/host/share/syslinux/isolinux.bin
	cp $< $@
${TMPDIR}/isoroot/boot/ldlinux.c32: ${BR_BUILD_DIR}/host/share/syslinux/ldlinux.c32
	cp $< $@

# Now that we have the artifacts we need, build a bootable hybrid ISO artifact
${TMPDIR}/holos-${HOLOS_VERSION}.iso: ${TMPDIR}/isoroot/boot/bzImage ${TMPDIR}/isoroot/boot/rootfs.cpio.gz ${TMPDIR}/isoroot/boot/isolinux.bin ${TMPDIR}/isoroot/boot/ldlinux.c32
	cd ${TMPDIR}/isoroot && xorriso -as mkisofs \
		-r \
		-V HolOS \
		-o $@ \
		-b boot/isolinux.bin \
		-c boot/boot.cat \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		.

iso: ${TMPDIR}/holos-${HOLOS_VERSION}.iso

distclean:
	rm -rf ${TMPDIR}

all: iso

