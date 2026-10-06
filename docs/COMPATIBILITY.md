# Compatibility

## Requirements (hard)
- **chan_sip loaded.** CCSS is implemented for chan_sip (and DAHDI/ISDN) only. It is **not** implemented for PJSIP (Asterisk issue ASTERISK-21453 is still open). On a PJSIP-only system the installer refuses to install.
- `res_ccss` loaded.
- `sip.conf` must `#include sip_general_custom.conf` (standard on Issabel/FreePBX-based systems).
- `callcounter=yes` for reliable SIP busy state (standard in FreePBX-generated `sip_general_additional.conf`; the check warns if missing).
- Asterisk 11+ (uses `cc_callback_sub`; on 1.8 the option does not exist).

## Issabel versions
| Version | Status |
|---|---|
| Issabel 4 (CentOS 7, Asterisk 11-16, chan_sip) | primary target |
| Issabel 5 with chan_sip extensions | supported if chan_sip is loaded |
| Issabel 5 with PJSIP extensions | **not supported** (Asterisk limitation) |

Do not mix drivers for the same extensions; CCSS only sees chan_sip peers.

## Differences between PBX builds
Some builds use `extensions_override_freepbx.conf` instead of `extensions_override_issabelpbx.conf`; the installer detects whichever one `extensions.conf` includes. If `macro-dial-one`/`s-BUSY` is not present, the installer stops:

```bash
asterisk -rx 'dialplan show macro-dial-one'
asterisk -rx 'dialplan show s-BUSY@macro-dial-one'
```

Asterisk 21+ removed `chan_sip` and `Macro()`; this project does not apply there.
