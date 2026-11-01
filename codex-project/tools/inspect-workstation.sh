#!/usr/bin/env bash
# Read-only workstation inspection. Writes only the requested report file.
# Never reads key-file contents or executes any bootstrap scripts.
set -u
export LC_ALL=C
umask 077

if [[ ${EUID} -ne 0 ]]; then
    echo "Run with sudo: sudo bash $0 [report-file]" >&2
    exit 1
fi

report=${1:-workstation-report-$(date +%Y%m%d-%H%M%S).txt}
if ! (set -o noclobber; : > "$report") 2>/dev/null; then
    echo "Cannot create report (it may already exist): $report" >&2
    exit 1
fi
exec 3>&1
exec > "$report" 2>&1

section() { printf '\n===== %s =====\n' "$1"; }
run() {
    printf '\n$'; printf ' %q' "$@"; printf '\n'
    if command -v "$1" >/dev/null 2>&1; then
        "$@"
        status=$?
        if (( status != 0 )); then printf '[exit status %s]\n' "$status"; fi
    else
        printf '[command unavailable]\n'
    fi
}

section "Report scope"
printf 'Collected: %s\n' "$(date -Is)"
printf 'Read-only inspection; no package, mount, service, boot or encryption changes.\n'
printf 'Review before sharing: contains disk serials, UUIDs, paths and configuration.\n'

section "Operating system and hardware"
run cat /etc/os-release
run uname -r
run free -h
run lspci -nnk

section "Storage identities and mounts"
run lsblk -e 7 -o NAME,PATH,SIZE,MODEL,SERIAL,TYPE,FSTYPE,UUID,MOUNTPOINTS
run ls -l /dev/disk/by-id/
run findmnt -R /
run cat /etc/fstab
run cat /etc/crypttab
run swapon --show

section "Boot files and firmware entries"
run ls -lh /boot /boot/efi
run efibootmgr -v
section "Initramfs key-inclusion configuration references"
# Search configuration text only, never /etc key files themselves.
run grep -RInE 'luks-incus|KEYFILE_PATTERN|cryptincus|cryptsetup-keys|copy_file.*key' \
    /etc/initramfs-tools /etc/cryptsetup-initramfs /etc/crypttab /etc/fstab

section "Limine configuration and update hooks"
for path in /boot/efi/limine.conf /boot/efi/EFI/limine/limine.conf \
    /boot/efi/EFI/BOOT/limine.conf /etc/kernel/postinst.d/zz-update-limine \
    /etc/kernel/postrm.d/zz-update-limine /etc/initramfs/post-update.d/zz-update-limine; do
    if [[ -f $path ]]; then run cat "$path"; fi
done

section "Initramfs archive filenames (not file contents)"
if command -v lsinitramfs >/dev/null 2>&1; then
    while IFS= read -r -d '' archive; do
        printf '\nArchive: %s\n' "$archive"
        # Stream the entire listing so lsinitramfs can finish normally.
        lsinitramfs "$archive" | awk '
            /luks-incus|cryptroot\/crypttab|cryptsetup-keys|keyfile/ { print; found=1 }
            END { if (!found) print "[No matching filenames; this is not proof of absence of all keys.]" }
        '
        if (( PIPESTATUS[0] != 0 )); then printf '[Archive listing failed]\n'; fi
    done < <(find /boot -type f \( -name 'initrd*' -o -name 'initramfs*' \) -print0)
else
    printf '[lsinitramfs unavailable]\n'
fi

section "Relevant packages and services"
run dpkg-query -W '-f=${binary:Package}\t${Version}\t${db:Status-Abbrev}\n' \
    'incus*' 'podman*' 'docker*' '*rocm*' '*hip*' 'linux-image*' 'linux-headers*'
run systemctl list-unit-files 'incus*' 'ollama*' 'podman*' 'docker*'
run systemctl --no-pager --full status incus.service ollama.service
run ls -l /dev/kfd /dev/dri
run lsmod

section "Incus inspection"
# Avoid socket-activating a stopped daemon solely for this report.
if command -v incus >/dev/null 2>&1 && systemctl is-active --quiet incus.service; then
    run timeout 20 incus version
    run timeout 20 incus list --all-projects
    run timeout 20 incus project list
    run timeout 20 incus storage list
    run timeout 20 incus network list
    printf '\nCustom storage volumes and project-specific resources need a follow-up inventory.\n'
else
    printf '[Incus missing or incus.service inactive; no daemon started.]\n'
fi

section "End of report"
printf 'Inspection complete. No migration performed.\n'
printf 'Report saved to: %s\nReview it before sharing; it includes system identifiers.\n' "$report" >&3
