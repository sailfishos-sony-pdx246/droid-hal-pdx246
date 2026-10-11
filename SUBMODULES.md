<!--
SPDX-FileCopyrightText: Johannes Meyer zum Alten Borgloh
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Submodules of droid-hal-pdx246

Placeholders: `$ANDROID_ROOT` is the hybris-23.2 Android tree, `<sfos>` the
Sailfish OS workspace that holds the reference port checkouts.

The repository lives at `$ANDROID_ROOT/rpm`. To create it and add the
submodule:

```sh
cd $ANDROID_ROOT/rpm
git init -b main
git submodule add https://github.com/mer-hybris/droid-hal-device dhd
git -C dhd checkout be67bbcdcfb9f1e392dbac699928fa29c5c103cd
git add .gitmodules dhd
```

`git submodule add` downloads droid-hal-device (about 1.3 MB of git history).
Without network, clone it from a local checkout of the 10 IV/10 V reference
port instead, then point the URL back at GitHub:

```sh
git submodule add <sfos>/pdx235/droid-hal-pdx225/dhd dhd
git config -f .gitmodules submodule.dhd.url https://github.com/mer-hybris/droid-hal-device
git submodule sync
git -C dhd checkout be67bbcdcfb9f1e392dbac699928fa29c5c103cd
```

## The pin

| path | URL | commit | date |
|---|---|---|---|
| `dhd` | https://github.com/mer-hybris/droid-hal-device | `be67bbcdcfb9f1e392dbac699928fa29c5c103cd` | 2026-05-25, "Merge pull request #349 from mer-hybris/jb64176" |

This is the same commit as the Xperia 10 IV/10 V reference
(`<sfos>/pdx235/droid-hal-pdx225`, `git submodule status`).

### Why be67bbc and not master

On 2026-10-04, mer-hybris `master` is `775f6c05123ca7e58422df1fcfd51943eb56920f`
(GitHub API, branch list and commit list). It is be67bbc plus a single commit,
`44a1036` "dhd: Switch mount services to use /dev/disk/by-partlabel/"
(`git log be67bbc..775f6c0` in the local dhd checkout; `git diff --stat` shows only
`helpers/makefstab`, +3 lines). That commit rewrites every `*by-name` mount source
to `/dev/disk/by-partlabel/<name>`.

pdx246's fstab mounts four slotted partitions with bare names (`modem`, `dsp`,
`bluetooth`, `vm-bootsys`, flag `slotselect`), and makefstab has no slot handling.
With master the units would point at `/dev/disk/by-partlabel/modem`, `.../dsp` and
`.../bluetooth`, but the GPT labels are `modem_a`, `dsp_a`, `bluetooth_a`. So
`/vendor/firmware_mnt`, `/vendor/dsp` and `/vendor/bt_firmware` would never mount,
and the modem, ADSP/CDSP and Bluetooth firmware would be missing. A simulation of
both versions on the pdx246 fstab and rc files is in NOTES.md (D1).

With be67bbc the by-name sources go through `hybris/hybris-boot/fixup-mountpoints`,
whose pdx246 entry (branch hybris-23.2, ea2e10b) maps the bare names to slot a:
modem sda67, dsp sda71, bluetooth sda68.

Everything else droid-hal needs for Android 16 is identical in both commits:
version detection, the bootstrap bionic libraries, linkerconfig and apexd.rc,
`enable_vendor_boot_update`, `enable_dtbo_update`, the kernel-modules package.
The Android 15/16 support itself is older than be67bbc (`46779019`
"dhd: Add support for Android 15 and 16", 2025-12-21; `9fecf2b6`
"Package vendor-bootconfig.img if custom vendor_boot is used", 2026-02-13).

### Moving to master later

Possible once one of these is done:
- Add `/vendor/firmware_mnt /vendor/dsp /vendor/bt_firmware` to
  `makefstab_skip_entries` and have droid-config-pdx246 ship the three mount units
  with `What=/dev/disk/by-partlabel/<name>_a`; or
- get slot handling into makefstab upstream (for example a udev rule that links
  `/dev/disk/by-partlabel/<name>` to `<name>_a`/`_b` from `androidboot.slot_suffix`).

`helpers/matched-set.sh check` warns about by-partlabel units, as a reminder.

### Not taken: branch jb64684

`jb64684` (`24bd7deb1cf3561e0e1a56eb5bd6ac8d56f76ea5`, 2026-07-04, not merged) makes
dhd copy `apexd.rc` only if it exists, copies `linkerconfig` with `cp -af`, also
from `obj/EXECUTABLES/linkerconfig.com.android.runtime_intermediates/`, and fixes
`--without dhd_tools`. pdx246 does not need it: the hybris-hal output has
`system/etc/init/apexd.rc` and `apex/com.android.runtime/bin/linkerconfig`, and no
`system/bin/linkerconfig` that `cp -a` could trip over (NOTES.md, T3, checked on
the finished output). If a later build loses
`apex/com.android.runtime/bin/linkerconfig`, droid-hal would ship no
linkerconfig, and then jb64684 (or a copy step in `custom_install_cmds`) is
needed.
