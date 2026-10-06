# Changelog

## 1.2.0 — Correctness & Hardening Release

### Fixed (critical)
- **CC policies were in the wrong file.** `cc_agent_policy` / `cc_monitor_policy` / timers / `cc_callback_sub` were written to `ccss.conf`, where Asterisk ignores them ("should NOT be set in this file"). Every request would have failed with `NOT_GENERIC`. They are now written to `sip_general_custom.conf` (channel-driver config).
- **PJSIP is not supported by CCSS** (only `chan_sip`). Docs claimed PJSIP was fine; the installer now detects PJSIP-only systems and refuses with an explanation.
- **Busy hook no longer replaces Issabel's whole `s-BUSY` branch.** Only priority 1 is taken over via `Gosub`; declining callers (or failed requests) fall through to Issabel's original busy handling (busy tone / voicemail-on-busy).
- **Trunk callers are no longer answered.** CCBS is offered only when the caller's channel is a registered Issabel extension (`require_local_device=1`, default).
- Wrong CLI commands in docs/health-check (`cc status`, `cc reload`) → `cc report status`.
- `issabel-ccbs.conf` was never read. It is now rendered into the dialplan and SIP policies by `install.sh` (prompt root, accept digit, input timeout, timers, …).
- Docs claimed `cc_max_agents=10` applies; Asterisk ignores it for generic agents (one outstanding request per caller). Corrected.
- Installer only worked when started from inside its own directory; it also needed Python 3 (absent on CentOS 7 / Issabel 4). Now location-independent and pure bash/awk.
- Uninstaller/installer only recognised `1.1.0` markers → markers are now version-free and every older marker is cleaned up.
- `rasterisk -rx` fallback was invalid (`rasterisk -x`).

### Added
- `install.sh --check` (read-only pre-flight) and `--force`.
- Pre-flight: chan_sip / res_ccss / `sip_general_custom.conf` include / `s-BUSY` branch / `callcounter` / prompt format / offer-timer vs. prompt length.
- `issabel-ccbs-ctl`: `status | enable | disable | list | cancel | check`. Runtime kill switch via AstDB (`ccbs/disabled`), no reload needed.
- `scripts/rollback.sh` restores the config files saved by the installer.
- AMI `UserEvent(CCBSRequest)` with caller, callee, result and reason for monitoring/integration.
- Experimental opt-in manual cancel feature code (`manual_cancel_enabled=1`).
- Auto-detection of `extensions_override_issabelpbx.conf` vs. `extensions_override_freepbx.conf`.
- Settings validation (no injection of arbitrary text into the dialplan).
- WAV validation in pure bash (no `file` dependency); `normalize-prompts.sh` accepts mp3/flac/ogg, normalises level, detects empty output.
- `tests/install_test.sh`: sandboxed end-to-end installer test (fresh install, upgrade from 1.1, idempotency, validation, PJSIP refusal, uninstall, rollback) using a stub `asterisk`.
- Upgrade cleanup: legacy 1.0/1.1 blocks removed, 1.0-era prompts moved into the backup.

## 1.1.0 — Professional Prompt & Packaging Release
- Prompts moved to `custom/ccbs/fa/`, `normalize-prompts.sh`, WAV validation, health-check, static tests, docs.

## 1.0.0
- First CCBS release for Issabel/Asterisk.
