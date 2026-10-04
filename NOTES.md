<!--
SPDX-FileCopyrightText: Johannes Meyer zum Alten Borgloh
SPDX-License-Identifier: Apache-2.0
-->

# droid-hal-pdx246: design notes

Draft of 2026-10-04 for `$ANDROID_ROOT/rpm`. It was first written while the
first `make hybris-hal` ran, so some checks used the LineageOS 23.2 release
output (`LOS out`, read only). That output comes from the same device, kernel
and vendor commits, but has no hybris patches and no Sailfish kernel config.
The checks that need the real output were then repeated on the finished
hybris-hal output (`hybris out`): T1-T5 are done, T6 needs the first package
build.

Placeholders: `$ANDROID_ROOT` = the `hybris-23.2` Android tree (this repository
is `$ANDROID_ROOT/rpm`); `<sfos>` = the Sailfish OS workspace with the
reference port checkouts; `<lineageos tree>` = the LineageOS 23.2 checkout of
the pdx246 port. `hybris out` = `$ANDROID_ROOT/out/target/product/pdx246`.
`LOS out` = `<lineageos tree>/out/target/product/pdx246`.

Paths: `dhd/` = mer-hybris/droid-hal-device at be67bbc, read from the reference
checkout `<sfos>/pdx235/droid-hal-pdx225/dhd`. `inc` = `dhd/droid-hal-device.inc`.
`initrd.inc` = `droid-hal-device-img-boot.inc` of mer-hybris/hybris-initrd at
7b972b6, the pin of droid-hal-img-boot-pdx246. `SAILFISH-NOTES.md`,
`findings.md` and the LineageOS port's `PORTING-NOTES.md` are the porter's
working notes; they are not part of this repository. `(inferred)` marks
conclusions that were not tested.

## Decisions

### D1. dhd pinned to be67bbc, not master

- On 2026-10-04 master is 775f6c0 (GitHub API: branch list and the last 15
  commits). That is be67bbc plus one commit, 44a1036. `git diff --stat be67bbc
  775f6c0` touches only `helpers/makefstab` (+3 lines): `$src =~
  s/.*by-name/\/dev\/disk\/by-partlabel/;`.
- The pdx246 fstab mounts four slotted partitions by bare name with
  `slotselect`: modem, dsp, vm-bootsys and bluetooth
  (`device/sony/pdx246/rootdir/etc/fstab.default:50-53`). makefstab has no slot
  handling (`dhd/helpers/makefstab:67-165`).
- I ran both makefstab versions on the pdx246 inputs in a scratch copy: first the
  hybris-patched `system/core/rootdir/init.rc`, `init.usb.rc`,
  `init.usb.configfs.rc`, `init.zygote64.rc`, and the `LOS out` vendor
  `etc/init/hw/*.rc`, `root/init.environ.rc`, `root/init.recovery.qcom.rc`,
  `vendor/etc/fstab.default` and `vendor/etc/fstab.emmc`; then (review) be67bbc
  again on the same file set taken from the `hybris out`, which has only
  `init.qti.kernel.rc` under `vendor/etc/init/hw` (D9). Each time with the skip
  list of D9, followed by `hybris/hybris-boot/fixup-mountpoints pdx246` on the
  copies. Results:

  | unit | be67bbc | 775f6c0 |
  |---|---|---|
  | vendor-firmware_mnt.mount | `/dev/sda67` (modem_a) | `/dev/disk/by-partlabel/modem`, which does not exist |
  | vendor-dsp.mount | `/dev/sda71` (dsp_a) | `/dev/disk/by-partlabel/dsp`, which does not exist |
  | vendor-bt_firmware.mount | `/dev/sda68` (bluetooth_a) | `/dev/disk/by-partlabel/bluetooth`, which does not exist |
  | metadata, mnt-vendor-persist, -qmcs | sda54, sda3, sda63 | by-partlabel, valid |

  With master the modem, ADSP/CDSP and Bluetooth firmware would not mount (GPT
  labels are `modem_a`, `dsp_a`, `bluetooth_a`, per the partition map in
  SAILFISH-NOTES.md, and the fixup entry). be67bbc uses the hybris-boot entry
  (`hybris/hybris-boot/fixup-mountpoints:17-165`, branch hybris-23.2, ea2e10b),
  which maps the bare names to slot a.
- The Android 15/16 handling is identical in both commits. Android 15/16 support
  came with 46779019 (2025-12-21) and init_boot support with 61090956. The
  vendor-bootconfig packaging came with 9fecf2b6. The version is detected from
  `build/release/flag_values/*/RELEASE_PLATFORM_VERSION_LAST_STABLE.textproto`
  (inc:476-477). In this tree those files say 15, 16 and 16, so `sort -n -r`
  gives 16.
- Branch jb64684 (unmerged) changes linkerconfig/apexd.rc copying and
  `--without dhd_tools`. The `hybris out` does not need it (T3). SUBMODULES.md
  has the reasons.

### D2. Repository layout and names

- `build_packages.sh -d` builds `rpm/droid-hal-$HABUILD_DEVICE.spec`, else
  `rpm/droid-hal-$DEVICE.spec`. With `HABUILD_DEVICE` unset, util.sh sets it to
  `$DEVICE` (`dhd/helpers/util.sh:64-66,146-158`). So the spec sits at the repo
  root as `droid-hal-pdx246.spec`, and `%include rpm/dhd/droid-hal-device.inc` is
  resolved from `$ANDROID_ROOT` (the cwd of mb2).
- `device`, `vendor` = pdx246, sony. `rpm_device` and `rpm_vendor` default to them
  (inc:105-110), so every package is `droid-hal-pdx246-*`, as decided for this
  port (DEVICE=pdx246 everywhere). `vendor_pretty`/`device_pretty` are not used by dhd.
  droid-hal-version uses them (`droid-hal-version.inc:134,140`). They are kept as
  the dhd template has them (`dhd/droid-hal-@DEVICE@.spec.template`).
- `droid_target_aarch64 1`: inc:433-441 fails the build when it is missing and a
  BoardConfig sets `TARGET_ARCH := arm64` (`device/sony/pdx246/BoardConfig.mk:38`).

### D3. have_custom_img_boot and have_custom_img_recovery: defined

- The boot image is the LVM one from droid-hal-img-boot-pdx246 (hybris-initrd).
  initrd.inc builds `Name: droid-hal-%{device}-img-boot` (initrd.inc:177) and
  `droid-hal-%{device}-img-recovery` (initrd.inc:258-267). Without the two defines
  dhd builds packages with the same names from the Android-built hybris-boot.img
  and hybris-recovery.img (inc:287-311, 1088-1094, 1286-1301). The reference
  droid-hal-pdx235.spec lacks them, so its two repos build colliding packages.
- Android's `hybris-boot.img`/`hybris-recovery.img` are still built by hybris-hal.
  They stay usable from `out/` for a test boot (telnet debug shell), but they
  are not packaged.

### D4. enable_kernel_update: not defined

Both uses are inside `%if 0%{!?have_custom_img_boot:1}` (inc:292-297, 1127-1136).
With D3 it would do nothing. The img-boot package registers
`flash-bootimg.sh` itself on upgrade (initrd.inc:520-525).

### D5. vendor_boot and dtbo: enable_vendor_boot_update 1, enable_dtbo_update 1

- Both macros exist at be67bbc (inc:33-41 docs; packages 337-347 and 364-384;
  install 1039-1049; %post 1149-1156 and 1169-1178; files 1315-1335). There is no
  `vendor_dlkm` macro anywhere in dhd (grep). See D6.
- `enable_vendor_boot_update` gives `droid-hal-pdx246-vendor_boot` with
  `out/.../vendor_boot.img` (the Android-built image: cmdline, dtb, bootconfig, the
  302-module vendor ramdisk). hybris-hal builds it because the device builds a
  vendor_boot image (`hybris/hybris-boot/Android.mk:371-373`). This is the
  decided route (Sailfish-built vendor_boot to vendor_boot_a). Upgrades register
  `flash-vendor_boot.sh`.
- `have_custom_vendor_boot` is not defined. It would switch dhd to a
  `kernel-modules-vendor_boot` package (inc:378-383, 1069-1081). hybris-initrd
  would then build its own vendor_boot.img with `vendor_boot_mkbootimg_cmd`
  (initrd.inc:161-169, 191-193, 426-454, 469-471). That is a different design,
  and the `droid-hal-pdx246-vendor_boot` package name would then come from
  img-boot (initrd.inc:281-291, 510-518), so img-boot must not define
  `vendor_boot_mkbootimg_cmd`.
- `kernel-dtbo` is always built. It contains `/boot/dtbo.img` if `out/.../dtbo.img`
  exists (inc:1039-1043). `enable_dtbo_update` adds the upgrade oneshot
  `flash-dtbo.sh` and `Requires(post): droid-config-flashing`. dtbo.img comes from
  the same build; the `hybris out` has a 24 MiB dtbo.img (25,165,824 bytes).
- `enable_init_boot_update`/`have_custom_init_boot`: pdx246 has no init_boot
  partition (GPT, `BoardConfig.mk` has no INIT_BOOT). The `init_boot` subpackage
  dhd declares has no files section without the macro, so rpm does not build it.

### D6. vendor_dlkm.img: a sub-package of this spec

- dhd only copies the .ko files of `vendor_dlkm/lib/modules` into
  `droid-hal-pdx246-kernel-modules` (`/lib/modules/<release>`, inc:1059-1067). It
  has no image handling.
- Decided for this port: the Sailfish-built vendor_dlkm.img is flashed to
  vendor_dlkm_a (logical partition in super, fastbootd). droid-config mounts it.
  Android's `vendor.modprobe` (init.qti.kernel.rc, early-init) loads its
  `modules.load` (265 of 351 modules).
- So this spec adds `droid-hal-pdx246-vendor_dlkm` after the `%include`:
  `/boot/vendor_dlkm.img` and `/boot/vendor_dlkm.release`, installed by
  `helpers/matched-set.sh install` from `custom_install_cmds` (inc:1105, after
  `kernel_release` is set at inc:1018). It requires
  `droid-hal-pdx246-vendor_boot = %{version}-%{release}` (same build) and registers
  `flash-vendor_dlkm.sh` on upgrade (D7). The sub-package follows dhd's
  vendor_boot sub-package (inc:364-370, 1169-1177, 1327-1332). rpmspec of the
  SDK (rpm 4.16.1.3, tooling 5.1.0.11) parses the spec with the `%package` after
  dhd's `%files` sections and lists 11 packages, `-vendor_dlkm` among them
  (`-init_boot` is declared but has no `%files`, so 10 are built). The spec
  sets no Version or Release: dhd gives local (mb2) builds Version 0.0.6 and a
  timestamped Release (inc:181-199), so every `-d` build has a new
  version-release, which img-boot's exact pin (D7) follows.
- The image goes into the rootfs `/boot` (about 70 MB raw; the `hybris out`
  vendor_dlkm.img is 69,554,176 bytes), so the kickstart can attach it, the same
  way dtbo.img and vendor_boot.img reach the flashing zip.
- Not taken: Nagara's droid-hal-vendor-dlkm, which writes the modules to a
  `/vendor_dlkm` directory in the rootfs and does not flash the partition
  (https://github.com/sailfishos-sony-nagara/droid-hal-vendor-dlkm, README and
  `rpm/droid-hal-vendor-dlkm.inc` @1b7569a; MIT). It was the alternative not
  chosen for this port (option N in droid-hal-img-boot-pdx246's notes; option M
  would be fastboot-only kernel updates).

### D7. Kernel updates on the phone (option P)

Decided design; droid-config-pdx246 implements the scripts, its NOTES have the
details. Untested on the phone (droid-config R11); until then, kernel updates go
by fastboot (README, Flashing).

- Registration: on upgrade (not at image creation, `$1 -ne 1`) `-kernel-dtbo`
  and `-vendor_boot` (dhd, D5), `-img-boot` (initrd.inc:520-525) and
  `-vendor_dlkm` (this spec) register preinit oneshots from
  droid-config-pdx246-flashing: `flash-dtbo.sh`, `flash-vendor_boot.sh`,
  `flash-bootimg.sh`, `flash-vendor_dlkm.sh`. A oneshot that exits non-zero
  stays registered (sailfishos/oneshot `scripts/oneshot`: `$SCRIPTLET && rm`;
  droid-config NOTES), which closes the former T8.
- The boot set: the first three call `ks_flash_boot_set`, which writes `boot_a`,
  `vendor_boot_a` and `dtbo_a` together, only when the kernel release inside
  `/boot/hybris-boot.img` equals `/boot/vendor_dlkm.release`, and checks each
  write with `ks_part_matches`. When it rewrites `vendor_boot_a` it writes
  `/proc/sys/kernel/random/boot_id` to
  `/var/lib/platform-updates/.pdx246-set-written`.
- vendor_dlkm: `flash-vendor_dlkm.sh` fails early unless `CPUCHECK_STRING` is
  found in the DT model or `/proc/cpuinfo`. It exits 1 (stays registered) while
  `uname -r` differs from `/boot/vendor_dlkm.release`, or while
  `.pdx246-set-written` holds the current boot ID. Otherwise it maps
  vendor_dlkm_a from the super metadata (slot a), refuses an image larger than
  the partition (only fastbootd can resize it), writes it with flash-partition
  before `/vendor_dlkm` is mounted, and verifies the partition (`simg2img` if
  the image is sparse, then `cmp` over the image size).
- Effect, new kernel release: boot N (old kernel) writes the set in preinit;
  vendor_dlkm waits for the release. Boot N+1 runs the new kernel and
  vendor_boot and writes vendor_dlkm_a before it is mounted. Effect, a rebuild
  that changes only the modules (same release, matched-set.sh cannot tell it
  apart): the boot ID guard defers vendor_dlkm_a to boot N+1 as well. Without
  it, boot N would mount the new second-stage modules on top of the previous
  first-stage ones, which the initrd loaded before preinit (hybris-initrd
  7b972b6 main-init:21-22).
- Packages: `-vendor_dlkm` requires `-vendor_boot = %{version}-%{release}`.
  droid-hal-pdx246-img-boot requires `-vendor_boot`, `-kernel-dtbo` and
  `-vendor_dlkm` at the version-release of the droid-hal build it packed
  (exact pin in its spec), so img-boot is rebuilt after every `-d` (D16).
- Not done: a second line in `vendor_dlkm.release` (for example the sha256 of
  vendor_boot.img) to name the build rather than the kernel commit, as the
  review suggested optionally. droid-config compares the whole file with
  `uname -r`, so it would need changes there; the boot ID guard covers the
  modules-only case.
- Open: img-boot's Release (T12), the order of oneshots within one preinit
  pass (T8).

### D8. installable_zip: not defined

dhd tests whether it is defined: `%if 0%{?installable_zip:1}` (inc:663-667,
1290-1294). Defined with any value, `%install` copies
`out/.../hybris-updater-script`. hybris-boot builds that only when `HYBRIS_BOOT_PART`
is set (`hybris/hybris-boot/Android.mk:365-369`). It is read from a `/boot` line
in the device's fstab files (Android.mk:47, 68). `device/sony/pdx246` has one
fstab, `rootdir/etc/fstab.default`, and it has no `/boot`. Nagara's
`installable_zip 0` would therefore fail here (working notes, findings.md).

### D9. makefstab_skip_entries and the generated mount units

dhd turns `mount` lines of `system/etc/init/hw/*.rc`, `vendor/etc/init/hw/*.rc`
and `root/*.rc`, plus the `vendor/etc/fstab*` entries, into units (inc:577-581).
It reads them from the `hybris out`, not from the phone. hybris-hal does not
build the vendor rc modules of the device tree (init.qcom.rc, init.target.rc,
init.qcom.usb.rc, init.qti.ufs.rc, init.qcom.factory.rc), so the `hybris out`
has only `vendor/etc/init/hw/init.qti.kernel.rc` (its one mount is
`/sys/kernel/tracing`, which dhd skips itself, inc:581). The `LOS out` has all
six files.

With be67bbc, this skip list and the pdx246 fixup entry, the `hybris out` gives
**10 units**, all resolved (simulated with makefstab and fixup-mountpoints in a
scratch copy):

| unit | source in the `hybris out` | What= |
|---|---|---|
| `config.mount` | `system/etc/init/hw/init.rc:268` configfs | `none` |
| `dev-binderfs.mount` | `init.rc:274` binderfs | `binder` |
| `linkerconfig.mount` | `init.rc:70` bind | `/linkerconfig/bootstrap` |
| `mnt-vm.mount` | `init.rc:513` tmpfs | `tmpfs` |
| `metadata.mount` | `vendor/etc/fstab.default:44` | `/dev/sda54` |
| `mnt-vendor-persist.mount` | `fstab.default:45` | `/dev/sda3` |
| `mnt-vendor-qmcs.mount` | `fstab.default:54` | `/dev/sda63` |
| `vendor-firmware_mnt.mount` | `fstab.default:50` (modem, slotselect) | `/dev/sda67` (modem_a) |
| `vendor-dsp.mount` | `fstab.default:51` (dsp, slotselect) | `/dev/sda71` (dsp_a) |
| `vendor-bt_firmware.mount` | `fstab.default:53` (bluetooth, slotselect) | `/dev/sda68` (bluetooth_a) |

dhd comments the mount lines out of the root `*.rc` and the packaged system
`init.rc` (inc:682, 697). The vendor rc files are not packaged: droid-hal-init
reads them at runtime from the LineageOS vendor partition (`vendor_a`) and runs
their mount commands itself. That includes `/mnt/vendor/spunvm`
(`device/sony/pdx246/rootdir/etc/init.target.rc:64-66`, only under
`property:ro.boot.product.vendor.sku=taro`), the `/dev/blkio` cgroup and the
functionfs mounts. No unit is generated for them; T10 checks them at runtime.
If a `/mnt/vendor/spunvm` unit is ever wanted, droid-config would ship it
(`What=/dev/sda48`).

The skip list and its effect:

| mount point | source | effect on the `hybris out` | reason |
|---|---|---|---|
| `/system` `/system_ext` `/product` `/vendor` `/vendor_dlkm` `/odm` | fstab.default:38-43, logical | skipped | No first-stage init; droid-config maps super and mounts `dynpart-*_a`. The source would be the bare word `system` etc. |
| `/firmware` | `root/init.recovery.qcom.rc:46` `mount vfat /dev/block/bootdevice/by-name/modem${ro.boot.slot_suffix} /firmware` | skipped | Recovery only. After fixup the source would be `/dev/sda67${ro.boot.slot_suffix}`, a device that never appears. With `Before=local-fs.target` that is a failed unit after the device timeout (inferred: 90 s default). `/firmware` is a symlink made by the vendor's init.qcom.rc |
| `/vendor/vm-system` | fstab.default:52 (vm-bootsys, slotselect) | skipped | LineageOS init skips it with "skipping mount due to invalid magic" (LineageOS PORTING-NOTES.md:6675, read from a ramoops capture); no Sailfish user |
| `/` `/system_root` | rc `mount rootfs rootfs / remount` (LineageOS init.rc; not in the patched one) | inert (LOS out only) | Same as the reference; kept in case a later init.rc has it |
| `/dev/blkio` | `LOS out` `vendor/etc/init/hw/init.qcom.rc:421` cgroup v1 | inert (LOS out only) | dhd already skips `/dev/cpuctl /dev/cpuset /dev/stune` (inc:581); hybris patch system/core 0005 "Systemd handles control groups". Kept in case the vendor rc files reach the hybris out |
| `/dev/usb-ffs/aoa` `/dev/usb-ffs/ctrl` `/dev/ffs-diag` `/dev/ffs-diag-1` `/dev/ffs-diag-2` | `LOS out` `init.qcom.usb.rc:176-186` functionfs | inert (LOS out only) | dhd skips adb/mtp/ptp of the same kind (dhd 335172b). The function instances do not exist at local-fs time. makefstab escapes only the first `-` (`helpers/makefstab:136`, no `/g`), so `dev-ffs\x2ddiag-1.mount` would not match its Where= and systemd would refuse it |

`/metadata`: the last of `fstab.default`/`fstab.emmc` wins, because both define
it and makefstab's duplicate check looks in cwd, not in the output dir
(`helpers/makefstab:153`). fstab.emmc is a stock vendor blob
(`proprietary-files.txt:2729`); same mount points as fstab.default, options
differ (`sync`). `/config` is needed by usb-moded; `/dev/binderfs` must be
mounted (dhd comments the mount lines out of the packaged init.rc);
`/linkerconfig` and `/mnt/vm` are upstream behaviour. The three firmware units
are ordered after droid-config's `vendor.mount` by their parent path.

`helpers/matched-set.sh check` stops the build if a unit source is still a
by-name path or contains an init property, for example after a device tree change
adds a new mount.

### D10. straggler_files: /adb_keys /bugreports /cache /d /sdcard

- dhd copies `out/.../root` with `rsync --exclude bin --exclude etc` (inc:669). The
  `etc` pattern matches at every depth, so `vendor_dlkm/etc` and `odm_dlkm/etc` are
  not copied. Neither are bin, etc and init, which dhd handles itself. The
  `odm/*` links are removed (inc:935-947). What is left are the five top-level
  symlinks, created by the `init.environ.rc` module that hybris-hal builds
  (`system/core/rootdir/create_root_structure.mk:32-43,134`).
- Every entry must exist, or `%files detritus` fails. The `hybris out` `root/`
  has all five (T2).

### D11. android_config: WANT_ADRENO_QUIRKS

- dhd documents it for the Sailfish Browser shader crash on 64-bit Adreno devices
  (inc:94-99). libhybris reads android-config.h (`hybris/common/hooks.c:83`). With
  the define it maps `malloc` calls of `libllvm-glnext.so` to a hook that turns
  4-byte allocations into 5-byte ones (hooks.c:353-365, 3532-3536;
  hybris/mw/libhybris 2b39e63). pdx246's vendor ships that library
  (`LOS out vendor/lib64/libllvm-glnext.so`).
- Precedent: Nagara (GKI 5.10, Adreno) sets it
  (https://github.com/sailfishos-sony-nagara/droid-hal-sony-nagara/blob/main/droid-hal-common.inc),
  and so does Jolla's lena (working notes, findings.md). The 10 IV/10 V
  reference does not.
  Whether pdx246 needs it is untested (T7). It must be decided before libhybris is
  built (`--mw`), because it is compiled in.
- QCOM_BSP: dhd adds `QCOM_BSP`/`QTI_BSP` only if a BoardConfig has
  `BOARD_USES_QCOM_HARDWARE := true` (inc:833-843). pdx246 deliberately does not
  set it (`BoardConfig.mk:223-232`). Nothing in libhybris (2b39e63), droidmedia or
  the Android headers dhd extracts tests QCOM_BSP (rg). So it is left out; T7
  rechecks it for the other middleware.

### D12. Android 16 sparse tools: helpers/img2simg.mk and simg2img.mk

- dhd builds img2simg/simg2img with its own makefiles and `-std=gnu++14`
  (`dhd/helpers/img2simg.mk:5`, `simg2img.mk:5`; called from inc:545-555 via
  `dhd/helpers/makefile:23-25`). On this tree `libsparse/output_file.cpp` calls
  `android::base::MappedFile::Create`, which returns `std::optional`
  (system/libbase a5fcaab 2025-08-13, system/core effce46f3 2025-08-15, tag
  android-16.0.0_r4). Compiling the A16 sources with dhd's makefile fails ("'optional'
  in namespace 'std' does not name a template type"; tested with g++ 15 on a
  scratch copy). The droid-hal build would stop in %build. dhd master and jb64684
  are no different.
- dhd uses `rpm/helpers/img2simg.mk` and `rpm/helpers/simg2img.mk` when they
  exist (inc:513-519). The two files here are rewritten after dhd's own
  (same interface and make skeleton) with `-std=gnu++17`; dhd passes the same
  source lists (inc:524-530). Tested in scratch with dhd's own `helpers/makefile` invocation and
  dhd's source lists: both tools link and run, and usergroupgen builds too. The
  cross compiler of the SDK tooling SailfishOS-5.1.0.11 is gcc 13.4
  (aarch64-meego-linux-gnu). The droid-hal-pdx246-tools package (mkbootimg for
  img-boot) depends on them.
- Also checked on the A16 tree: dhd's `extract-headers.sh` exits 0 and writes
  `ANDROID_VERSION_MAJOR 16`. Its "not found" messages are fallbacks.
  `fs_config_generator.py aidarray` works, and mkbootimg.py imports only
  `gki.generate_gki_certificate`, which dhd installs.

### D13. helpers/matched-set.sh (custom_build_cmds, custom_install_cmds)

- `check` runs at the end of %build (inc:601), after makefstab and fixup. It
  stops the build when:
  - obj/KERNEL_OBJ and obj/DTB_OBJ disagree on `kernel.release`. dhd's
    `sort -u .../kernel.release` (inc:1018) would give two lines, and
    `cp kernel .../kernel-$kernel_release` would fail with a confusing message.
  - kernel, vendor_boot.img, dtbo.img or vendor_dlkm.img is missing.
  - a staged module (`vendor_ramdisk/lib/modules`, `vendor_dlkm/lib/modules`)
    has a vermagic other than the kernel release.
  - a module inside `vendor_boot.img` (header v4 parsed with od, ramdisk through
    `lz4 -dc`) or inside the raw `vendor_dlkm.img` has another release.
  - a mount unit is unresolved;
  - `system/lib64/hw/audio.hidl_compat.default.so` is missing. hybris-hal does
    not build it (hybris-boot Android.mk, HYBRIS_COMMON_TARGETS), but
    droid-config-pdx246 points the vendor's `audio.primary.parrot.so` name at it
    under `/usr/libexec/droid-hybris/system/lib64/hw/`; without it that link
    dangles and audio fails with no build error. dhd packages it with the rest
    of `system/` into the main package.

  It warns on `-dirty` and on module counts other than 302/351.
- Tests: on the `hybris out` it passes: 302/351 staged, 302 in vendor_boot.img,
  351 in vendor_dlkm.img, kernel `5.10.269-gki-ga6ce50fc4d00`, about 5 s. On the
  `LOS out` (also a consistent set) it passes too. In scratch copies it fails as
  intended for (a) a new kernel release with the LineageOS vendor_boot.img, (b) a
  matching vendor_boot with the LineageOS vendor_dlkm.img, (c) a `/firmware`
  unit with `${ro.boot.slot_suffix}` and (d) a missing
  `audio.hidl_compat.default.so`. It runs under bash (the SDK target's /bin/sh),
  dash and busybox sh. The first draft compared file times, but `LOS out` has
  vendor_boot.img (18:49) older than kernel (18:56) for a valid set, so times are
  not used.
- The kernel release names the kernel commit, not the build: a rebuild that
  changes only the modules keeps it. The on-device side handles that case (D7).
- `install` writes `/boot/vendor_dlkm.img` and `/boot/vendor_dlkm.release`.
- `custom_build_requires BuildRequires: lz4` (inc:210). The SDK target has no lz4
  yet. img-boot needs lz4 anyway (initrd.inc:206-208).

### D14. Kernel-config check

Nothing to set. dhd runs `mer_verify_kernel_config` on `obj/*/.config`
(inc:470-473). That covers `obj/KERNEL_OBJ/.config` and `obj/DTB_OBJ/.config`.
On the `hybris out`, run as dhd runs it, it exits 0 with 0 ERRORs (T1).

### D15. Not defined, on purpose

`installable_zip` (D8), `enable_kernel_update` (D4), `have_custom_vendor_boot`
(D5), `have_custom_init_boot` and `enable_init_boot_update` (no init_boot),
`bootloader_binary`/`enable_bootloader_update` (bootloader stays Sony's),
`lunch_device`, `device_variant`, `hadk_make_target`, `pre_actions` (OBS only,
inc:443-464; the Android side is built on the host with
`lunch lineage_pdx246-bp4a-userdebug`), `rpm_device`/`rpm_vendor` (defaults),
`dtbo_binary` (default `dtbo.img`), `provides_own_headers`, `header_patches`,
`droid_src_build`, `have_vendor_src_for_obs`, `additional_ha_groups(_remove)`.

### D16. Build sequence

Host, in `$ANDROID_ROOT` (`lunch lineage_pdx246-bp4a-userdebug`):
`PORT_ARCH=aarch64 make hybris-hal droidmedia vendor_dlkmimage audio.hidl_compat.default`
(without PORT_ARCH the droidmedia target builds nothing).
`vendor_dlkmimage` and `audio.hidl_compat.default` are not hybris-hal targets;
matched-set.sh refuses an out/ without them (D13). In the Platform SDK, from
`$ANDROID_ROOT`: `build_packages.sh -d`, `-c`, `-o --mw` (after checking out
pulseaudio-modules-droid 14.2.106), `--mw` parse-android-dynparts, `--mw`
sensorfw with `--spec=rpm/sensorfw-qt5-binder.spec`, `-g` (droidmedia and
gst-droid), then img-boot with
`rpm/dhd/helpers/build_packages.sh -o -N --mw=droid-hal-img-boot-pdx246`, then
`-v` and `-i`. README.md has the exact commands.

img-boot is not built with `-b`: only buildmw runs dhd's img-boot preparation
(`dhd/helpers/util.sh:278-298`), which removes the installed img-boot from the
SDK target and installs `droid-hal-pdx246-kernel` and `-kernel-modules` from
`droid-local-repo`. mb2's `--output-dir` implies `--search-output-dir`, so every
build first updates the target from `droid-local-repo`. img-boot obsoletes
`droid-hal-pdx246-kernel-modules < <kernel version>` (initrd.inc:239-240), and
dhd's packages are versioned 0.0.6 (inc:181), so after a new `-d` build the
target can end up with the old img-boot in place of the new kernel-modules,
and the img-boot spec's `rpm -ql droid-hal-pdx246-kernel-modules`
(initrd.inc:157) then finds no modules. `-o` skips buildmw's `git pull`
(util.sh:262-265) on the repository already in `hybris/mw`, and `-N` skips the
version-tag check (util.sh:268-271). img-boot is rebuilt after every `-d`,
because it pins `-vendor_boot`, `-kernel-dtbo` and `-vendor_dlkm` to the exact
version-release of the droid-hal build (D7).

### D17. Flash procedure (droid-config-pdx246 owns it)

Fastbootd first. From the Sony bootloader: the dry run with
`getvar_fail_if secure yes` (as droid-hal-configs' flash.sh does), then
`fastboot --set-active=a` and `fastboot reboot fastboot`. Then
`./flash-preflight.sh` (shipped in the zip through droid-config's
out-of-image-files) stops unless fastbootd reports `current-slot` a,
`snapshot-update-status` none and `is-logical:vendor_dlkm_a` yes. From
fastbootd: `vendor_dlkm_a` and `userdata` (sailfish.img001). Then
`fastboot reboot bootloader`, and from the bootloader `boot_a`
(hybris-boot.img), `vendor_boot_a`, `dtbo_a`; finally `fastboot --set-active=a`
and reboot.

- Why: on the first install, recovery_a (ramdisk-only; it hosts fastbootd)
  still boots on LineageOS's boot_a kernel and vendor_boot_a, which are known to
  work. fastbootd works on the current slot's super metadata and refuses
  userdata while a snapshot merge is pending, hence the pre-flight checks.
- Before flashing, LineageOS must be installed on slot a and booted once to the
  home screen, then left a minute, so that the Virtual A/B merge completes.
- Re-flashing over an installed Sailfish OS: fastbootd then runs on the Sailfish
  kernel. If `fastboot reboot fastboot` does not reach fastbootd, flash the
  saved LineageOS boot_a, vendor_boot_a and dtbo_a from the bootloader first,
  then run `./flash.sh` again.
- If `flash.sh` stops halfway (a USB drop while sending a large image, a known
  pdx246 failure, "TRAP 2" in the LineageOS port notes): reconnect until
  `fastboot devices` lists the phone, run `fastboot reboot bootloader`, and
  start `./flash.sh` again. A rerun from fastbootd would stop at the dry run,
  because fastbootd answers `secure: yes` (LineageOS recovery has ro.secure=1);
  droid-config's message for that case says so.
- Slot b holds no bootable LineageOS (Virtual A/B keeps one copy of the dynamic
  partitions). Rollback means reflashing the saved slot-a LineageOS set.

## Checks on the build output

- **T1** done. `obj/KERNEL_OBJ` and `obj/DTB_OBJ` `kernel.release` are both
  `5.10.269-gki-ga6ce50fc4d00` (no `-dirty`). `mer_verify_kernel_config
  obj/*/.config`, as dhd runs it (inc:472-473), exits 0 with 0 ERRORs.
- **T2** done. `hybris out` `root/` has adb_keys, bugreports, cache, d and sdcard
  (straggler_files), the bin, etc and init symlinks that dhd excludes or
  replaces, `init.environ.rc`, `init.recovery.qcom.rc` and empty mount-point
  directories. The first `-d` build (T6) shows whether rpmbuild reports anything
  as unpackaged.
- **T3** done. `apex/com.android.runtime/bin/linkerconfig` and
  `system/etc/init/apexd.rc` exist, `system/bin/linkerconfig` does not, and
  `system/lib64/bootstrap/lib{c,dl,dl_android,m}.so` exist (inc:781-786). jb64684
  is not needed (D1).
- **T4** done for the images: `sh rpm/helpers/matched-set.sh check pdx246` passes
  on the `hybris out` (D13). After the first `build_packages.sh -d`, look at
  `tmp/units/*.mount`: the 10 units of D9, sources sdaN or the pseudo file
  systems.
- **T5** done. `kernel`, `dtbo.img` (25,165,824 bytes), `vendor_boot.img`
  (100,663,296) and `vendor_dlkm.img` (69,554,176) exist, and
  `system/lib64/hw/audio.hidl_compat.default.so`, built separately with
  `make audio.hidl_compat.default`.
- **T6** After `build_packages.sh -d`: `rpm -qlp` of `-vendor_boot`,
  `-kernel-dtbo` and `-vendor_dlkm` show one image each (plus
  `vendor_dlkm.release`); the main package contains
  `/usr/libexec/droid-hybris/system/lib64/hw/audio.hidl_compat.default.so`.
  `-img-boot` and `-img-recovery` are not built here.

## Runtime, device and later TODOs

- **T7** WANT_ADRENO_QUIRKS: test the Sailfish Browser (WebGL/shaders) with it. If
  in doubt, also test without it. When cloning pulseaudio-modules-droid,
  gst-droid and qt5-qpa-hwcomposer-plugin for `--mw`, grep them for
  `QCOM_BSP`/`QTI_BSP` (D11).
- **T8** (droid-config) Oneshot order within one preinit pass: the boot ID guard
  of D7 only works if `ks_flash_boot_set` has run before `flash-vendor_dlkm.sh`
  in the same pass. If oneshot can run `flash-vendor_dlkm.sh` first, a
  modules-only rebuild would still write vendor_dlkm_a in the boot that also
  rewrites vendor_boot_a. Check sailfishos/oneshot's run order, or have
  `flash-vendor_dlkm.sh` also wait while one of the set's oneshots is still
  registered.
- **T9** On the phone: confirm vm-bootsys_a holds no ext4 (`blkid` or `file -s` on
  `/dev/block/by-name/vm-bootsys_a`, adb root). Then decide whether to keep it
  skipped (D9). The evidence is a LineageOS ramoops capture, not a fresh read.
- **T10** On the phone under Sailfish: `systemctl --failed` and
  `systemctl list-units '*.mount'`. Check that the firmware mounts come up from
  sda67/sda71/sda68 and that `/config` and `/dev/binderfs` work. Check what
  droid-hal-init's runtime mounts from the vendor rc files do (`/dev/blkio`
  cgroup next to systemd's cgroups, the functionfs mounts next to usb-moded,
  `/mnt/vendor/spunvm` if its sku condition holds) in its log.
- **T11** The fixup map, the dynpart units and the flashing all assume slot a.
  Before the first flash the phone must run LineageOS from slot a, with the
  merge completed (D17); flash-preflight.sh checks it.
- **T12** (img-boot, not implemented) img-boot's Release is 1 for every rebuild
  with the same kernel sublevel (initrd.inc:177-184: Version is the kernel
  sublevel, Release 1). After a kernel rebuild the installed img-boot keeps
  requiring the old exact `-vendor_boot`, `-kernel-dtbo` and `-vendor_dlkm`
  version-release. Its Release must change per build (tags, or derived from the
  droid-hal release) before any update channel exists.

## Cross-repo contract

1. Packages. This repository (`rpm/`): `droid-hal-pdx246`, `-devel`, `-users`,
   `-tools`, `-kernel`, `-kernel-modules`, `-detritus`, `-kernel-dtbo`,
   `-vendor_boot`, `-vendor_dlkm`; it builds no img-boot or img-recovery (D3).
   `hybris/mw/droid-hal-img-boot-pdx246` (hybris-initrd): `droid-hal-pdx246-img-boot`
   and `-img-recovery`; it must not define `vendor_boot_mkbootimg_cmd` (D5).
   `hybris/droid-configs`: `droid-config-pdx246` and its sub-packages.
   `hybris/droid-hal-version-pdx246`: `droid-hal-version-pdx246`. Submodule pins:
   dhd be67bbc, droid-hal-configs 1dae7f2, droid-hal-version 09c2745,
   hybris-initrd 7b972b6.
2. Images, one matched set from one Sailfish OS build: `hybris-boot.img`
   (img-boot), `vendor_boot.img` (`-vendor_boot`), `dtbo.img` (`-kernel-dtbo`),
   `vendor_dlkm.img` and `vendor_dlkm.release` (`-vendor_dlkm`), all under
   `/boot`. The kickstart attachment lists the images (plus `hybris-recovery.img`
   as a debug image, never written to recovery_a); `vendor_dlkm.release` stays in
   the rootfs `/boot` only.
3. Flash procedure: fastbootd first, with `flash-preflight.sh` (D17; README).
4. On-device kernel updates: option P (D7). img-boot requires `-vendor_boot`,
   `-kernel-dtbo` and `-vendor_dlkm` at this build's version-release.
   droid-config-pdx246-flashing ships `flash-bootimg.sh`, `flash-vendor_boot.sh`,
   `flash-dtbo.sh`, `flash-vendor_dlkm.sh` and `pdx246-kernel-set.sh`, and no
   `flash-recoveryimg.sh` that writes recovery_a (it stays the LineageOS
   ramdisk-only recovery; img-recovery's `%post` registers that name on upgrade,
   initrd.inc:492-495).
5. USB in the running OS (droid-config): `usb-moded-configfs-setup.sh` waits up
   to 30 s after droid-hal-init for `/sys/class/udc/a600000.dwc3`; if it is
   absent, it writes `peripheral` to
   `/sys/bus/platform/devices/a600000.ssusb/mode` and logs it. A bring-up aid,
   to drop once the Type-C role switch is shown to work.
6. Slot marking (droid-config): `pdx246-mark-slot.service` runs
   `/usr/bin/droid/droid-bootctl.sh` after `droid-hal-init.service`, so slot a
   is marked successful once the boot HAL runs, not only after the UI.
7. Build commands: D16 and README.
8. Mount units: this repository generates the 10 units of D9 and skips
   `/ /system_root /system /system_ext /product /vendor /vendor_dlkm /odm`;
   droid-config maps super (parse-android-dynparts, `dynpart-*_a`) and owns
   `system_root`, `system`, `system_ext`, `product`, `vendor`, `vendor_dlkm`
   and `odm` mounts, named `vendor.mount` etc., so the dhd units below them are
   ordered after them.
9. The adaptation pattern requires `droid-hal-pdx246`, `-tools`, `-kernel-dtbo`,
   `-vendor_boot`, `-vendor_dlkm`, `-img-boot` and `-img-recovery`, and not
   `-kernel-modules` (img-boot provides `/lib/modules`; `build_packages.sh -i`
   then uses `mic create loop` for the LVM pack, `build_packages.sh:410-427`).
10. hybris/hybris-boot branch hybris-23.2 must stay checked out when droid-hal
    is built (pdx246 entry in fixup-mountpoints, ea2e10b). A `repo sync` must
    not replace it.

## Provenance

| file | origin | licence handling |
|---|---|---|
| `droid-hal-pdx246.spec` | new. Macro names and semantics from dhd (`droid-hal-device.inc`, `droid-hal-@DEVICE@.spec.template` @be67bbc); no template text copied. The vendor_dlkm sub-package (`%package vendor_dlkm` to the end) is modelled on dhd be67bbc `droid-hal-device.inc:364-370, 1169-1177, 1327-1332` (RPM boilerplate; dhd `License: BSD`), as an in-file comment says. Values from this analysis; none taken from sharks-dev's spec | SPDX header, Apache-2.0, Johannes Meyer zum Alten Borgloh |
| `helpers/img2simg.mk`, `helpers/simg2img.mk` | new, rewritten after dhd's `helpers/img2simg.mk` / `helpers/simg2img.mk` (BSD per dhd's RPM tag, no in-file notice) with `-std=gnu++17`; interface (file names, `*_SOURCES` variables, run directory) defined by dhd inc:513-519 and `dhd/helpers/makefile`. The shared part is the make skeleton (`*_SOURCES` default, include flags, object mapping, `-lz`, all/clean), noted in each file | SPDX header, Apache-2.0 |
| `helpers/matched-set.sh` | new | SPDX header, Apache-2.0 |
| `README.md`, `NOTES.md`, `SUBMODULES.md` | new | SPDX header (HTML comment), Apache-2.0 |
| `.gitmodules` | content as `git submodule add` writes it, URL mer-hybris/droid-hal-device | REUSE.toml, Apache-2.0 |
| `REUSE.toml` | new | own SPDX header |
| `LICENSES/Apache-2.0.txt` | Apache License 2.0 text, copied from `device/sony/pdx246/LICENSES/Apache-2.0.txt` (sha256 074e6e32...615ff) | licence text |
| `dhd/` (submodule, not part of this repository's own files) | mer-hybris/droid-hal-device @be67bbc | upstream; RPM `License: BSD` (inc:179), helper scripts carry BSD-3-Clause-style headers (Alin Marin Elena, Jolla Ltd., e.g. `helpers/util.sh:1-32`); not modified |

The repository text uses placeholders (`$ANDROID_ROOT`, `<sfos>`,
`<lineageos tree>`) instead of local paths.

The built RPMs carry dhd's licence tags (`License: BSD`, tools `ASL 2.0`), but
their content is Android build output under its own licences: AOSP and
LineageOS code, kernel modules built from GPL sources (vendor_boot, vendor_dlkm,
kernel-modules), and the dtb/dtbo from the device tree repo. The main package
copies `out/.../system` and the root directory, not `vendor/`, so it should
contain no Sony blobs from vendor/sony/pdx246, and the vendor_dlkm image only
holds built modules (proprietary-files.txt lists no `vendor_dlkm` or
`lib/modules` paths; working notes, findings.md). Of the `system/` entries in
proprietary-files.txt, only `system/lib64/libprotobuf-cpp-full.so` exists in the
`hybris out`, and it is the AOSP-built library: the stock blob is installed as
`system_ext/lib64/libprotobuf-cpp-full-stock.so` (`proprietary-files.txt:1701`),
which dhd does not copy. Check `rpm -qlp` before publishing any of these RPMs
(not yet checked on built packages).
