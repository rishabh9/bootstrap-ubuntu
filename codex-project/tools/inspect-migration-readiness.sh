#!/usr/bin/env bash
# Read-only follow-up inspection; writes only a new report.
set -u
export LC_ALL=C
umask 077
if (( EUID != 0 )); then
    echo "Run: sudo bash $0 [report-file]" >&2
    exit 1
fi
report=${1:-migration-readiness-$(date +%Y%m%d-%H%M%S).txt}
if ! (set -o noclobber; : > "$report") 2>/dev/null; then
    echo "Cannot create report: $report" >&2
    exit 1
fi
exec 3>&1
exec > "$report" 2>&1
section() { printf '\n===== %s =====\n' "$1"; }
run() {
    printf '\n$'; printf ' %q' "$@"; printf '\n'
    if command -v "$1" >/dev/null 2>&1; then
        timeout 45 "$@"
        code=$?
        if (( code != 0 )); then printf '[exit status %s]\n' "$code"; fi
    else
        echo '[command unavailable]'
    fi
}
section "Scope"
date -Is
echo 'No migration performed. Review paths, network addresses and identifiers before sharing.'
section "Current storage identity and health"
run lsblk -e 7 -o NAME,PATH,SIZE,MODEL,SERIAL,TYPE,FSTYPE,UUID,MOUNTPOINTS
run df -hT / /boot/efi /var/lib/incus/storage-pools/incus-pool
run btrfs device stats /
run btrfs device stats /var/lib/incus/storage-pools/incus-pool
run cryptsetup status cryptroot
run cryptsetup status cryptincus
run cryptsetup luksDump /dev/disk/by-id/nvme-CT2000P310SSD8_REPLACE_P310_SERIAL-part2
run cryptsetup luksDump /dev/disk/by-id/nvme-CT2000P510SSD8_REPLACE_P510_SERIAL-part1

section "Kernel identities and exact boot-file matches"
run uname -r
shopt -s nullglob
for image in /boot/vmlinuz-* /boot/efi/vmlinuz /boot/efi/vmlinuz.old; do
    [[ -f $image ]] && run file "$image"
done
for image in /boot/vmlinuz-* /boot/initrd.img-* /boot/efi/vmlinuz /boot/efi/vmlinuz.old /boot/efi/initrd.img /boot/efi/initrd.img.old; do
    [[ -f $image ]] && run sha256sum "$image"
done
section "Initramfs embedded module versions (filenames only)"
if command -v lsinitramfs >/dev/null 2>&1; then
    for image in /boot/efi/initrd.img /boot/efi/initrd.img.old; do
        [[ -f $image ]] || continue
        printf '\nArchive: %s\n' "$image"
        timeout 45 lsinitramfs "$image" | awk '
          /(^|\/)lib\/modules\// {
            p=$0; sub(/^.*lib\/modules\//,"",p); sub(/\/.*/,"",p)
            if (p != "" && !seen[p]++) print p
          }'
    done
fi

section "Incus resources (existing running daemon only)"
if command -v incus >/dev/null 2>&1 && systemctl is-active --quiet incus.service; then
    run incus list --all-projects
    run incus project list
    run incus storage show incus-pool
    run incus storage volume list incus-pool --project default
    run incus profile list --project default
    run incus profile show default --project default
    run incus config device show rocm --project default
    run incus network show incusbr0 --project default
    run incus image list --project default
else
    echo '[Incus unavailable or stopped; not started for inspection]'
fi

section "Existing inference and container services"
run snap list
run snap services
run systemctl list-units --all --no-pager 'snap.lemonade*' 'ollama*' 'podman*' 'docker*'
run ss -lntup
run ls -l /run/podman/podman.sock
run ls -ld /var/lib/containers/storage /etc/containers/systemd
section "GPU tools"
run ls -l /dev/kfd /dev/dri
run sh -c 'command -v rocminfo; command -v vulkaninfo; command -v ollama; command -v lemonade-server; command -v llama-server'

section "Invoking user's container configuration"
invoking_user=${SUDO_USER:-}
if [[ -n $invoking_user && $invoking_user != root ]]; then
    invoking_uid=$(id -u "$invoking_user")
    invoking_home=$(getent passwd "$invoking_user" | cut -d: -f6)
    run id "$invoking_user"
    run loginctl show-user "$invoking_user" -p Linger -p State
    run ls -ld "$invoking_home/.local/share/containers/storage" "$invoking_home/.config/containers/systemd"
    # Listing existing state avoids initializing Podman storage via podman info/ps.
    if [[ -d /run/user/$invoking_uid ]]; then
        run runuser -u "$invoking_user" -- env XDG_RUNTIME_DIR="/run/user/$invoking_uid" \
            systemctl --user list-units --all --no-pager --type=service
    fi
else
    echo '[Run through sudo from your normal account to inspect user services.]'
fi
section "APT removal preview — simulation only"
run apt-get --simulate remove incus incus-base incus-client incus-ui-canonical
section "End"
echo 'No services stopped, no key contents read, no configuration changed.'
printf 'Report saved to: %s\nReview before sharing.\n' "$report" >&3
