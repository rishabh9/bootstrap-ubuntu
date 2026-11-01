# Incus Migration Implementation Plan

> Historical document: migration subsequently completed. Read the final checkpoint in HANDOVER.md (at the codex-project root) before taking action. Do not rerun the migration.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare a reviewable, machine-specific migration without executing it.

**Architecture:** Two explicit interactive stages separate key-free boot validation
from secondary-disk destruction. Persistent identities and observed UUIDs are
pinned; a reboot checkpoint separates the stages.

**Tech Stack:** Bash, cryptsetup, initramfs-tools, Btrfs, Incus, systemd.

**Spec:** User's pasted architecture request and approved staged approach in chat;
operational detail in `tools/MIGRATION.md`.

## Global Constraints

- Preserve P310 partitions, root encryption, Limine binary, installed AI software.
- Do not run original bootstrap scripts or apply modes in the authoring environment.
- User approval is required before boot/encryption changes or destructive actions.
- P510 contents are disposable; external backup, USB and OS passphrase confirmed.

## Review Focus

- Missing or swapped hardware: pinned identifiers, UUIDs and root ancestry must reject it.
- Key exposure: both retained images must omit the known secondary-key filenames.
- Early dependency: unpacked initramfs crypttab must not depend on the retired disk.
- Partial failure: preserve backups and refuse automatic data-stage reruns.
- New runtime state: unexpected instances/volumes must stop migration.

## Tasks

- [x] Write and observe failing non-destructive CLI safety tests in `tools/test-migration-safety.py`.
- [x] Create `tools/migrate-workstation.sh` with default plan output, terminal guards,
  pinned hardware checks, staged boot cleanup and P510 recreation.
- [x] Create `tools/MIGRATION.md` with review steps, validation and recovery.
- [x] Run Bash syntax and CLI tests without invoking apply operations.
- [ ] Obtain approval of the concrete script before any apply command.
- [ ] Run approved boot stage on workstation; reboot and review evidence.
- [ ] Run approved data stage; reboot, validate and secure new header backup.
- [ ] Update bootstrap repository and long-term Limine maintenance after validation.

The runtime failure cases require real-machine checkpoints and have not been
validated end-to-end by the CLI tests. No success claim extends to live migration.
