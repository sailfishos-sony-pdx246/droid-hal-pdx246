# SPDX-FileCopyrightText: Johannes Meyer zum Alten Borgloh
# SPDX-License-Identifier: BSD-3-Clause
#
# droid-hal-pdx246: the Sailfish OS droid-hal packages for the Sony Xperia 10 VI
# (pdx246; XQ-ES54 and XQ-ES72), built from the hybris-23.2 (Android 16) tree.
# Checked out at $ANDROID_ROOT/rpm, with mer-hybris/droid-hal-device at rpm/dhd
# (pinned to be67bbc, see SUBMODULES.md). After the Android build
#   make hybris-hal droidmedia vendor_dlkmimage audio.hidl_compat.default
# build from $ANDROID_ROOT with
#   rpm/dhd/helpers/build_packages.sh -d
# README.md has the whole build sequence. The macros are documented in
# dhd/droid-hal-device.inc; NOTES.md gives the evidence for every value set or
# left out here.
#
# rpm expands macros in comments too, so no comment in this file may contain a
# percent sign. To disable a macro, delete its line; commenting it out is not
# enough.

%define device pdx246
%define vendor sony

%define vendor_pretty Sony
%define device_pretty Xperia 10 VI

%define droid_target_aarch64 1

# hybris-boot.img and hybris-recovery.img come from droid-hal-img-boot-pdx246
# (mer-hybris/hybris-initrd, LVM root), which itself builds the packages
# droid-hal-pdx246-img-boot and droid-hal-pdx246-img-recovery. Without these two
# defines this spec would build packages of the same names from the Android-built
# images. The img-boot package registers flash-bootimg.sh on upgrade itself, so
# enable_kernel_update is deliberately not defined: in dhd it only acts on the
# img-boot package this spec no longer builds.
%define have_custom_img_boot 1
%define have_custom_img_recovery 1

# vendor_boot.img (cmdline, dtb, bootconfig and the 302 first-stage modules) and
# dtbo.img are taken from this Android build, because their modules and dtb must
# match the Sailfish kernel. Packages droid-hal-pdx246-vendor_boot and
# droid-hal-pdx246-kernel-dtbo; on upgrade they register flash-vendor_boot.sh and
# flash-dtbo.sh from droid-config-pdx246-flashing. have_custom_vendor_boot is not
# defined: hybris-initrd does not build vendor_boot here.
%define enable_vendor_boot_update 1
%define enable_dtbo_update 1

# installable_zip is deliberately not defined. dhd tests whether it is defined,
# not its value, and then copies hybris-updater-script, which hybris-boot only
# builds when an fstab has a /boot line; fstab.default of pdx246 has none.

# Mount units: dhd turns the mounts of the fstab files and of the system,
# vendor and root init rc files in out/ into systemd units. The hybris-hal out
# installs only init.qti.kernel.rc under vendor/etc/init/hw, so the result is
# 10 units: config, dev-binderfs, linkerconfig, metadata (sda54),
# mnt-vendor-persist (sda3), mnt-vendor-qmcs (sda63), mnt-vm,
# vendor-bt_firmware (sda68), vendor-dsp (sda71), vendor-firmware_mnt (sda67).
# Mounts in the other vendor rc files (for example /mnt/vendor/spunvm) are run
# by droid-hal-init at runtime from the rc files of the LineageOS vendor
# partition.
# Skipped here, with effect on the hybris-hal out:
#   the six logical partitions of super (system, system_ext, product, vendor,
#     vendor_dlkm, odm): no Android first-stage init runs, so
#     droid-config-pdx246 maps super and mounts them from
#     /dev/mapper/dynpart-*_a.
#   /firmware: from root/init.recovery.qcom.rc (recovery only); its source
#     contains an init property that a mount unit cannot expand.
#   /vendor/vm-system: vm-bootsys_a holds no ext4 file system (the LineageOS
#     boot log shows Android init skipping it for "invalid magic"), and nothing
#     in Sailfish uses it.
# Skipped, but only found in a LineageOS out (inert on the hybris-hal out;
# kept in case a later build installs those rc files):
#   / and /system_root, as in the reference port.
#   /dev/blkio: a cgroup v1 mount from init.qcom.rc; systemd owns the cgroups,
#     as for the /dev/cpuctl, /dev/cpuset and /dev/stune that dhd skips itself.
#   /dev/usb-ffs/aoa, /dev/usb-ffs/ctrl, /dev/ffs-diag, /dev/ffs-diag-1 and
#     /dev/ffs-diag-2: functionfs mounts of Android's USB gadget from
#     init.qcom.usb.rc, like the adb, mtp and ptp ones dhd skips; usb-moded owns
#     the gadget, and the two diag units would get names systemd refuses.
# The slotted firmware partitions (modem, dsp, bluetooth) stay: dhd be67bbc
# passes their by-name sources through hybris-boot's fixup-mountpoints, whose
# pdx246 entry maps the bare names to slot a (sda67, sda71, sda68).
%define makefstab_skip_entries / /system_root /system /system_ext /product /vendor /vendor_dlkm /odm /firmware /vendor/vm-system /dev/blkio /dev/usb-ffs/aoa /dev/usb-ffs/ctrl /dev/ffs-diag /dev/ffs-diag-1 /dev/ffs-diag-2

# Symlinks the Android build puts in its root directory that no other droid-hal
# package owns. They go to droid-hal-pdx246-detritus; every entry must exist in
# out/target/product/pdx246/root, or the files section fails.
%define straggler_files \
/adb_keys\
/bugreports\
/cache\
/d\
/sdcard\
%{nil}

# Written to android-config.h in droid-hal-pdx246-devel. pdx246 has an Adreno GPU
# (vendor libllvm-glnext.so); libhybris then hooks that library's malloc calls,
# the workaround dhd documents for the Sailfish Browser shader crash on 64-bit
# Adreno devices.
%define android_config \
#define WANT_ADRENO_QUIRKS 1\
%{nil}

# matched-set.sh reads the vendor ramdisk of vendor_boot.img, which is lz4.
%define custom_build_requires BuildRequires: lz4

# After dhd's build step: stop unless kernel, vendor_boot.img and vendor_dlkm.img
# come from one kernel build, and unless every mount unit source is resolved.
%define custom_build_cmds \
sh rpm/helpers/matched-set.sh check %{device}\
%{nil}

# After dhd's install step: add vendor_dlkm.img and vendor_dlkm.release for the
# vendor_dlkm package below.
# kernel_release is the shell variable dhd's install step sets.
%define custom_install_cmds \
sh rpm/helpers/matched-set.sh install %{device} "$RPM_BUILD_ROOT" "$kernel_release"\
%{nil}

%include rpm/dhd/droid-hal-device.inc

# vendor_dlkm.img is not handled by dhd. It is the image of the vendor_dlkm
# logical partition in super, flashed to vendor_dlkm_a from fastbootd and mounted
# by droid-config-pdx246 at /vendor_dlkm, where Android's vendor_modprobe.sh loads
# the second-stage modules. Its modules must match the kernel, so it is built
# and versioned together with vendor_boot; droid-hal-pdx246-img-boot requires it
# at the same version-release as vendor_boot and kernel-dtbo.
# The sub-package below follows dhd's vendor_boot sub-package
# (droid-hal-device.inc at be67bbc, lines 364-370, 1169-1177 and 1327-1332;
# dhd is licensed BSD).
%package vendor_dlkm
Summary: The vendor_dlkm img for droid-hal device: %{rpm_device}
Requires: droid-hal-%{rpm_device}-vendor_boot = %{version}-%{release}
Requires: oneshot
Requires(post): droid-config-flashing
%{_oneshot_requires_post}

%description vendor_dlkm
The vendor_dlkm.img (second-stage kernel modules) from the same build as the
kernel in droid-hal-pdx246-kernel and the vendor_boot.img in
droid-hal-pdx246-vendor_boot, and vendor_dlkm.release, the kernel release its
modules were built for. Kernel, vendor_boot and vendor_dlkm only work as one
set; flash them together.

%post vendor_dlkm
# Installation at image creation does nothing; the image is flashed with fastboot.
# On upgrade the new modules must reach vendor_dlkm_a at the first boot of the
# new set. flash-vendor_dlkm.sh (droid-config-pdx246-flashing) writes only when
# uname -r equals /boot/vendor_dlkm.release and boot_a, vendor_boot_a and dtbo_a
# (vendor_boot_a) was not rewritten during the current boot, before vendor_dlkm is mounted, and
# verifies the write; otherwise it exits non-zero and stays registered. See
# NOTES.md of droid-hal-pdx246 (D7).
if [ $1 -ne 1 ] ; then
  if [ -x /var/lib/platform-updates/flash-vendor_dlkm.sh ] ; then
    add-preinit-oneshot /var/lib/platform-updates/flash-vendor_dlkm.sh || :
  else
    echo "droid-hal-pdx246-vendor_dlkm: no flash-vendor_dlkm.sh in droid-config;" >&2
    echo "flash /boot/vendor_dlkm.img to vendor_dlkm_a from fastbootd before rebooting." >&2
  fi
fi

%files vendor_dlkm
%defattr(644,root,root,-)
/boot/vendor_dlkm.img
/boot/vendor_dlkm.release
