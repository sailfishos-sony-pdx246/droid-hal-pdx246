#!/bin/sh
# SPDX-FileCopyrightText: Johannes Meyer zum Alten Borgloh
# SPDX-License-Identifier: BSD-3-Clause
#
# Build-time guard and installer for droid-hal-pdx246, run from $ANDROID_ROOT by
# the spec (custom_build_cmds and custom_install_cmds of dhd's droid-hal-device.inc).
#
#   sh rpm/helpers/matched-set.sh check   <device>
#   sh rpm/helpers/matched-set.sh install <device> <buildroot> <kernel_release>
#
# The Sailfish kernel config changes the module ABI (CONFIG_MODVERSIONS: about
# 10,000 export CRCs differ from LineageOS), so the kernel, vendor_boot.img (dtb and
# the first-stage modules in the vendor ramdisk) and vendor_dlkm.img (the
# second-stage modules) only work as one set from one build. "check" stops the
# package build when out/ does not hold such a set, instead of producing packages
# that boot without storage, USB or Wi-Fi. It reads the module release strings
# (vermagic) from the staged modules and from inside both images, so an image left
# over from an older kernel is caught even when file times look fine. It also
# stops when a generated mount unit still names a by-name path or an init property,
# which fixup-mountpoints would have left unresolved. "install" adds
# vendor_dlkm.img and vendor_dlkm.release (the kernel release its modules were
# built for) to the build root for the droid-hal-pdx246-vendor_dlkm package.
#
# "check" also stops when out/ lacks audio.hidl_compat.default.so, which
# hybris-hal does not build: droid-config-pdx246 links the vendor's
# audio.primary.parrot.so name to it, and without it that link dangles and
# audio fails with no build error.
#
# Limits: vermagic names the kernel release, which names the kernel commit
# (CONFIG_LOCALVERSION_AUTO). Builds of one commit with different uncommitted
# configs both end in "-dirty", which is reported as a warning; CRCs are not
# compared. A rebuild that changes only the modules keeps the release; on the
# phone, droid-config's boot_id guard keeps flash-vendor_dlkm.sh from writing
# vendor_dlkm_a in the same boot that rewrote vendor_boot_a.
#
# Needs: sort, tr, sed, od, head, tail, wc, find, install, lz4 (BuildRequires).

set -e

die() {
	echo "matched-set: ERROR: $*" >&2
	exit 1
}

warn() {
	echo "matched-set: WARNING: $*" >&2
}

mode=$1
device=$2
[ -n "$mode" ] && [ -n "$device" ] || die "usage: $0 check|install <device> [<buildroot> <kernel_release>]"
out=out/target/product/$device
[ -d "$out" ] || die "$out not found; run this from \$ANDROID_ROOT after the Android build"

# Release strings of all kernel modules in a byte stream on stdin, one per module.
vermagics() {
	tr '\000' '\n' | sed -n 's/^vermagic=\([^ ]*\).*/\1/p'
}

# check_staged <dir> <expected count> <release>: every .ko in <dir> must carry
# <release>; a different number of modules is only reported.
check_staged() {
	dir=$1
	expected=$2
	release=$3
	[ -d "$dir" ] || die "$dir not found"
	count=0
	bad=0
	for ko in "$dir"/*.ko; do
		[ -f "$ko" ] || continue
		count=$((count + 1))
		vm=$(vermagics < "$ko" | head -n 1)
		if [ "$vm" != "$release" ]; then
			bad=$((bad + 1))
			[ "$bad" -le 5 ] && echo "matched-set:   $ko: vermagic '$vm'" >&2
		fi
	done
	[ "$count" -gt 0 ] || die "no kernel modules in $dir"
	[ "$bad" -eq 0 ] || die "$bad of $count modules in $dir were not built for kernel $release"
	[ "$count" -eq "$expected" ] || warn "$dir has $count modules, expected $expected (fine if the kernel config changed on purpose)"
	echo "matched-set: $dir: $count modules for $release"
}

# check_found <what> <release> <minimum>: reads release strings on stdin.
# A string that is a proper prefix of <release> is a vermagic cut by a file
# fragment boundary inside an ext4 image; it is reported, not fatal.
check_found() {
	what=$1
	release=$2
	minimum=$3
	total=0
	cut=0
	others=
	while read -r vm; do
		total=$((total + 1))
		[ "$vm" = "$release" ] && continue
		case $release in
		"$vm"*) cut=$((cut + 1)) ;;
		*) case " $others " in *" $vm "*) ;; *) others="$others $vm" ;; esac ;;
		esac
	done
	[ -z "$others" ] || die "$what holds modules for other kernels:$others (expected $release). Rebuild it in the Android tree before packaging"
	[ "$total" -ge "$minimum" ] || die "$what: found $total module release strings, expected at least $minimum; is it the right image?"
	[ "$cut" -eq 0 ] || warn "$what: $cut release strings were cut by fragmentation and could not be compared"
	echo "matched-set: $what: $total modules for $release"
}

# The vendor ramdisk of a boot image header v3/v4 vendor_boot.img: it starts at the
# first page after the header and is vendor_ramdisk_size bytes long (all fragments).
vendor_ramdisk() {
	img=$1
	magic=$(head -c 8 "$img")
	[ "$magic" = "VNDRBOOT" ] || die "$img: not a vendor_boot image (magic '$magic')"
	page=$(od -An -t u4 -j 12 -N 4 "$img" | tr -d ' ')
	size=$(od -An -t u4 -j 24 -N 4 "$img" | tr -d ' ')
	hdr=$(od -An -t u4 -j 2096 -N 4 "$img" | tr -d ' ')
	offset=$(( (hdr + page - 1) / page * page ))
	tail -c +$((offset + 1)) "$img" | head -c "$size"
}

check() {
	releases=$(sort -u "$out"/*/*/include/config/kernel.release)
	[ -n "$releases" ] || die "no $out/*/*/include/config/kernel.release; was the kernel built?"
	[ "$(echo "$releases" | wc -l)" -eq 1 ] || die "obj/KERNEL_OBJ and obj/DTB_OBJ disagree on the kernel release: $(echo $releases). dhd would fail copying the kernel"
	release=$releases
	case $release in
	*-dirty) warn "kernel release $release: the kernel tree had uncommitted changes when it was built" ;;
	esac

	for f in kernel vendor_boot.img dtbo.img vendor_dlkm.img; do
		[ -s "$out/$f" ] || die "$out/$f is missing; build: make hybris-hal droidmedia vendor_dlkmimage audio.hidl_compat.default"
	done
	[ -s "$out/system/lib64/hw/audio.hidl_compat.default.so" ] || die "$out/system/lib64/hw/audio.hidl_compat.default.so missing; build: make audio.hidl_compat.default"
	[ -s "$out/system/lib64/libdroidmedia.so" ] || die "$out/system/lib64/libdroidmedia.so missing; build: PORT_ARCH=aarch64 make droidmedia (without PORT_ARCH the target is empty)"
	command -v lz4 >/dev/null || die "lz4 not found (BuildRequires: lz4)"

	check_staged "$out/vendor_ramdisk/lib/modules" 302 "$release"
	check_staged "$out/vendor_dlkm/lib/modules" 351 "$release"

	n=$(ls "$out"/vendor_ramdisk/lib/modules/*.ko | wc -l)
	vendor_ramdisk "$out/vendor_boot.img" | lz4 -dc | vermagics | check_found "$out/vendor_boot.img" "$release" "$n"
	n=$(ls "$out"/vendor_dlkm/lib/modules/*.ko | wc -l)
	vermagics < "$out/vendor_dlkm.img" | check_found "$out/vendor_dlkm.img" "$release" $((n * 9 / 10))

	# Mount units generated by dhd's makefstab and rewritten by fixup-mountpoints.
	if ls tmp/units/*.mount >/dev/null 2>&1; then
		unresolved=$(grep -l -e '^What=.*/by-name/' -e '^What=.*\$' tmp/units/*.mount || true)
		[ -z "$unresolved" ] || die "mount units with an unresolved source (add the partition to fixup-mountpoints or the mount point to makefstab_skip_entries): $(echo $unresolved)"
		partlabel=$(grep -l '^What=/dev/disk/by-partlabel/' tmp/units/*.mount || true)
		[ -z "$partlabel" ] || warn "by-partlabel mount units (dhd newer than be67bbc?); slotted partitions need their _a label: $(echo $partlabel)"
		echo "matched-set: mount units: $(cd tmp/units && echo *.mount)"
	fi

	echo "matched-set: kernel $release, vendor_boot.img and vendor_dlkm.img form one set; audio.hidl_compat.default.so and libdroidmedia.so present"
}

install_images() {
	buildroot=$3
	release=$4
	[ -n "$buildroot" ] && [ -n "$release" ] || die "install needs <buildroot> <kernel_release>"
	[ -f "$buildroot/boot/kernel-$release" ] || die "$buildroot/boot/kernel-$release missing; dhd's kernel install step did not run as expected"
	install -D -m 644 "$out/vendor_dlkm.img" "$buildroot/boot/vendor_dlkm.img"
	# For droid-config's flash-vendor_dlkm.sh: it flashes the image only once the
	# running kernel (uname -r) is the one the modules were built for.
	echo "$release" > "$buildroot/boot/vendor_dlkm.release"
	chmod 644 "$buildroot/boot/vendor_dlkm.release"
	echo "matched-set: installed /boot/vendor_dlkm.img and /boot/vendor_dlkm.release for kernel $release"
}

case $mode in
check) check ;;
install) install_images "$@" ;;
*) die "unknown mode $mode" ;;
esac
