# Ubuntu 26.04 LTS — encrypted Btrfs workstation with Limine

Target: Ryzen AI Max+ PRO 395, Radeon 8060S, 128 GB shared memory. Two independent
SSDs: P310 for Ubuntu/home and P510 for general-purpose `/data`. No Incus, RAID or
spanning filesystem is provisioned. Ubuntu 26.04 codename is `resolute`.

## Existing workstation versus fresh installation

**The workstation migration is complete. Do not run scripts 01–04 on it.**
The verified continuation and recovery history are in [codex-project/HANDOVER.md](codex-project/HANDOVER.md).
Historical reports are evidence from before migration, not current inventory.

Scripts 01–04 are destructive **fresh-install tools for a live USB only**. They
require explicit `FRESH_INSTALL=ERASE_BOTH_DISKS`, root, live-environment detection,
and selected disk identifiers. Script 01 erases BOTH selected disks. Review every
operation and keep independently verified backups and recovery media. No fresh
Ubuntu 26.04 installation with this revised pipeline has yet been tested end-to-end.

## Storage and encryption

| Disk role | Layout |
|---|---|
| P310 OS | p1: FAT32 ESP, 1 GiB; p2: LUKS2 → Btrfs |
| P510 data | p1: LUKS2 → Btrfs, mounted at `/data` |

Root uses `@`, `@home`, `@log`, `@pkg`, `@swap`. A 4 GiB Btrfs swapfile remains a
safety net, not a model-memory expansion strategy. Root and data need recovery
passphrases. The random `/etc/luks-data-keyfile` lives inside encrypted root with
0600 permissions; systemd reads it AFTER root unlocks. It must never be embedded
in initramfs, which Limine reads from the unencrypted ESP. The installer checks
archive filenames and extracted early crypttab entries before boot publication.

`/data` is independent, with shared capacity rather than fixed-size allocations.
Create `models`, `services`, `projects`, `datasets`, `scratch` as needed. Give
ownership to the specific user/service, not broad permissions on all service data.
Services must require the actual mount so they do not write into the underlying
OS directory if the data disk is absent. `nofail` allows OS boot without data;
that degraded boot path is not yet separately tested.

## Fresh installation procedure

Use a Ubuntu 26.04 live USB, UEFI, working networking and current debootstrap.
Retain the known-working Limine firmware/Secure Boot policy; this setup does not
establish a signed Secure Boot chain. Inspect serial numbers and live-root ancestry:

```bash
lsblk -e 7 -o NAME,MODEL,SERIAL,SIZE,TYPE,MOUNTPOINTS
ls -l /dev/disk/by-id/
```

Set explicit whole-disk `OS_DISK` and `DATA_DISK` values in `00-config.sh`, or pass
them as environment variables through sudo. Never rely on nvme0/nvme1 numbering.
Example placeholders below must be replaced; they are not actual targets:

```bash
sudo env FRESH_INSTALL=ERASE_BOTH_DISKS \
  OS_DISK=/dev/disk/by-id/REPLACE_OS_ID \
  DATA_DISK=/dev/disk/by-id/REPLACE_DATA_ID \
  bash scripts/01-partition-and-encrypt.sh
```

Run 02, 03, 04 in order with the SAME environment. Do not reboot between stages.

| Script | Responsibility |
|---|---|
| 00 | Side-effect-free shared configuration and guards |
| 01 | Verify targets, confirm, erase both disks, partition, LUKS2, Btrfs/root mounts |
| 02 | Bootstrap resolute, generic kernel/headers, fstab, initial crypttab, user/network |
| 03 | Enroll data key on encrypted root, swap, rebuild and inspect initramfs |
| 04 | Install Limine and generation-based maintenance hooks |
| 05 | Optional installed-system Podman prerequisites, no disk or boot writes |
| 06 | Optional Niri/greetd desktop; independent of disks and Podman |

Script 06 changes the display manager and installs source-built software; it is
not routine maintenance. Review its pinned versions and desktop preference first.
The verified workstation uses its existing desktop; running 06 is unnecessary.

## Limine maintenance

`maintenance/update-limine` is installed into `/usr/local/sbin` by script 04.
Kernel install/removal and initramfs updates call it. It selects the newest two
complete installed kernel pairs, checks for root unlock configuration and known
secondary key filenames, stages and compares both pairs in a fresh ESP generation,
then switches each menu file by rename. Identical repeated package-hook calls are no-ops. Older changed generations are retained for recovery.
A previous installed kernel is not necessarily a previously tested kernel.

The helper refuses missing ESPs or insufficient staging space. Review unreferenced
generations manually as the ESP fills; no automated deletion is performed. A failed
update may leave an unused staging generation. Menu copies are individually
published, not a globally atomic transaction; retain recovery USB and backups.

**These new hooks are repository changes only. They have not replaced the working
hooks on the installed workstation.** Review and test them before live adoption.
Default mapper `cryptroot` and root subvolume `@` are required by the helper.

## AI, networking and containers

Preserve working Ubuntu `amdgpu` and `r8169`. The observed Ubuntu 26.04 workstation
uses r8169 for RTL8127; the historical vendor tarball is retained but never built
or blacklisted automatically. GPU userspace support must match the chosen backend;
no GPU driver or ROCm stack is installed by these scripts.

Existing Lemonade/ROCm works on the migrated workstation; do not replace it merely
because the installer changed. For a new installation, choose one inference
backend and validate actual GPU offload before tuning model size, context or UMA.

05 installs Podman prerequisites only. Run Podman as a normal user. Configure
per-user Quadlets and lingering only for a concrete persistent-service requirement.
No rootful API socket or Incus daemon is enabled. Use VMs for higher-risk untrusted
code; kernel-sharing containers do not provide a VM boundary.

## Backups and recovery

Snapshots are not independent backups and do not include the ESP or sibling
subvolumes automatically. Keep compatible ESP kernel/initramfs pairs alongside
root snapshots. Never snapshot active swap as part of a root snapshot policy.
Back up important data independently.

Back up LUKS headers separately after key changes. A header backup plus a valid
credential can unlock its associated encrypted data; protect the backup. A
password-encrypted header file can be stored on an ordinary USB. Verify decrypting
that USB copy against the original and retain its password separately. Header
backups do not recover a lost disk or substitute for file backups. Never restore
an OLD P510 header after the data volume has been recreated.

The legacy review and VM RCU documents are historical, not installation instructions.
Do not weaken Argon2 parameters on the basis of their unverified hypotheses.

## Validation

```bash
python3 -m unittest discover -s tests
python3 codex-project/tools/test-migration-safety.py
for script in scripts/*.sh maintenance/update-limine; do bash -n "$script"; done
```

Tests must not execute destructive operations. Fresh-install boot, generation-hook
publication and failure recovery still require disposable VM testing before use.
