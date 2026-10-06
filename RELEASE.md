حتماً. این نسخه برای یک فایل `RELEASE.md` طبیعی و حرفه‌ای است:

# Issabel CCBS 1.2.0 Release

## Purpose

Version 1.2 is a **fix and hardening release**. It addresses the most important issues from previous versions, including the incorrect CCSS configuration location, the misleading claim of PJSIP support, complete replacement of the Busy branch, and answering Trunk calls.

## Before Upgrading

1. Create a full backup of `/etc/asterisk` (the installer also creates an automatic backup).
2. Run `sudo bash install.sh --check`; this performs checks only and makes no changes.
3. The system must have **chan\_sip**. On PJSIP-only systems, CCSS is not implemented in Asterisk.

## Upgrading from 1.0 / 1.1

The installer removes the old blocks, writes the settings to `sip_general_custom.conf`, replaces the hook, and moves the old prompts to the backup.

Re-running `install.sh` is safe and **idempotent**.

## Recommended Before Production

1. Test Busy / Accept / Decline / Cancel using two test extensions (`docs/TEST-PLAN.md`).
2. `issabel-ccbs-check` should complete with no FAILs.
3. If any problems occur, use `issabel-ccbs-ctl disable` for an immediate kill-switch without a reload, or run `scripts/rollback.sh`.

## Limitations

- A real end-to-end test with SIP phones could not be performed in the build environment. Static tests and installer tests in a sandbox (using an Asterisk stub) have been completed. The actual CCSS behavior and the `macro-dial-one` structure on your Issabel system must be verified in staging.
- **chan\_sip only**, internal extensions only (generic agent/monitor).

