#!/usr/bin/env bash
# =============================================================================
# 04-install-limine.sh
# =============================================================================
# This script:
#   1. Downloads Limine v10.x pre-built binaries
#   2. Installs BOOTX64.EFI to the EFI System Partition
#   3. Creates limine.conf with the correct kernel path
#   4. COPIES (not symlinks!) the kernel and initramfs to the ESP
#   5. Installs kernel update hooks so future apt upgrades stay bootable
#   6. Registers Limine in the UEFI boot manager
#
# Prerequisites:
#   - Scripts 01-03 have been run successfully
#   - Chroot bind mounts are still active
#
# Usage:
#   sudo bash 04-install-limine.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/00-config.sh"

require_fresh_install
require_target

# ─── Step 1: Download Limine ────────────────────────────────────────────────

step "Downloading Limine v10.x binaries"

echo "Cloning Limine binary release from Codeberg..."
echo ""

# Clone into a temporary directory. Register cleanup on exit so the temp dir
# is always removed even if git clone fails partway through.
LIMINE_TMP=$(mktemp -d)
trap 'rm -rf "$LIMINE_TMP"' EXIT

git clone https://codeberg.org/Limine/Limine.git \
    --branch=v10.x-binary --depth=1 \
    "$LIMINE_TMP" || {
    echo ""
    echo "ERROR: git clone failed. Check your internet connection."
    echo "       Source: https://codeberg.org/Limine/Limine.git (branch v10.x-binary)"
    exit 1
}

echo "Limine downloaded to $LIMINE_TMP"
ls -la "$LIMINE_TMP/"

# ─── Step 2: Install Limine to ESP ──────────────────────────────────────────

step "Installing Limine to EFI System Partition"

# Create the Limine directory on the ESP
mkdir -p "$TARGET/boot/efi/EFI/limine"
mkdir -p "$TARGET/boot/efi/EFI/BOOT"

# Validate the UEFI binary before installing it.
# A missing or truncated file produces a system that silently fails to boot.
BOOTX64="$LIMINE_TMP/BOOTX64.EFI"
if [[ ! -f "$BOOTX64" ]]; then
    echo "ERROR: BOOTX64.EFI not found at $BOOTX64"
    echo "       The v10.x-binary branch stores all files at the repo root (no bin/ subdir)."
    echo "       List of files in the cloned repo:"
    ls -la "$LIMINE_TMP/"
    exit 1
fi
BOOTX64_SIZE=$(stat -c %s "$BOOTX64")
if [[ "$BOOTX64_SIZE" -lt 65536 ]]; then
    echo "ERROR: BOOTX64.EFI is only ${BOOTX64_SIZE} bytes — file appears truncated or corrupted."
    exit 1
fi

# Copy the UEFI binary — BOOTX64.EFI is for x86_64 UEFI systems.
cp "$BOOTX64" "$TARGET/boot/efi/EFI/limine/"

# Also install as the fallback bootloader (EFI/BOOT/BOOTX64.EFI).
# This ensures the system boots even if UEFI entries get wiped.
cp "$BOOTX64" "$TARGET/boot/efi/EFI/BOOT/"

echo "Limine UEFI binary installed."
# Temp dir is cleaned up by the EXIT trap set during clone.

# Install the reviewed maintenance helper, then publish a complete boot generation.
install -m755 "$SCRIPT_DIR/../maintenance/update-limine" "$TARGET/usr/local/sbin/update-limine"
for directory in etc/kernel/postinst.d etc/kernel/postrm.d etc/initramfs/post-update.d; do
    mkdir -p "$TARGET/$directory"
    cat > "$TARGET/$directory/zz-update-limine" <<'HOOK'
#!/bin/sh
exec /usr/local/sbin/update-limine
HOOK
    chmod 755 "$TARGET/$directory/zz-update-limine"
done
chroot "$TARGET" /usr/local/sbin/update-limine

# ─── Step 6: Register Limine in UEFI boot manager ───────────────────────────

step "Registering Limine with UEFI boot manager (efibootmgr)"

# efibootmgr needs to write to EFI variables, which live on the efivarfs
# filesystem at /sys/firmware/efi/efivars. A plain "mount --bind /sys"
# does NOT include efivarfs — it is a separate submount on the host and
# is invisible inside the chroot without an explicit bind.
if mountpoint -q /sys/firmware/efi/efivars 2>/dev/null; then
    mountpoint -q "$TARGET/sys/firmware/efi/efivars" 2>/dev/null \
        || mount --bind /sys/firmware/efi/efivars "$TARGET/sys/firmware/efi/efivars"
else
    echo "WARNING: /sys/firmware/efi/efivars is not mounted on the live system."
    echo "         This usually means the live USB booted in legacy BIOS mode."
    echo "         efibootmgr will be skipped — the system will rely on the"
    echo "         fallback EFI/BOOT/BOOTX64.EFI path to boot Limine."
    echo ""
    echo "         To register the boot entry manually after booting:"
    echo "           efibootmgr -c -d $OS_DISK -p 1 -L Limine -l '\\\\EFI\\\\limine\\\\BOOTX64.EFI'"
fi

# Determine the disk number for efibootmgr
# The EFI partition is partition 1 on the OS disk
if mountpoint -q "$TARGET/sys/firmware/efi/efivars" 2>/dev/null; then
    chroot "$TARGET" /bin/bash -e << CHROOT_EOF

# Remove any existing Limine entries before creating a new one.
# Without this, each re-run of the script adds a duplicate UEFI boot entry.
efibootmgr | grep 'Limine' \
    | sed 's/Boot\([0-9A-F]*\).*/\1/' \
    | xargs -r -I{} efibootmgr -B -b {}

efibootmgr -c \
    -d "$OS_DISK" \
    -p 1 \
    -L "Limine" \
    -l '\\EFI\\limine\\BOOTX64.EFI'

echo ""
echo "Current UEFI boot entries:"
efibootmgr -v

CHROOT_EOF
else
    echo "Skipping efibootmgr (efivarfs not available — see warning above)."
fi

echo ""
echo "============================================"
echo "  LIMINE BOOTLOADER INSTALLATION COMPLETE"
echo "============================================"
echo ""
echo "IMPORTANT: Before rebooting, make sure:"
echo "  1. Secure Boot is DISABLED in your UEFI firmware"
echo "     (Limine does not support Secure Boot)"
echo "  2. You remember your LUKS passphrase"
echo "  3. Copy the repository scripts and maintenance directories to the"
echo "     installed system — e.g. cp -r $SCRIPT_DIR /mnt/home/<user>/"
echo "     Script 05 optionally installs rootless Podman prerequisites."
echo "     Use the distro network driver; do not blacklist r8169 automatically."
echo ""
echo "To reboot:"
echo "  exit        # if inside chroot"
echo "  umount -R /mnt"
echo "  reboot"
echo ""
echo "After reboot:"
echo "  - You will see a LUKS password prompt → enter your OS disk passphrase"
echo "  - The data disk unlocks after encrypted root is available"
echo "  - Limine will show a boot menu → select Ubuntu"
echo "  - You should boot into your new system!"
echo ""
echo "Next step after successful boot: Run 05-post-boot-setup.sh"
echo ""
