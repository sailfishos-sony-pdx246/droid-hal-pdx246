<!--
SPDX-FileCopyrightText: Johannes Meyer zum Alten Borgloh
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# droid-hal-pdx246

The droid-hal packaging for the Sailfish OS port to the Sony Xperia 10 VI
(pdx246; XQ-ES54 and XQ-ES72; SM6450 "parrot"). It packages the Android 16 side
built from the mer-hybris `hybris-23.2` tree with the pdx246 LineageOS 23.2 device
repos: droid-hal-init, the Android system binaries and libraries, the mount units,
the udev rules, the headers for libhybris, the kernel and its modules, and the
kernel-dependent images `vendor_boot.img`, `dtbo.img` and `vendor_dlkm.img`.

Unofficial community port, not affiliated with Jolla or Sony.

## Layout

This repository is checked out at `$ANDROID_ROOT/rpm`:

| path | what |
|---|---|
| `droid-hal-pdx246.spec` | the spec; `build_packages.sh -d` builds `rpm/droid-hal-$DEVICE.spec` |
| `dhd/` | submodule mer-hybris/droid-hal-device, pinned to `be67bbc` (SUBMODULES.md) |
| `helpers/img2simg.mk`, `helpers/simg2img.mk` | dhd picks these up from `rpm/helpers/` instead of its own; they build the sparse tools with C++17, which Android 16's libsparse needs |
| `helpers/matched-set.sh` | build-time guard that kernel, vendor_boot and vendor_dlkm come from one kernel build and that `audio.hidl_compat.default.so` was built; installs `vendor_dlkm.img` |
| `NOTES.md` | every decision with its evidence, open TODOs, provenance |

The other adaptation repos: `hybris/droid-configs` (droid-config-pdx246;
submodule droid-hal-configs at 1dae7f2), `hybris/droid-hal-version-pdx246`
(droid-hal-version at 09c2745), and `hybris/mw/droid-hal-img-boot-pdx246` (the
LVM boot image from mer-hybris/hybris-initrd at 7b972b6).

## Packages

| package | content |
|---|---|
| `droid-hal-pdx246` | droid-hal-init, `/usr/libexec/droid-hybris/system` (with `lib64/hw/audio.hidl_compat.default.so`), mount units, udev rules |
| `droid-hal-pdx246-devel`, `-users`, `-tools`, `-detritus` | headers, Android users and groups, mkbootimg/simg2img/img2simg, stray root symlinks |
| `droid-hal-pdx246-kernel` | `/boot/kernel-<release>`, `/boot/dtb.img` |
| `droid-hal-pdx246-kernel-modules` | the 351 modules in `/lib/modules/<release>` (only a build input for img-boot, which ships them; keep it out of the pattern) |
| `droid-hal-pdx246-kernel-dtbo` | `/boot/dtbo.img` |
| `droid-hal-pdx246-vendor_boot` | `/boot/vendor_boot.img`: cmdline, dtb, bootconfig, 302 first-stage modules |
| `droid-hal-pdx246-vendor_dlkm` | `/boot/vendor_dlkm.img` (second-stage modules) and `/boot/vendor_dlkm.release` |

`hybris-boot.img` and `hybris-recovery.img` are not built here
(`have_custom_img_boot`, `have_custom_img_recovery`); droid-hal-img-boot-pdx246
builds `droid-hal-pdx246-img-boot` and `-img-recovery`.

## Building

Placeholders: `$ANDROID_ROOT` is the `hybris-23.2` Android tree, with this
repository at `$ANDROID_ROOT/rpm`.

1. Android side, on the host (not in HABUILD), in `$ANDROID_ROOT`, with the
   `hybris-23.2` branches of `kernel/sony/sm6450`, `device/sony/pdx246` and
   `hybris/hybris-boot` checked out and the hybris patches applied:

   ```sh
   export PORT_ARCH=aarch64                # droidmedia's target list depends on it
   source build/envsetup.sh
   lunch lineage_pdx246-bp4a-userdebug     # never a bare "lunch lineage_pdx246"
   make hybris-hal droidmedia vendor_dlkmimage audio.hidl_compat.default
   ```

   Neither `vendor_dlkmimage` nor `audio.hidl_compat.default` is part of
   hybris-hal, and both must be built every time. The package build refuses a
   `vendor_dlkm.img` whose modules do not match the kernel, and it refuses an
   out/ without `system/lib64/hw/audio.hidl_compat.default.so`: droid-config-pdx246
   points the vendor's `audio.primary.parrot.so` name at that library, and
   without it audio would fail with no build error. Without `PORT_ARCH`,
   hybris-boot's `droidmedia` target silently builds nothing, so matched-set.sh
   also refuses an out/ without `system/lib64/libdroidmedia.so`. Commit kernel
   changes before building, or the kernel release ends in `-dirty`.

2. Packages, in the Platform SDK, from `$ANDROID_ROOT`, in this order:

   ```sh
   rpm/dhd/helpers/build_packages.sh -d
   rpm/dhd/helpers/build_packages.sh -c
   git clone --recurse-submodules https://github.com/mer-hybris/pulseaudio-modules-droid.git hybris/mw/pulseaudio-modules-droid
   git -C hybris/mw/pulseaudio-modules-droid checkout 65edd31f62f22e2eec1f765608ca9c6ae5c4af7b   # 14.2.106
   rpm/dhd/helpers/build_packages.sh -o --mw
   rpm/dhd/helpers/build_packages.sh --mw=https://github.com/sailfish-on-nabu/parse-android-dynparts
   rpm/dhd/helpers/build_packages.sh --mw=https://github.com/sailfishos/sensorfw --spec=rpm/sensorfw-qt5-binder.spec
   rpm/dhd/helpers/build_packages.sh -g
   rpm/dhd/helpers/build_packages.sh -o -N --mw=droid-hal-img-boot-pdx246
   rpm/dhd/helpers/build_packages.sh -v
   rpm/dhd/helpers/build_packages.sh -i
   ```

   - `-d` is this repository; `-c` is droid-config-pdx246
     (`hybris/droid-configs`); `-v` is droid-hal-version-pdx246; `-i` builds
     the image and the flashing zip.
   - `-o --mw` builds the default middleware set. pulseaudio-modules-droid stays at 14.2.106 (commit 65edd31f), the version
     recommended for Sailfish OS 5.1; newer releases need matching changes in other
     packages. It is cloned and checked out before the middleware run, and `--mw`
     runs with `-o`: without `-o`, buildmw runs `git pull` in every middleware
     repository that already exists, which fails on the detached checkout or moves
     it to a newer release. Missing repositories are still cloned.
   - `-g` packages droidmedia and gst-droid (droidmedia-localbuild from
     `external/droidmedia`); the adaptation pattern requires gstreamer1.0-droid.
     It needs droidmedia from the host build, which is only built with
     `PORT_ARCH=aarch64` set.
   - parse-android-dynparts maps the logical partitions of super; the sensorfw
     binder spec (0.15.2) talks to the AIDL sensors HAL.
   - droid-hal-img-boot-pdx246 (`hybris/mw/droid-hal-img-boot-pdx246`) is
     built with `-o -N --mw=...`, not with `-b`. Only the `--mw` route runs
     dhd's img-boot preparation (`dhd/helpers/util.sh:278-298`): it removes the
     installed img-boot from the SDK target and installs
     `droid-hal-pdx246-kernel` and `-kernel-modules` from the local repository.
     `-b` skips that. After a new `-d` build the target then keeps or gets the
     old img-boot package, which obsoletes `droid-hal-pdx246-kernel-modules`,
     and the img-boot spec's `rpm -ql droid-hal-pdx246-kernel-modules` finds no
     modules, so the build fails. `-o` stops buildmw's `git pull`
     (`util.sh:262-265`) on the local repository, `-N` skips its version-tag
     check (`util.sh:268-271`). Rebuild img-boot after every `-d`: it requires
     `-vendor_boot`, `-kernel-dtbo` and `-vendor_dlkm` at the exact
     version-release of the droid-hal build it packed.
   - Network access: the first runs install build dependencies (lz4 among
     them) into the SDK target and clone the middleware repositories.

   `build_packages.sh -d` stops if:
   - `hybris/mer-kernel-check` reports an ERROR for `obj/KERNEL_OBJ/.config` or
     `obj/DTB_OBJ/.config` (dhd runs it on `obj/*/.config`);
   - `hybris/hybris-boot/fixup-mountpoints` does not know pdx246 (the entry is on
     the hybris-boot `hybris-23.2` branch);
   - `helpers/matched-set.sh` finds a module in the staged module directories, in
     `vendor_boot.img` or in `vendor_dlkm.img` that was built for a different
     kernel release, a missing image, a missing
     `audio.hidl_compat.default.so`, or a mount unit whose source is still a
     by-name path.

   The build writes into the Android tree: `tmp/`,
   `generated_android_filesystem_config.h`, objects and the two sparse tools in
   `system/core/libsparse/`, objects in `system/libbase/`, and the RPMs in
   `droid-local-repo/pdx246/`. Unless a .gitignore covers them, `git status` in
   system/core and system/libbase lists them as untracked.

## Flashing (summary)

The flashing procedure itself belongs to droid-config-pdx246
(`sparse/boot/flash-config.sh`, run by `flash.sh` from the release zip, and
`flashing-README.txt`). The rules for the images from this package:

- `hybris-boot.img` (droid-hal-pdx246-img-boot, with the kernel),
  `vendor_boot.img` (`-vendor_boot`), `dtbo.img` (`-kernel-dtbo`) and
  `vendor_dlkm.img` with `vendor_dlkm.release` (`-vendor_dlkm`) are one matched
  set from one Sailfish OS build. The Sailfish kernel config changes the module
  ABI (about 10,000 symbol CRCs), so never combine them with the LineageOS
  images, in either direction.
- Slot a only. Every partition name has an explicit `_a`, and
  `fastboot --set-active=a` runs before and after the writes. Sailfish mounts
  `system_a`, `vendor_a`, `vendor_dlkm_a` and the other logical partitions.
- Before flashing: LineageOS must be installed on slot a and booted once to the
  home screen, then left running for a minute, so that the Virtual A/B merge
  completes. Keep the LineageOS set (boot, vendor_boot, dtbo, vendor_dlkm and
  recovery images) of the release in super, to roll back with.

`flash.sh` runs fastbootd first:

1. From the Sony bootloader: a dry run that stops if `fastboot getvar secure`
   says yes (`getvar_fail_if secure yes`, as droid-hal-configs' flash.sh does).
2. `fastboot --set-active=a`, then `fastboot reboot fastboot`.
3. `./flash-preflight.sh` (in the zip) stops with a message unless fastbootd
   reports `current-slot` a, `snapshot-update-status` none and
   `is-logical:vendor_dlkm_a` yes.
4. From fastbootd: `vendor_dlkm_a` (vendor_dlkm.img) and `userdata`
   (sailfish.img001). Logical partitions such as vendor_dlkm can only be
   flashed from fastbootd, and large images need it (or `fastboot -S 256M`),
   because Sony's bootloader does not report a usable max-download-size.
5. `fastboot reboot bootloader`, then from the bootloader: `boot_a`
   (hybris-boot.img), `vendor_boot_a` (vendor_boot.img), `dtbo_a` (dtbo.img).
6. `fastboot --set-active=a`, then reboot.

Why fastbootd first: on the first install, recovery_a (ramdisk-only; it hosts
fastbootd) still boots on LineageOS's boot_a kernel and vendor_boot_a, which are
known to work with it.

- Re-flashing over an installed Sailfish OS: fastbootd then runs on the Sailfish
  kernel and vendor_boot. If `fastboot reboot fastboot` does not reach
  fastbootd, flash the saved LineageOS `boot_a`, `vendor_boot_a` and `dtbo_a`
  from the bootloader first, then run `./flash.sh` again.
- If `flash.sh` stops halfway (for example the USB connection drops while a
  large image is sent, a known pdx246 failure), reconnect until
  `fastboot devices` lists the phone, run `fastboot reboot bootloader`, and
  start `./flash.sh` again from the beginning.
- Flashing userdata erases all LineageOS data on the phone.
- Slot b holds no bootable LineageOS: Virtual A/B keeps one copy of the dynamic
  partitions. Rolling back means reflashing the saved slot-a LineageOS set, all
  of it.
- Reflashing or updating LineageOS on slot a afterwards replaces vendor_dlkm_a
  (and the vendor layer under Sailfish) with modules that do not match the
  Sailfish kernel.

## Updates on the phone

Upgrading the kernel packages on the phone registers preinit oneshots from
droid-config-pdx246-flashing: `flash-vendor_boot.sh` and `flash-dtbo.sh` (dhd),
`flash-bootimg.sh` (img-boot) and `flash-vendor_dlkm.sh` (this spec's
`-vendor_dlkm`). Untested on the phone; until it is, do kernel updates with the
fastboot procedure above.

- The first three write `boot_a`, `vendor_boot_a` and `dtbo_a` together as one
  set, only when the kernel release inside `hybris-boot.img` equals
  `/boot/vendor_dlkm.release`, and check each written partition. When the set
  rewrites `vendor_boot_a`, droid-config records the current boot ID in
  `/var/lib/platform-updates/.pdx246-set-written`.
- `flash-vendor_dlkm.sh` writes `vendor_dlkm_a` in preinit, before
  `/vendor_dlkm` is mounted, only when `uname -r` equals
  `/boot/vendor_dlkm.release` and vendor_boot_a was not rewritten during the current
  boot. Until then it exits non-zero and stays registered, so vendor_dlkm_a
  follows at the first boot of the new set. It fails early if the device check
  (`CPUCHECK_STRING` in the DT model or `/proc/cpuinfo`) fails, and it verifies
  the written partition against the image.
- droid-hal-pdx246-img-boot requires `-vendor_boot`, `-kernel-dtbo` and
  `-vendor_dlkm` at the same version-release, so the set is installed together.
- Open before any update channel: img-boot's Release is 1 for every rebuild
  with the same kernel sublevel (NOTES.md, T12).
