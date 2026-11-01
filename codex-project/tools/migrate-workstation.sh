#!/usr/bin/env bash
# Machine-specific migration DRAFT. Read MIGRATION.md before applying.
# Default mode prints the plan only. Never source the original bootstrap scripts.
set -Eeuo pipefail
export LC_ALL=C
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
umask 077
die() { printf 'STOP: %s\n' "$*" >&2; exit 1; }
(( $# <= 1 )) || die 'Supply at most one mode; unattended confirmation is unsupported.'
mode=${1:-plan}
case "$mode" in
    plan|--help)
        cat <<'EOF'
No changes made. Machine-specific migration proposal:
  boot-cleanup   Back up configuration and ESP inside encrypted root; remove the
                 secondary-key initramfs hook; rebuild and verify both kernel pairs.
  Reboot and confirm Ubuntu, networking and Lemonade work.
  data-migration Delete the disposable Incus resources; recreate encryption and
                 Btrfs on P510 partition 1 only; mount /data with post-root unlock.
Apply modes require sudo, an interactive terminal and typed confirmations.
Read MIGRATION.md and obtain approval before running either apply mode.
EOF
        exit 0 ;;
    boot-cleanup|data-migration) ;;
    *) die "Unknown mode: $mode" ;;
esac
[[ -t 0 && -t 1 ]] || die 'Apply modes require an interactive terminal.'
(( EUID == 0 )) || die 'Apply modes require sudo.'
die 'Public redacted recovery copy: restore the exact LOCAL script and re-review before applying.'

ROOT_PART=/dev/disk/by-id/nvme-CT2000P310SSD8_REPLACE_P310_SERIAL-part2
DATA_PART=/dev/disk/by-id/nvme-CT2000P510SSD8_REPLACE_P510_SERIAL-part1
ROOT_UUID=REPLACE_UUID_02
OLD_DATA_UUID=REPLACE_UUID_03
ROOT_FS=REPLACE_UUID_04
ESP_UUID=REPLACE_ESP_UUID
STATE=/root/ai-workstation-migration
KEY=/etc/luks-data-keyfile
NEW=7.0.0-42-generic
OLD=7.0.0-38-generic
HOOK=/etc/initramfs-tools/hooks/luks-keyfile
UPDATE=/etc/initramfs/post-update.d/zz-update-limine

confirm() {
    local answer
    printf '\n%s\nType exactly: %s\n' "$1" "$2"
    read -r answer
    [[ $answer == "$2" ]] || die 'Confirmation did not match.'
}
for tool in findmnt lsblk blkid cryptsetup readlink python3 sha256sum lsinitramfs unmkinitramfs \
    update-initramfs mountpoint cp mv cmp df stat flock; do
    command -v "$tool" >/dev/null || die "Missing required tool: $tool"
done
exec 9>/run/lock/ai-workstation-migration.lock
flock -n 9 || die 'Another migration process is running.'
[[ -b $ROOT_PART && -b $DATA_PART ]] || die 'Expected persistent partition identifiers are missing.'
[[ $(cryptsetup luksUUID "$ROOT_PART") == "$ROOT_UUID" ]] || die 'OS encryption UUID changed.'
[[ $(findmnt -nro UUID /) == "$ROOT_FS" ]] || die 'Unexpected running root filesystem.'
[[ $(findmnt -nro UUID -T /root) == "$ROOT_FS" ]] || die '/root must be on encrypted OS storage.'
[[ $(findmnt -nro UUID /boot/efi) == "$ESP_UUID" ]] || die 'Unexpected ESP.'
mountpoint -q /boot/efi || die 'ESP is not mounted.'
[[ $(lsblk -dnro PKNAME "$(readlink -f "$ROOT_PART")") != \
   $(lsblk -dnro PKNAME "$(readlink -f "$DATA_PART")") ]] || die 'OS and data partitions share a physical disk.'
data_parent=$(lsblk -dnro PKNAME "$(readlink -f "$DATA_PART")")
[[ $(lsblk -dnro SERIAL "/dev/$data_parent" | xargs) == REPLACE_P510_SERIAL ]] || die 'P510 serial mismatch.'
[[ $(lsblk -dnro MODEL "/dev/$data_parent" | xargs) == CT2000P510SSD8 ]] || die 'P510 model mismatch.'
# Root must have exactly the known OS partition in its block ancestry.
lsblk -snro PATH "$(findmnt -nro SOURCE / | sed 's/\[.*//')" | \
    grep -Fx "$(readlink -f "$ROOT_PART")" >/dev/null || die 'Root ancestry does not match P310.'
for version in "$NEW" "$OLD"; do
    [[ -f /boot/vmlinuz-$version && -f /boot/initrd.img-$version && -d /lib/modules/$version ]] \
        || die "Required kernel pair missing: $version"
done

verify_image() {
    local image=$1 listing
    listing=$(lsinitramfs "$image") || die "Cannot inspect $image"
    [[ $listing == *cryptroot/crypttab* ]] || die "Root unlock configuration missing from $image"
    if printf '%s\n' "$listing" | grep -E '(^|/)(luks-incus-keyfile|luks-data-keyfile)$' >/dev/null; then
        die "Secondary key found in $image"
    fi
}

verify_early_devices() {
    local image=$1 directory=$2 config
    mkdir -m 700 "$directory"
    unmkinitramfs "$image" "$directory"
    # Retain unpacked files inside encrypted root for review/recovery.
    while IFS= read -r -d '' config; do
        if grep -E 'cryptincus|cryptdata|REPLACE_UUID_03' "$config" >/dev/null; then
            die 'Secondary disk is still required in early boot. Do not publish these images; inspect the saved files.'
        fi
    done < <(find "$directory" -type f -path '*/cryptroot/crypttab' -print0)
}

if [[ $mode == boot-cleanup ]]; then
    [[ ! -e $STATE ]] || die "State already exists at $STATE; inspect it instead of rerunning."
    [[ -f $HOOK && -x $UPDATE && -f /etc/luks-incus-keyfile ]] || die 'Expected key hook or boot-update hook missing.'
    [[ $(cryptsetup luksUUID "$DATA_PART") == "$OLD_DATA_UUID" ]] || die 'Secondary encryption UUID changed.'
    [[ $(df -Pk /root | awk 'NR==2 {print $4}') -gt 4194304 ]] || die 'Need at least 4 GiB free on encrypted root.'
    [[ $(df -Pk /boot/efi | awk 'NR==2 {print $4}') -gt 307200 ]] || die 'Need at least 300 MiB free on ESP.'
    confirm 'This changes initramfs and ESP boot images. No disks will be formatted. Recovery preparations must be ready.' 'CLEAN BOOT IMAGES'
    echo 'Verify your OS passphrase locally now (nothing is displayed):'
    cryptsetup open --test-passphrase "$ROOT_PART"
    mkdir -m 700 "$STATE"
    cp -a /etc/crypttab /etc/fstab "$STATE/"
    cp -a /boot/efi "$STATE/esp"
    cp -a /etc/luks-incus-keyfile "$STATE/"
    cp -a /boot/initrd.img-"$NEW" /boot/initrd.img-"$OLD" "$STATE/"
    cp -a "$UPDATE" "$STATE/zz-update-limine"
    cryptsetup luksHeaderBackup "$ROOT_PART" --header-backup-file "$STATE/p310.header"
    cryptsetup luksHeaderBackup "$DATA_PART" --header-backup-file "$STATE/p510-old.header"
    # Moving hooks outside their execution directories prevents automatic ESP rotation.
    mv "$HOOK" "$STATE/luks-keyfile.hook"
    mv "$UPDATE" "$STATE/update-hook.disabled"
    restore_update_hook() {
        if [[ -f $STATE/update-hook.disabled ]]; then mv "$STATE/update-hook.disabled" "$UPDATE"; fi
    }
    trap restore_update_hook EXIT
    for version in "$NEW" "$OLD"; do
        update-initramfs -u -k "$version"
        verify_image "/boot/initrd.img-$version"
        verify_early_devices "/boot/initrd.img-$version" "$STATE/checked-$version"
    done
    # Stage complete files first. Individual renames are atomic, a pair is not.
    # The fallback remains untouched until the current pair has been published.
    for slot in current fallback; do
        version=$NEW; suffix=''
        if [[ $slot == fallback ]]; then version=$OLD; suffix=.old; fi
        cp "/boot/vmlinuz-$version" "/boot/efi/vmlinuz$suffix.new"
        cp "/boot/initrd.img-$version" "/boot/efi/initrd.img$suffix.new"
        cmp "/boot/vmlinuz-$version" "/boot/efi/vmlinuz$suffix.new"
        cmp "/boot/initrd.img-$version" "/boot/efi/initrd.img$suffix.new"
        sync
        mv "/boot/efi/vmlinuz$suffix.new" "/boot/efi/vmlinuz$suffix"
        mv "/boot/efi/initrd.img$suffix.new" "/boot/efi/initrd.img$suffix"
        sync
    done
    verify_image /boot/efi/initrd.img
    verify_image /boot/efi/initrd.img.old
    cat /proc/sys/kernel/random/boot_id > "$STATE/boot-cleaned-at"
    echo 'Boot cleanup complete. Reboot manually; verify Ubuntu, networking and Lemonade before data-migration.'
    echo "Backups remain inside encrypted root: $STATE"
    exit 0
fi

[[ -f $STATE/boot-cleaned-at && ! -e $STATE/data-started ]] || die 'Boot cleanup must complete first; data migration cannot be rerun automatically.'
[[ $(cat "$STATE/boot-cleaned-at") != "$(cat /proc/sys/kernel/random/boot_id)" ]] || die 'Reboot after boot cleanup before continuing.'
[[ $(uname -r) == "$NEW" || $(uname -r) == "$OLD" ]] || die 'Unexpected running kernel.'
[[ ! -e $HOOK && ! -e $KEY && ! -e /dev/mapper/cryptdata ]] || die 'Unexpected existing key, mapper or initramfs hook.'
verify_image /boot/efi/initrd.img
verify_image /boot/efi/initrd.img.old
[[ $(cryptsetup luksUUID "$DATA_PART") == "$OLD_DATA_UUID" ]] || die 'Secondary encryption UUID changed.'
[[ ! -e /data || ( -d /data && -z $(ls -A /data) ) ]] || die '/data is not an empty directory.'
[[ ${SUDO_USER:-root} != root ]] || die 'Run through sudo from the normal account.'
for tool in incus mkfs.btrfs btrfs apt-get systemctl udevadm; do
    command -v "$tool" >/dev/null || die "Missing required tool: $tool"
done
systemctl is-active --quiet incus.service || die 'Incus must be running for dependency checks.'
# Never inherit a CLI default remote or selected project.
incus_local=(incus --force-local --project default)
"${incus_local[@]}" project list --format json | python3 -c '
import json,sys
x=json.load(sys.stdin)
assert len(x)==1 and x[0]["name"]=="default", "Unexpected Incus projects"
'
"${incus_local[@]}" storage list --format json | python3 -c '
import json,sys
x=json.load(sys.stdin)
assert len(x)==1 and x[0]["name"]=="incus-pool" and x[0]["driver"]=="btrfs", "Unexpected Incus pools"
'
# Check the backing device BEFORE deleting any Incus resource, not just before format.
mapped=$(cryptsetup status cryptincus | awk '$1=="device:" {print $2}')
[[ $(readlink -f "$mapped") == "$(readlink -f "$DATA_PART")" ]] || die 'cryptincus maps an unexpected device.'
[[ $(findmnt -nro UUID /var/lib/incus/storage-pools/incus-pool) == REPLACE_UUID_05 ]] || die 'Unexpected mounted pool filesystem.'
"${incus_local[@]}" storage get incus-pool source | grep -Fx REPLACE_UUID_05 >/dev/null || die 'Incus pool source changed.'
"${incus_local[@]}" list --all-projects --format json | python3 -c '
import json,sys
x=json.load(sys.stdin)
assert len(x)==1 and x[0]["name"]=="rocm" and x[0]["status"]=="Stopped" and x[0].get("project","default")=="default", "Unexpected instances"
'
"${incus_local[@]}" storage volume list incus-pool --format json | python3 -c '
import json,sys
x=json.load(sys.stdin)
assert len(x)==1 and x[0]["name"]=="rocm" and x[0]["type"]=="container", "Unexpected volumes"
'
"${incus_local[@]}" storage show incus-pool
"${incus_local[@]}" network show incusbr0
apt-get --simulate remove incus incus-base incus-client incus-ui-canonical
confirm 'Confirm the clean reboot, networking and Lemonade work. This deletes Incus and ALL P510 data; P310 is preserved.' 'ERASE P510 REPLACE_P510_SERIAL'
touch "$STATE/data-started"
"${incus_local[@]}" delete rocm
"${incus_local[@]}" profile delete gpuprof
"${incus_local[@]}" profile device remove default root
"${incus_local[@]}" profile device remove default eth0
"${incus_local[@]}" network delete incusbr0
"${incus_local[@]}" storage delete incus-pool
# Refuse to close a different mapped device, even if mapper names were reused.
mapped=$(cryptsetup status cryptincus | awk '$1=="device:" {print $2}')
[[ $(readlink -f "$mapped") == "$(readlink -f "$DATA_PART")" ]] || die 'cryptincus maps an unexpected device.'
[[ -z $(lsblk -nro MOUNTPOINTS "$(readlink -f "$DATA_PART")" | tr -d '[:space:]') ]] || die 'Data partition still has mounted descendants.'
# Stop automatic reopening before removing the old header.
python3 - <<'PY'
from pathlib import Path
p=Path('/etc/crypttab')
lines=p.read_text().splitlines(True)
entries=[s for s in lines if s.strip() and not s.lstrip().startswith('#') and s.split()[0]=='cryptincus']
assert len(entries)==1, 'Expected exactly one cryptincus entry'
p.write_text(''.join('# Retired by migration: '+s if s in entries else s for s in lines))
PY
systemctl daemon-reload
systemctl stop incus.socket incus-user.socket incus-startup.service incus.service incus-lxcfs.service
cryptsetup close cryptincus
[[ ! -e /dev/mapper/cryptincus ]] || die 'Old mapping remains open.'
[[ -z $(lsblk -nro MOUNTPOINTS "$(readlink -f "$DATA_PART")" | tr -d '[:space:]') ]] || die 'Data partition became mounted.'
[[ $(cryptsetup luksUUID "$DATA_PART") == "$OLD_DATA_UUID" ]] || die 'Data identity changed before format.'
[[ $(lsblk -nr "$DATA_PART" | wc -l) -eq 1 ]] || die 'Data partition still has device-mapper descendants.'
echo 'Create a NEW P510 recovery passphrase at the cryptsetup prompts. Record it securely.'
cryptsetup luksFormat --type luks2 "$DATA_PART"
cryptsetup open "$DATA_PART" cryptdata
dd if=/dev/urandom of="$KEY" bs=4096 count=1 status=none
chmod 600 "$KEY"
cryptsetup luksAddKey "$DATA_PART" "$KEY"
cryptsetup open --test-passphrase --key-file "$KEY" "$DATA_PART"
echo 'Verify the NEW P510 recovery passphrase:'
cryptsetup open --test-passphrase "$DATA_PART"
mkfs.btrfs -L workstation-data /dev/mapper/cryptdata
data_luks=$(cryptsetup luksUUID "$DATA_PART")
data_fs=$(blkid -s UUID -o value /dev/mapper/cryptdata)
[[ -n $data_luks && -n $data_fs && $data_luks != "$OLD_DATA_UUID" ]] || die 'New UUID verification failed.'
printf 'cryptdata UUID=%s %s luks,nofail,x-systemd.device-timeout=10s\n' "$data_luks" "$KEY" >> /etc/crypttab
printf '\nUUID=%s /data btrfs defaults,compress=zstd:3,noatime,nofail,x-systemd.device-timeout=10s 0 0\n' "$data_fs" >> /etc/fstab
mkdir -p /data
systemctl daemon-reload
mount /data
[[ $(findmnt -nro UUID /data) == "$data_fs" ]] || die 'Unexpected /data mount.'
mkdir /data/{models,services,projects,datasets,scratch}
chown "$SUDO_USER:$(id -gn "$SUDO_USER")" /data/{models,projects,datasets,scratch}
chmod 755 /data /data/services
cryptsetup luksHeaderBackup "$DATA_PART" --header-backup-file "$STATE/p510-new.header"
# Remove packages only after verified new storage. apt asks for its own confirmation.
apt-get remove incus incus-base incus-client incus-ui-canonical
findmnt --verify --verbose
printf '%s\n' "$data_luks" > "$STATE/data-completed"
echo 'Data migration complete. Back up the NEW header securely; reboot and verify /data and Lemonade.'
echo 'Do not restore the old P510 header. Do not run blanket apt autoremove.'
echo 'Old key-bearing backups remain protected inside encrypted root for controlled retirement.'
