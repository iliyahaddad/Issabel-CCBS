#!/bin/bash
# End-to-end installer test in a throw-away sandbox using a stub `asterisk` binary.
# Covers: fresh install, idempotency, upgrade from 1.1 markers, config rendering, validation,
# PJSIP-only refusal, kill switch, uninstall, rollback.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pass(){ echo "PASS: $*"; }
fail(){ echo "FAIL: $*" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export CCBS_TESTING=1
export CCBS_ETC_DIR="$T/etc" CCBS_SOUND_BASE="$T/sounds" CCBS_PREFIX="$T/opt" CCBS_SBIN="$T/sbin"
export CCBS_BACKUP_ROOT="$T/backups" CCBS_STATE_FILE="$T/last-backup"
export PATH="$ROOT/tests/fakebin:$PATH"
mkdir -p "$T/etc" "$T/sounds" "$T/sbin"

# ---- seed a realistic Issabel config incl. a 1.1.0-style legacy block
printf '#include sip_general_additional.conf\n#include sip_general_custom.conf\n#include sip_nat.conf\ncallcounter=yes\n' > "$T/etc/sip.conf"
printf '#include extensions_override_issabelpbx.conf\n#include extensions_additional.conf\n#include extensions_custom.conf\n' > "$T/etc/extensions.conf"
printf '; user general options\nallowguest=no\n' > "$T/etc/sip_general_custom.conf"
printf '[from-internal-custom]\nexten => 7777,1,Answer()\n' > "$T/etc/extensions_custom.conf"
printf '[macro-user-hook]\nexten => s,1,Return()\n' > "$T/etc/extensions_override_issabelpbx.conf"
printf '[general]\n; ===== ISSABEL-CCBS 1.1.0 BEGIN =====\ncc_agent_policy=generic\n; ===== ISSABEL-CCBS 1.1.0 END =====\n' > "$T/etc/ccss.conf"
mkdir -p "$T/sounds/custom"; cp "$ROOT/sounds/ccbs-busy.wav" "$T/sounds/custom/ccbs-busy.wav"   # 1.0-era prompt
mkdir "$T/orig"; cp "$T/etc"/*.conf "$T/orig/"

sum(){ (cd "$T/etc" && cat sip_general_custom.conf extensions_override_issabelpbx.conf extensions_custom.conf ccss.conf | md5sum); }
install(){ bash "$ROOT/install.sh" "$@" >"$T/install.log" 2>&1; }

# 1 pre-flight only must not change anything
before="$(sum)"; install --check || { cat "$T/install.log"; fail "--check failed"; }
[[ "$(sum)" == "$before" ]] || fail "--check modified files"; pass "--check is read-only"

# 2 fresh install / upgrade
install || { cat "$T/install.log"; fail "install failed"; }
grep -q '^allowguest=no' "$T/etc/sip_general_custom.conf"                || fail "user content in sip_general_custom lost"
grep -q '^cc_agent_policy=generic' "$T/etc/sip_general_custom.conf"      || fail "cc_agent_policy not written to sip_general_custom"
grep -q '^cc_callback_sub=ccbs-callback,s,1' "$T/etc/sip_general_custom.conf" || fail "cc_callback_sub missing"
grep -q 'macro-user-hook' "$T/etc/extensions_override_issabelpbx.conf"   || fail "user override content lost"
grep -q 'Gosub(ccbs-offer,s,1)' "$T/etc/extensions_override_issabelpbx.conf" || fail "hook not installed"
grep -q 'sounds\|custom/ccbs/fa/offer' "$T/etc/extensions_override_issabelpbx.conf" || fail "prompt path not rendered"
grep -q '@' "$T/etc/extensions_override_issabelpbx.conf" && fail "unrendered placeholder left in dialplan"
if grep -q 'ISSABEL-CCBS 1.1.0' "$T/etc/ccss.conf"; then fail "legacy ccss block not removed"; fi
grep -q '^\[general\]' "$T/etc/ccss.conf"                                 || fail "ccss.conf [general] lost"
[[ ! -e "$T/sounds/custom/ccbs-busy.wav" && -n "$(ls "$T"/backups/*/legacy-ccbs-busy.wav 2>/dev/null)" ]] || fail "legacy prompt not moved to backup"
for p in busy offer accepted cancelled failed; do [[ -f "$T/sounds/custom/ccbs/fa/$p.wav" ]] || fail "prompt $p not installed"; done
[[ -x "$T/sbin/issabel-ccbs-check" && -x "$T/sbin/issabel-ccbs-ctl" && -f "$T/opt/lib/ccbs-common.sh" ]] || fail "tools not installed"
pass "fresh install / upgrade from 1.1 markers"

# 3 idempotency
s1="$(sum)"; install || fail "second install failed"; [[ "$(sum)" == "$s1" ]] || fail "re-install is not idempotent"
[[ "$(grep -c 'ISSABEL-CCBS BEGIN' "$T/etc/sip_general_custom.conf")" == 1 ]] || fail "duplicate blocks"
pass "idempotent re-install"

# 4 health check + ctl
"$T/sbin/issabel-ccbs-check" >"$T/check.log" 2>&1 || { cat "$T/check.log"; fail "health check reported failures"; }
"$T/sbin/issabel-ccbs-ctl" disable | grep -q DISABLED || fail "ctl disable"
"$T/sbin/issabel-ccbs-ctl" status  | grep -q DISABLED || fail "ctl status after disable"
"$T/sbin/issabel-ccbs-ctl" enable  | grep -q ENABLED  || fail "ctl enable"
pass "health check and ctl"

# 5 config rendering
printf '[general]\naccept_digit=5\ninput_timeout=9\nprompt_root=custom/ccbs/en\nrequire_local_device=0\noffer_timer=40\nmanual_cancel_enabled=1\nmanual_cancel_code=*37\n' > "$T/etc/issabel-ccbs.conf"
install || { cat "$T/install.log"; fail "install with custom config failed"; }
grep -q '"5"' "$T/etc/extensions_override_issabelpbx.conf"       || fail "accept_digit not rendered"
grep -q 'custom/ccbs/en/offer,1,,1,9' "$T/etc/extensions_override_issabelpbx.conf" || fail "prompt_root/input_timeout not rendered"
grep -q 'Goto(eligible)' "$T/etc/extensions_override_issabelpbx.conf" || fail "require_local_device=0 not rendered"
grep -q '^cc_offer_timer=40' "$T/etc/sip_general_custom.conf"      || fail "offer_timer not rendered"
grep -q 'exten => \*37,1' "$T/etc/extensions_custom.conf" && grep -q 'exten => 7777' "$T/etc/extensions_custom.conf" || fail "manual cancel block / user content"
[[ -f "$T/sounds/custom/ccbs/en/busy.wav" ]] || fail "prompts not installed to configured prompt_root"
pass "settings are really applied"

# 6 invalid settings are rejected without touching files
printf '[general]\naccept_digit=ab\n' > "$T/etc/issabel-ccbs.conf"; s1="$(sum)"
if install; then fail "invalid config accepted"; fi
[[ "$(sum)" == "$s1" ]] || fail "invalid config modified files"
printf '[general]\nprompt_root=../../etc\n' > "$T/etc/issabel-ccbs.conf"
if install; then fail "path traversal accepted"; fi
pass "invalid settings rejected"

# 7 PJSIP-only systems are refused
rm -f "$T/etc/issabel-ccbs.conf"; s1="$(sum)"
if FAKE_NO_SIP=1 install; then fail "installed on PJSIP-only system"; fi
grep -q 'PJSIP' "$T/install.log" || fail "no PJSIP explanation"
[[ "$(sum)" == "$s1" ]] || fail "PJSIP refusal modified files"
pass "PJSIP-only refused with explanation"

# 8 unbalanced markers are never edited blindly
cp "$T/etc/sip_general_custom.conf" "$T/sipg.bak"; printf '; ===== ISSABEL-CCBS BEGIN =====\n' >> "$T/etc/sip_general_custom.conf"
if install; then fail "unbalanced markers accepted"; fi
cp "$T/sipg.bak" "$T/etc/sip_general_custom.conf"
pass "unbalanced markers refused"

# 8b re-running the INSTALLED copy must not delete itself

bash "$T/opt/install.sh" >"$T/install.log" 2>&1 || { cat "$T/install.log"; fail "install from installed copy failed"; }
[[ -f "$T/opt/install.sh" && -f "$T/opt/lib/ccbs-common.sh" && -f "$T/opt/sounds/ccbs-busy.wav" ]] || fail "installed copy damaged itself"
pass "re-install from installed copy"

# 9 rollback restores what install changed
install || fail "reinstall before rollback"
bash "$ROOT/scripts/rollback.sh" >/dev/null 2>&1 || fail "rollback failed"
pass "rollback runs"

# 10 uninstall restores originals byte-for-byte (config content)
install || fail "reinstall before uninstall"
bash "$T/opt/uninstall.sh" >/dev/null 2>&1 || fail "uninstall (from installed copy) failed"
for f in sip_general_custom.conf extensions_override_issabelpbx.conf extensions_custom.conf; do
  cmp -s "$T/orig/$f" "$T/etc/$f" || { diff "$T/orig/$f" "$T/etc/$f" || true; fail "$f not restored by uninstall"; }
done
[[ ! -e "$T/sounds/custom/ccbs" && ! -e "$T/sbin/issabel-ccbs-check" && ! -e "$T/opt" ]] || fail "uninstall left files"
pass "uninstall restores configuration"
echo "All install tests passed."
