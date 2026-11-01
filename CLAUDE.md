# Repository guidance

Read README.md for the current Ubuntu 26.04 architecture. Scripts 01–04 are fresh
installation tools, not installed-system maintenance. Never run them on the user's
workstation. Use explicit persistent disk identifiers; preserve the P310 for any
future migration. The completed migration history is in codex-project/HANDOVER.md.

The P510 is encrypted Btrfs /data, not Incus storage. Never embed its unlock key
in initramfs or copy raw recovery keys into the repository. Root unlock precedes
systemd data unlock. The ESP is unencrypted. Source configuration must not probe
or mutate disks. No mandatory vendor network driver or GPU stack installation.

maintenance/update-limine is a fresh-install asset; repository updates do not
imply approval to install it on the running workstation. It retains complete
version generations and publishes menu references only after files are staged.

Run the tests and Bash syntax checks documented in README. Report limits honestly:
script syntax/guard tests do not establish bootability. Preserve the redacted
historical recovery snapshot; do not re-enable or rerun the public migration copy.
