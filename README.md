:::writing{variant="document" id="58321" title="Issabel CCBS — Call Completion on Busy Subscriber"}

# Issabel CCBS — Call Completion on Busy Subscriber

**Version 1.2.0**

A lightweight **Issabel / Asterisk** addon that enables **CCBS (Call Completion on Busy Subscriber)** for **internal calls**: when the destination extension is busy, the caller is prompted to press `1` to request a callback once the destination becomes available.

> **Exact behavior:** The request is registered **only when****`1`****is pressed**. Otherwise, no CCBS request is registered, and Issabel behaves as before (busy tone / Voicemail).

## ⚠️ Important Prerequisite: chan\_sip

Asterisk CCSS is implemented only for **chan\_sip** (and ISDN/DAHDI); **PJSIP is not supported**. If your extensions use PJSIP, this addon will not work and the installer will not install it. (See `docs/COMPATIBILITY.md` for details.)

## Scenario

```
101 ---> 102 (Busy)
          └─ Persian prompt + "Press 1 for a callback when the subscriber is available"
               ├─ Anything other than 1 → "Request not registered" → normal Issabel behavior (busy tone/Voicemail)
               └─ 1         → CallCompletionRequest()
                                └─ 102 becomes available → Asterisk calls 101
                                      └─ 101 answers → 102 is called → call established
```

Standard Asterisk CCBS does **not** mean an automatic bridge without either phone answering. First, the caller is recalled, and after the caller answers, the destination is called. If a fully automatic bridge is required, a separate AMI/ARI service must be implemented (see `docs/ARCHITECTURE.md`).

## Important Changes from 1.1

- CCSS settings are now written to **`sip_general_custom.conf`**; previous versions placed them in `ccss.conf`, where Asterisk ignores those options.
- The hook only takes **priority 1** from `s-BUSY`; Voicemail-on-busy and the busy tone remain intact.
- The prompt is offered only when the caller is a **registered Issabel internal extension** (Trunk calls are not answered).
- `issabel-ccbs.conf` is actually applied.
- Added `--check` mode, the `issabel-ccbs-ctl` utility, kill-switch, rollback, and installer tests. See `CHANGELOG.md` for the complete list.

## Structure

```
issabel-ccbs/
├── install.sh  uninstall.sh  VERSION  CHANGELOG.md  RELEASE.md  LICENSE
├── lib/ccbs-common.sh                 Shared functions (no Python)
├── etc/asterisk/
│   ├── ccbs-dialplan.conf.in          Dialplan template
│   ├── ccbs-sip.conf.in               CC policy template for chan_sip
│   ├── ccbs-custom.conf.in            Manual cancellation code template (optional)
│   ├── issabel-ccbs.conf.example      Local configuration
│   └── ccss.conf.example              Documentation only (installer does not modify ccss.conf)
├── sounds/ccbs-*.wav   prompts/fa-IR/
├── scripts/normalize-prompts.sh  scripts/rollback.sh
├── usr/local/sbin/issabel-ccbs-check  issabel-ccbs-ctl
├── tests/static_test.sh  tests/install_test.sh  tests/fakebin/asterisk
└── docs/ARCHITECTURE.md COMPATIBILITY.md TEST-PLAN.md TROUBLESHOOTING.md
```

## Prerequisites

- Issabel with root access and Asterisk 11 or later
- `chan_sip` and `res_ccss` modules
- `sip.conf` containing `#include sip_general_custom.conf` (standard in Issabel)
- `callcounter=yes` (standard; the installer will warn if it is missing)
- Bash/awk/coreutils only — **Python is not required**. SoX is required only for converting your own prompts.

## Installation

```
unzip issabel-ccbs-1_2_0.zip && cd issabel-ccbs
sudo bash install.sh --check     # Check only; makes no changes
sudo bash install.sh
```

The installer performs: preflight checks (chan_sip, res_ccss, includes, presence of `s-BUSY`, prompt format, timing) → Backup → cleanup of old 1.0/1.1 blocks → template rendering based on configuration → prompt installation → `sip reload` and `dialplan reload` → verification → health check.

Re-running the installer is safe. Invalid configuration or a PJSIP-only setup causes the installation to stop without modifying any files.

## Modified Files

| File | Contents |
| --- | --- |
| `/etc/asterisk/sip_general_custom.conf` | Managed block: `cc_agent_policy=generic`, `cc_monitor_policy=generic`, timers, `cc_callback_sub` |
| `/etc/asterisk/extensions_override_issabelpbx.conf` (or `..._freepbx.conf`) | Hook on `s-BUSY`, `ccbs-offer` context, `ccbs-callback` |
| `/etc/asterisk/extensions_custom.conf` | Only if `manual_cancel_enabled=1` |
| `/var/lib/asterisk/sounds/custom/ccbs/fa/` | `busy`, `offer`, `accepted`, `cancelled`, `failed` |
| `/opt/issabel-ccbs/`, `/usr/local/sbin/issabel-ccbs-{check,ctl}` | Utilities |
| `/var/backups/issabel-ccbs/<timestamp>/` | Backup + `s-BUSY.before.txt` |

Blocks are marked with `; ===== ISSABEL-CCBS BEGIN/END =====`. **Do not manually edit anything inside these blocks.**

## Configuration

Edit `/etc/asterisk/issabel-ccbs.conf` and then run `install.sh` again.

```
[general]
prompt_root=custom/ccbs/fa     ; Prompt path relative to /var/lib/asterisk/sounds
accept_digit=1
input_timeout=7
require_local_device=1         ; Offer only to registered internal extensions
offer_timer=30                 ; Must be longer than (busy+offer+input_timeout)
ccbs_available_timer=3600
ccnr_available_timer=3600
cc_recall_timer=20
cc_max_monitors=5
manual_cancel_enabled=0        ; Experimental
manual_cancel_code=*31
```

## Day-to-Day Management

```
issabel-ccbs-ctl status        # Enabled/disabled + pending requests
issabel-ccbs-ctl disable       # Immediately stop offering CCBS (without reload)
issabel-ccbs-ctl enable
issabel-ccbs-ctl list          # = asterisk -rx 'cc report status'
issabel-ccbs-ctl cancel all    # Or specify an ID
issabel-ccbs-check             # Full health check; exit code = number of FAILs
```

For monitoring, an AMI event named `CCBSRequest` is sent for every request, containing `Caller / Callee / Result / Reason`.

## Persian Prompts

Five prompts (`busy`, `offer`, `accepted`, `cancelled`, `failed`) have their text defined in `prompts/fa-IR/prompts.txt`.

For production quality, record them using a professional voice artist and convert them with `scripts/normalize-prompts.sh` (SoX) to WAV PCM 16-bit / mono / 8 kHz. See `prompts/fa-IR/README.md` for details.

## Testing

```
bash tests/static_test.sh      # Syntax, templates, WAV format, regression checks
bash tests/install_test.sh     # Install/upgrade/idempotency/uninstall in a sandbox with stubs
```

These tests do **not** simulate a real Asterisk instance or physical phones. Perform practical staging tests according to `docs/TEST-PLAN.md`.

## Uninstallation and Rollback

```
sudo bash uninstall.sh                          # Removes all blocks, prompts, and utilities; backups and issabel-ccbs.conf are retained
sudo bash scripts/rollback.sh [BACKUP_DIR]      # Restores configuration files from the selected backup
```

## Limitations

- **chan\_sip only**, internal extensions only (generic agent/monitor). Each caller can have only one active request.
- Requests are stored only in Asterisk memory and are lost after a restart.
- Recall is made directly to the device (`SIP/101`), so Issabel features such as Follow-Me are not applied to this path.
- The exact structure of `macro-dial-one` varies between Issabel versions. The installer saves the previous state in `s-BUSY.before.txt` and warns if it does not match the expected structure.
- Asterisk 21+ no longer includes chan\_sip or Macro; this project is not applicable there.

## License

This project is licensed under the MIT license. See the [LICENSE](LICENSE) file for the full license text.
