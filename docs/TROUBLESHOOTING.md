# Troubleshooting

Quick overview: `issabel-ccbs-check` (or `issabel-ccbs-ctl check`).

## `CC_REQUEST_REASON=NOT_GENERIC`
The caller's channel has no generic CC agent policy. Policies must be in the channel-driver config, not in `ccss.conf`:

```bash
grep -n 'cc_agent_policy\|cc_monitor_policy' /etc/asterisk/sip_general_custom.conf
asterisk -rx 'sip reload'
```
Also confirm the caller uses **chan_sip** (not PJSIP). Peers that define their own `cc_agent_policy=never` override the default.

## `NO_CORE_INSTANCE`
The failed call did not create a CCSS core instance: caller is a PJSIP/Local channel, the busy state came from a trunk, or `cc_offer_timer` expired before the digit was pressed (check prompt length vs. `offer_timer`).

## `TOO_MANY_REQUESTS`
Global `cc_max_requests` (default 20 in `ccss.conf`) reached; every busy-offer holds a slot until the offer timer ends. Raise `cc_max_requests` in `/etc/asterisk/ccss.conf` `[general]`, then `module reload res_ccss.so`.

## No prompt / silence
```bash
ls -l /var/lib/asterisk/sounds/custom/ccbs/fa/
issabel-ccbs-check          # validates WAV format
```
Remember `Playback()` paths omit `.wav`.

## Hook not firing
```bash
asterisk -rx 'dialplan show s-BUSY@macro-dial-one'     # priority 1 must be Gosub(ccbs-offer,s,1)
asterisk -rx 'dialplan show macro-dial-one'
```
The caller must be a registered Issabel extension (`database show DEVICE` lists `DEVICE/<ext>/user`). To offer CCBS to everyone set `require_local_device=0` and re-run `install.sh` (not recommended: trunk callers would be answered).

## "Unable to register extension 's-BUSY', priority 1 ... already in use"
Expected: our priority 1 shadows Issabel's original priority 1 on purpose. Harmless.

## After a decline the call just ends
Issabel's original `s-BUSY` had only one priority on your build (the installer warns about this). Open an issue with the output of `dialplan show s-BUSY@macro-dial-one` from before installation (saved as `s-BUSY.before.txt` in the backup directory).

## Callee gets free but nobody is called back
- `callcounter=yes` missing → Asterisk never sees the callee as busy/free.
- Pending requests: `asterisk -rx 'cc report status'`; cancel with `asterisk -rx 'cc cancel <id>'` or `issabel-ccbs-ctl cancel all`.
- Check `ccbs_available_timer` (default 3600 s) has not expired.

## Stop offering CCBS immediately
```bash
issabel-ccbs-ctl disable     # no reload needed
issabel-ccbs-ctl enable
```

## Rollback
```bash
sudo bash /opt/issabel-ccbs/scripts/rollback.sh        # last backup
sudo bash /opt/issabel-ccbs/scripts/rollback.sh /var/backups/issabel-ccbs/<timestamp>
```
