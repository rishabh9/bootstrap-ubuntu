#!/usr/bin/env bash
# FRESH INSTALL ONLY. Post-root /data unlock; never embed its key in initramfs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/00-config.sh"
require_fresh_install
require_target
for hook in "$TARGET/etc/initramfs-tools/hooks/luks-keyfile"; do
    [[ ! -e $hook ]] || fail 'Legacy key-embedding hook exists; inspect it manually.'
done
KEYFILE="$TARGET/etc/luks-data-keyfile"
if [[ ! -e $KEYFILE ]]; then
    (umask 077; dd if=/dev/urandom of="$KEYFILE" bs=4096 count=1 status=none)
fi
chmod 600 "$KEYFILE"
if ! cryptsetup open --test-passphrase --key-file "$KEYFILE" "$DATA_PART"; then
    cryptsetup luksAddKey "$DATA_PART" "$KEYFILE"
fi
cryptsetup open --test-passphrase --key-file "$KEYFILE" "$DATA_PART"
ROOT_PART_UUID=$(cryptsetup luksUUID "$ROOT_PART")
DATA_PART_UUID=$(cryptsetup luksUUID "$DATA_PART")
cat > "$TARGET/etc/crypttab" <<EOF
$ROOT_MAPPER UUID=$ROOT_PART_UUID none luks
$DATA_MAPPER UUID=$DATA_PART_UUID /etc/luks-data-keyfile luks,nofail,x-systemd.device-timeout=10s
EOF
mkdir -p "$TARGET/data"
# ─── Step 3: Set up swap ────────────────────────────────────────────────────

step "Setting up Btrfs swapfile"

# Mount the swap subvolume inside the target
mkdir -p "$TARGET/swap"
ROOT_BTRFS_UUID=$(blkid -s UUID -o value /dev/mapper/"$ROOT_MAPPER")

# The swap subvolume should already be in fstab from script 02.
# Mount it now so we can create the swapfile.
if ! mountpoint -q "$TARGET/swap"; then
    mount -o "subvol=$SUBVOL_SWAP,noatime" /dev/mapper/"$ROOT_MAPPER" "$TARGET/swap"
fi

# Create the swapfile.
# Btrfs swapfiles require: no compression, no COW, contiguous allocation.
chroot "$TARGET" /bin/bash -e << 'CHROOT_EOF'

if [ -f /swap/swapfile ]; then
    echo "Swapfile already exists at /swap/swapfile. Skipping."
else
    # Create a 4 GiB swapfile using the modern btrfs-progs command (btrfs-progs
    # 6.1+ / kernel 6.1+, available on Ubuntu 26.04).
    # This command sets NOCOW, preallocates contiguous space, and zeros the file
    # atomically — replacing the old truncate+chattr+dd sequence.
    btrfs filesystem mkswapfile --size 4G /swap/swapfile
    chmod 600 /swap/swapfile
    mkswap /swap/swapfile

    # Add to fstab only if not already present
    if ! grep -q '/swap/swapfile' /etc/fstab; then
        echo "/swap/swapfile    none    swap    defaults    0    0" >> /etc/fstab
    fi

    echo "4 GiB swapfile created at /swap/swapfile"
fi

CHROOT_EOF


chroot "$TARGET" update-initramfs -u -k all
for image in "$TARGET"/boot/initrd.img-*; do
    verify_initramfs "$image"
    checked=$(mktemp -d "$TARGET/root/initramfs-check.XXXXXX")
    unmkinitramfs "$image" "$checked"
    while IFS= read -r -d '' config; do
        if grep -E 'cryptdata|luks-data-keyfile' "$config" >/dev/null; then
            fail "Data disk present in early-boot crypttab: $config"
        fi
    done < <(find "$checked" -type f -path '*/cryptroot/crypttab' -print0)
    # Checked files remain inside encrypted root for inspection.
done
echo 'Next: 04-install-limine.sh. Record and test both recovery passphrases.'
