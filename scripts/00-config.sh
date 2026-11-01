#!/usr/bin/env bash
# Sourcing configuration performs no disk probing or mutation.
# Set explicit whole-disk /dev/disk/by-id paths before a FRESH installation.
OS_DISK="${OS_DISK:-}"
DATA_DISK="${DATA_DISK:-}"
ROOT_MAPPER=cryptroot
DATA_MAPPER=cryptdata
TARGET="${TARGET:-/mnt}"
UBUNTU_RELEASE=resolute
UBUNTU_MIRROR=https://archive.ubuntu.com/ubuntu

fail() { echo "ERROR: $*" >&2; exit 1; }
resolve_disks() {
    local disk
    for disk in "$OS_DISK" "$DATA_DISK"; do
        [[ $disk == /dev/disk/by-id/* && $disk != *-part* && -b $disk ]] || fail 'Set OS_DISK and DATA_DISK to explicit whole-disk by-id paths.'
        [[ $(lsblk -dnro TYPE "$disk") == disk ]] || fail 'Expected a whole disk.'
    done
    [[ $(readlink -f "$OS_DISK") != "$(readlink -f "$DATA_DISK")" ]] || fail 'Disks must differ.'
    EFI_PART="${OS_DISK}-part1"
    ROOT_PART="${OS_DISK}-part2"
    DATA_PART="${DATA_DISK}-part1"
}
require_fresh_install() {
    [[ ${FRESH_INSTALL:-} == ERASE_BOTH_DISKS ]] || fail 'Fresh-install scripts require FRESH_INSTALL=ERASE_BOTH_DISKS; NEVER run on the installed workstation.'
    require_root
    [[ -d /run/live || -d /run/casper || -d /cdrom/casper ]] || fail 'Expected a live USB environment.'
    [[ $TARGET == /mnt ]] || fail 'Fresh install target must be /mnt.'
    resolve_disks
    local disk ancestors
    ancestors=$(lsblk -snp -o PATH "$(findmnt -nro SOURCE / | sed 's/\[.*//')" 2>/dev/null || true)
    for disk in "$OS_DISK" "$DATA_DISK"; do
        [[ $ancestors != *"$(readlink -f "$disk")"* ]] || fail 'Selected disk backs running root.'
    done
}
require_target() {
    mountpoint -q "$TARGET" || fail 'Installation target is not mounted.'
    mountpoint -q "$TARGET/boot/efi" || fail 'Target ESP is not mounted.'
    local backing
    backing=$(cryptsetup status "$ROOT_MAPPER" | awk '$1=="device:" {print $2}')
    [[ $(readlink -f "$backing") == "$(readlink -f "$ROOT_PART")" ]] || fail 'Target root mapping does not match configured OS partition.'
    backing=$(cryptsetup status "$DATA_MAPPER" | awk '$1=="device:" {print $2}')
    [[ $(readlink -f "$backing") == "$(readlink -f "$DATA_PART")" ]] || fail 'Data mapping does not match configured data partition.'
    [[ $(readlink -f "$(findmnt -nro SOURCE --target "$TARGET/boot/efi")") == "$(readlink -f "$EFI_PART")" ]] || fail 'Target ESP does not match configured OS partition.'
    [[ $(findmnt -nro SOURCE --target "$TARGET") == /dev/mapper/$ROOT_MAPPER* ]] || fail 'Unexpected target source.'
}
verify_initramfs() {
    local image=$1 listing
    listing=$(lsinitramfs "$image") || fail "Cannot inspect $image"
    [[ $listing == *cryptroot/crypttab* ]] || fail "Root unlock configuration missing: $image"
    [[ $listing != *luks-data-keyfile* && $listing != *luks-incus-keyfile* ]] || fail "Secondary key found: $image"
}
# --- Btrfs subvolume names ---
# These are the subvolumes that will be created on the OS disk.
# Standard layout compatible with Timeshift and Snapper.
SUBVOL_ROOT="@"
SUBVOL_HOME="@home"
SUBVOL_LOG="@log"
SUBVOL_PKG="@pkg"
SUBVOL_SWAP="@swap"

# --- Btrfs mount options ---
# Do NOT add space_cache=v2 or ssd — they are auto-detected on modern kernels.
BTRFS_OPTS="compress=zstd:3,noatime"

# --- Hostname ---
HOSTNAME="workstation"

# --- Timezone ---
# Find your timezone name with: timedatectl list-timezones | grep <City>
TIMEZONE="Europe/London"

# --- Keyboard layout ---
# XKBMODEL: keyboard hardware model. Use "macintosh" for Apple Mac keyboards,
#           "pc105" for a standard PC keyboard.
# XKBLAYOUT: layout code. "gb" = British English, "us" = US English, etc.
# XKBVARIANT: layout variant. Leave empty for the default variant.
# Run "localectl list-x11-keymap-models" / "list-x11-keymap-layouts" for options.
XKBMODEL="macintosh"
XKBLAYOUT="gb"
XKBVARIANT=""
XKBOPTIONS=""

# --- Helper function: confirm before destructive operations ---
confirm_destructive() {
    local msg="$1"
    # Require an interactive terminal — piping "YES" in bypasses the safety review.
    if [[ ! -t 0 ]]; then
        echo "ERROR: This script requires an interactive terminal for destructive confirmations."
        echo "       Do not pipe or redirect stdin to this script."
        exit 1
    fi
    echo ""
    echo "============================================"
    echo "  WARNING: DESTRUCTIVE OPERATION"
    echo "============================================"
    echo ""
    echo "$msg"
    echo ""
    read -rp "Type YES (all caps) to continue: " answer
    if [[ "$answer" != "YES" ]]; then
        echo "Aborted."
        exit 1
    fi
}

# --- Helper function: print a step header ---
step() {
    echo ""
    echo "========================================"
    echo "  STEP: $1"
    echo "========================================"
    echo ""
}

# --- Helper function: check if running as root ---
require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root (use sudo)."
        exit 1
    fi
}
