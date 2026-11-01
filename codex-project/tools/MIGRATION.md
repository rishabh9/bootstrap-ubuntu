# AI Workstation migration — review copy

> Historical document: migration subsequently completed. Read the final checkpoint in HANDOVER.md (at the codex-project root) before taking action. Do not rerun the migration.

Prepared 1 November 2026 from the two reports collected 29 October. This is a
machine-specific proposal, not evidence that the migration has run. The user has
confirmed a backup, recovery USB and OS passphrase are ready. Execution still
requires explicit approval of the supplied script. Do not run original bootstrap
scripts. Do not perform other kernel/package updates during either apply stage.

## Files and scope

- `migrate-workstation.sh`: default prints its plan without changing anything;
  two explicit apply modes perform the migration with terminal confirmations.
- `test-migration-safety.py`: tests only the non-mutating command-line gates.
- Existing inspection scripts and reports remain unchanged.

The P310 OS installation, partition table, LUKS keyslots, Limine binary and
configuration, ROCm, Lemonade, and Podman storage are preserved. Root configuration
and kernel initramfs files necessarily change. Only the P510 partition's LUKS
header and filesystem are recreated. Neither physical disk is repartitioned.

### Pinned identities

OS: `/dev/disk/by-id/nvme-CT2000P310SSD8_REPLACE_P310_SERIAL-part2`

Data: `/dev/disk/by-id/nvme-CT2000P510SSD8_REPLACE_P510_SERIAL-part1`

Root LUKS UUID: `REPLACE_UUID_02`

Old data LUKS UUID: `REPLACE_UUID_03`

Root Btrfs UUID: `REPLACE_UUID_04`

ESP UUID: `REPLACE_ESP_UUID`

## Stage 1 — clean boot images, preserve existing Incus storage

After review and approval, from a local terminal on the workstation:

```bash
sudo bash migrate-workstation.sh boot-cleanup
```

The script verifies identities, available space and both reported kernel pairs;
requires a typed confirmation and tests the OS passphrase. It creates a private
backup at `/root/ai-workstation-migration` inside encrypted root, including ESP
files, configuration, original initramfs images, the old secondary key and both
LUKS headers. Copy essential recovery material to your independently encrypted
backup as appropriate; the on-disk backup alone does not protect against OS disk
loss. Never upload these backups or their extracted archive contents.

It moves the key-embedding hook out of initramfs-tools, temporarily suspends the
existing Limine update hook, and rebuilds the two retained initramfs images. It
checks for the known secondary-key filenames and refuses publication if the
embedded crypttab still references the secondary device. It publishes matching
`7.0.0-42` current and `7.0.0-38` fallback pairs and restores the update hook.

The secondary disk's existing key stays on encrypted root; its crypttab entry
stays unchanged. Incus is not deleted in this stage. Removing a key from initramfs
does not revoke the old key from the disk; the security fix completes in stage 2.

After successful completion, reboot manually. Check:

```bash
uname -r
findmnt /
findmnt /boot/efi
systemctl --no-pager status snap.lemonade-server.daemon.service
```

Confirm networking and normal desktop use. If the current kernel fails, choose
the previous-kernel entry in Limine. Stop if either path is unreliable. Do not
proceed solely because the script recorded a reboot; the human functional check
is required. Report the outcome before stage 2.

## Stage 2 — delete Incus and recreate P510 encryption

Only after the successful reboot checkpoint and approval to proceed:

```bash
sudo bash migrate-workstation.sh data-migration
```

Run via sudo from the normal `USER` account. The script refuses a repeated attempt
after the data stage has started. It checks for exactly the reported stopped
`rocm` instance and its single pool volume, displays dependencies and an APT
removal preview, then requires `ERASE P510 REPLACE_P510_SERIAL`.

It deletes the container, `gpuprof`, the default profile's root/network devices,
the Incus bridge and pool. It disables the obsolete crypttab entry, stops Incus,
closes the verified old mapping, and refuses formatting if device descendants or
mounts remain. The default profile's unused GPU device need not be individually
removed because Incus itself is retired.

**The destructive boundary is Incus resource deletion; disk encryption is then
recreated. There is no promise of recovering old Incus data after this point.**

At cryptsetup's interactive prompts, create and securely record a NEW recovery
passphrase for the P510. This is separate from the root disk passphrase. The
script enrolls a fresh random `/etc/luks-data-keyfile` and tests both key and
passphrase before creating Btrfs. It configures:

```text
cryptdata UUID=<new-LUKS-UUID> /etc/luks-data-keyfile luks,nofail,x-systemd.device-timeout=10s
UUID=<new-Btrfs-UUID> /data btrfs defaults,compress=zstd:3,noatime,nofail,x-systemd.device-timeout=10s 0 0
```

It mounts `/data`, creates models/services/projects/datasets/scratch directories,
and leaves `/data/services` root-owned for future per-service permissions. The
other four directories belong to the invoking user. It backs up the NEW header
inside encrypted root. APT asks for confirmation when removing the four reported
Incus packages; read the actual removal list and decline if it differs materially.
No blanket autoremove, GPU installation or Podman/Lemonade configuration occurs.

The data entry is intended for post-root systemd unlocking, with no initramfs
key hook. The old disk UUID must already be absent from the stage-1 embedded
crypttab checks, so reformatting cannot break an early-boot dependency.

## Stage 3 — verify before putting important data on P510

Reboot manually again, then collect:

```bash
uname -r
lsblk -e 7 -o NAME,SIZE,MODEL,SERIAL,FSTYPE,UUID,MOUNTPOINTS
findmnt /data
sudo cryptsetup status cryptdata
systemctl --failed
systemctl --no-pager status snap.lemonade-server.daemon.service
sudo lsinitramfs /boot/efi/initrd.img | grep -E 'luks-(incus|data)-keyfile'
sudo lsinitramfs /boot/efi/initrd.img.old | grep -E 'luks-(incus|data)-keyfile'
```

The last two commands should print nothing (grep exit status 1 is expected).
Confirm one OS passphrase prompt, automatic `/data` unlock, working networking
and working Lemonade inference. Verify the actual GPU backend separately; an
active daemon is not proof of GPU offload. Save a new inspection report.

Copy the NEW P510 header backup to secure external storage. Retire the old
`/etc/luks-incus-keyfile` and old key-bearing backups only after successful
validation and a deliberate backup-retention decision. New LUKS formatting
creates a new volume key, so old keys and headers cannot unlock the NEW data.
They can still compromise preserved copies of OLD data. SSD deletion and Btrfs
snapshots make reliable erasure of old copies more involved than deleting paths.

Retire the obsolete Incus APT source/key and group memberships after checking
whether its signing key/repository serves any other installed packages. These
are deferred cleanup, not a reason to couple package-source edits to disk writes.

## Failure and recovery

If an apply stage fails, STOP. Do not rerun it blindly or delete the state
directory. Record the last successful operation and the error. Do not reboot
after a boot-image publication failure until a matching pair is verified.

Before stage 2, the saved ESP pairs can restore the previous boot state. Those
old images contain the exposed secondary key and are an emergency recovery
measure, not the desired final state.

If Ubuntu cannot boot, use the USB's live environment. Identify disks afresh by
the persistent IDs above. Example recovery mount sequence (these commands are
for the recovery environment only):

```bash
sudo cryptsetup open /dev/disk/by-id/nvme-CT2000P310SSD8_REPLACE_P310_SERIAL-part2 recovery-root
sudo mkdir -p /mnt/recovery
sudo mount -o subvol=@ /dev/mapper/recovery-root /mnt/recovery
sudo mount /dev/disk/by-id/nvme-CT2000P310SSD8_REPLACE_P310_SERIAL-part1 /mnt/recovery/boot/efi
```

Backups are then at `/mnt/recovery/root/ai-workstation-migration`. Restore only
the needed matching kernel/initramfs pair and corresponding root-side image.
If stage 1 failed before publication, its original ESP files may still be intact.
The temporarily moved update hook should be restored from `update-hook.disabled`
if present, or `zz-update-limine` in the backup. For an emergency full return to
pre-stage-1 behavior, the saved key hook and initramfs/ESP images are available.
Do not overwrite a healthy LUKS header merely to fix a boot-file problem.

**After P510 recreation, NEVER restore `p510-old.header` or the old crypttab
wholesale.** Recover the OS boot independently. The new P510 passphrase can open
it as `recovery-data` if automatic unlocking fails. Its new header backup is
`p510-new.header`. A failed data stage may require manually completing crypttab,
fstab or key enrollment from its observed state; do not format it a second time.

ESP publication uses staged copies and individual renames; changing two files is
not a single atomic transaction. A power failure can interrupt a pair update.
The other slot and encrypted backups provide recovery options, not a guarantee.

## Verification limits and follow-up

Local verification covers Bash parsing and non-mutating CLI safety gates only.
No apply mode has run on this workspace or on the workstation; there has been no
end-to-end VM migration test. Runtime guards stop unexpected layouts rather than
trying to adapt them. Review the actual machine state at each checkpoint.

The existing Limine update hook is restored for continuity; its long-term
rotation/atomicity weakness is not redesigned by this one-time migration.
After storage validation, update bootstrap documentation/scripts, improve that
maintenance hook, and configure rootless Podman with explicit mount dependencies.
Do not add new inference software until the existing Lemonade/ROCm setup has
been evaluated.

References: [cryptsetup key enrollment](https://www.man7.org/linux/man-pages/man8/cryptsetup-luksAddKey.8.html),
[Incus profiles](https://linuxcontainers.org/incus/docs/main/profiles/),
[systemd crypttab](https://www.freedesktop.org/software/systemd/man/latest/crypttab.html).
