# Ubuntu 26.04 repository refresh — 1 November 2026

Implements the user's approved repository update after the completed Incus removal.
This is not another migration and does not install changes onto the workstation.

- [x] Replace model-first disk probing with explicit persistent whole-disk IDs.
- [x] Require live environment, root and explicit erase opt-in for scripts 01–04.
- [x] Reject active mappings/mounts, verify target root, data mapping and ESP ancestry.
- [x] Bootstrap resolute using the generic kernel, retain separate Btrfs OS/data.
- [x] Enroll data key only inside encrypted root and reject key-bearing initramfs.
- [x] Configure post-root cryptdata and /data mounting; preserve recovery passphrases.
- [x] Remove Incus/vendor-driver setup; optional Podman prerequisites stay independent.
- [x] Publish complete boot generations before menu references, skip unchanged hooks.
- [x] Rewrite current documentation; flag legacy reviews as historical.
- [x] Validate six bootstrap checks and five historical migration safety checks.
- [x] Independent static review; fix partition timing, backing-device and duplicate-publication findings.
- [ ] Disposable VM fresh-install, reboot and interrupted-update testing.
- [ ] Explicitly reviewed deployment of new maintenance hooks onto the live workstation.

Known limits: free-space checks stop updates rather than pruning old boot generations;
manual retention is required. Previous installed kernel is not guaranteed known-good.
The optional source-built desktop remains a separate choice, not tested on Ubuntu
26.04 by this change. Package/network/GPU behavior must be validated on the target.

Sources: https://ubuntu.com/blog/canonical-releases-ubuntu-26-04-lts-resolute-raccoon
and https://packages.ubuntu.com/search?keywords=linux-generic&suite=resolute.
