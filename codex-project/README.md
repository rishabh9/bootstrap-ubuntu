# Codex AI Workstation recovery checkpoint

This folder preserves the Codex Project work through 1 November 2026, before any
live boot cleanup or storage migration. It is a continuation snapshot, not a
completed migration or a replacement for the historical bootstrap installer.

**Public copy: machine identifiers are redacted.** `REPLACE_*`, `REDACTED_*`,
`USER`, `WORKSTATION`, and generic project paths replace private values. The
scripts and recovery commands must not be used for migration until their exact
machine values have been restored and independently checked. Keep inspection
reports as historical evidence rather than current machine state.

## Resume here

Read `HANDOVER.md`, then `tools/MIGRATION.md`. The user has confirmed the backup,
Ubuntu recovery USB, and OS passphrase are ready. Neither migration apply stage
has run. The user requested this commit and PR as a recovery checkpoint before
proceeding. Approval to publish this backup is not approval to execute migration.

## Contents

- `HANDOVER.md`: recovered discussion, decisions, findings, stopping point.
- `CONTEXT.md`: original continuation notes; some pre-inspection statements are
  stale and superseded by HANDOVER.md and the reports.
- `original-architecture-request.txt`: user's detailed requirements, redacted.
- `tools/`: both inspection scripts and reports, migration draft, recovery guide,
  and four non-destructive CLI tests.
- `docs/superpowers/plans/`: migration implementation/checkpoint plan.
- `AGENTS.md`: original project file-handling rules, retained as reference.

## Local exact backup

The Codex Project's `recovery-backups/` folder, outside this Git repository,
contains `ai-workstation-full-2026-11-01.tar.gz`, `SHA256SUMS`, a private UUID
redaction map, and a Git bundle of the historical bootstrap repository. The
archive contains the original unredacted scripts, reports, context, plans, user
request, and Git bundle. It does not contain actual LUKS unlock keys or passphrases.

Copy that archive and checksum file to the external backup/recovery USB. They are
currently local files; the PR deliberately does not upload them. The archive has
restrictive permissions but is not itself encrypted: use encrypted external
storage. Verify with `sha256sum -c SHA256SUMS` in its folder.

To inspect an exact restore, extract the archive into a NEW directory, not over
the installed workstation's `/etc` or `/boot`. The Git bundle can reconstruct
the old bootstrap checkout with `git clone bootstrap-ubuntu-before-migration.bundle bootstrap-ubuntu`.

## Validation limits

Bash syntax checks, four non-mutating CLI tests, and an independent static code
review were performed. No disk operation or migration apply mode was executed.
No end-to-end boot or systemd unlocking test has been performed. The public
redaction changes also need their own validation before restoring functionality.

This is a reconstructed handover, not an export of every chat message. The older
ChatGPT conversation's assistant replies were unavailable as text; only its user
preview and saved context were recovered. This snapshot records those limits.
