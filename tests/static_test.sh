#!/bin/bash
# Static checks: syntax, template sanity, WAV format, forbidden legacy patterns. No Asterisk needed.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../lib/ccbs-common.sh
source "$ROOT/lib/ccbs-common.sh"
pass(){ echo "PASS: $*"; }
fail(){ echo "FAIL: $*" >&2; exit 1; }

for f in install.sh uninstall.sh lib/ccbs-common.sh scripts/normalize-prompts.sh scripts/rollback.sh \
         usr/local/sbin/issabel-ccbs-check usr/local/sbin/issabel-ccbs-ctl tests/install_test.sh tests/fakebin/asterisk; do
  bash -n "$ROOT/$f" || fail "syntax: $f"
done
pass "shell syntax"

DP="$ROOT/etc/asterisk/ccbs-dialplan.conf.in"; SIP="$ROOT/etc/asterisk/ccbs-sip.conf.in"
grep -q 'CallCompletionRequest()' "$DP"        || fail "CallCompletionRequest missing"
grep -q 'Gosub(ccbs-offer,s,1)' "$DP"          || fail "s-BUSY hook missing"
grep -q 'DB_EXISTS(ccbs/disabled)' "$DP"       || fail "kill switch missing"
grep -q '@PROMPT_ROOT@/offer' "$DP"            || fail "prompt placeholder missing"
grep -q '^cc_agent_policy=generic' "$SIP"      || fail "cc_agent_policy missing in sip template"
grep -q '^cc_monitor_policy=generic' "$SIP"    || fail "cc_monitor_policy missing in sip template"
grep -q '^cc_callback_sub=' "$SIP"             || fail "cc_callback_sub missing"
pass "templates"

# Regression guards for bugs fixed in 1.2.0
if grep -rEn '^[[:space:]]*cc_(agent|monitor)_policy' "$ROOT/etc/asterisk/ccss.conf.example"; then fail "policies must not be in ccss.conf"; fi
if grep -rEn "asterisk -rx '(cc status|cc reload)'|-rx 'cc status'" "$ROOT" --include='*.sh' --include='*.md' --include='issabel-ccbs-*' | grep -v 'static_test.sh'; then fail "non-existent CLI command referenced (use 'cc report status')"; fi
if grep -rEn 'python3?[[:space:]]' "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/lib"; then fail "python dependency reintroduced"; fi
pass "regression guards"

for f in "$ROOT"/sounds/*.wav; do ccbs_wav_ok "$f" || fail "bad WAV format: $f"; done
pass "WAV format (PCM/16-bit/mono/8 kHz)"
for f in busy offer accepted cancelled failed; do test -f "$ROOT/sounds/ccbs-$f.wav" || fail "missing prompt $f"; done
pass "prompt inventory"

[[ "$(tr -d '[:space:]' < "$ROOT/VERSION")" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION format"
grep -q "$(tr -d '[:space:]' < "$ROOT/VERSION")" "$ROOT/CHANGELOG.md" || fail "CHANGELOG lacks current version"
pass "version consistency"
echo "All static tests passed."
