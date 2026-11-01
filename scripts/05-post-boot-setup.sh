#!/usr/bin/env bash
# Optional installed-system package setup. No disk or boot configuration writes.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/00-config.sh"
require_root
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 26.04 ]] || fail 'Expected installed Ubuntu 26.04.'
[[ ! -d /run/casper && ! -d /run/live ]] || fail 'Do not run from the live installer.'
mountpoint -q /data || fail '/data must be mounted before service setup.'
apt-get update
apt-get install podman uidmap slirp4netns fuse-overlayfs
echo 'Run podman info as your NORMAL user to verify rootless mode.'
echo 'No rootful API socket, linger, service or GPU stack was enabled.'
echo 'Use per-user Quadlets only when needed; require /data mounts explicitly.'
echo 'Preserve working distro amdgpu/r8169 drivers and existing inference software.'
