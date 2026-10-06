#!/bin/bash
# Issabel CCBS installer.  Usage: install.sh [--check] [--force] [--help]
set -Eeuo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ccbs-common.sh
source "$SRC/lib/ccbs-common.sh"
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"

MODE=install; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) MODE=check ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2p' "$0"; echo "  --check  run pre-flight checks only, change nothing"; echo "  --force  continue despite failed pre-flight checks"; exit 0 ;;
    *) ccbs_die "Unknown option: $arg" ;;
  esac
done

ccbs_require_root
ccbs_find_asterisk || ccbs_die "Asterisk CLI not found."

BACKUP_DIR=""
trap 'rc=$?; echo "[issabel-ccbs] ERROR: failed at line $LINENO (exit $rc).${BACKUP_DIR:+ Backup: $BACKUP_DIR (restore with scripts/rollback.sh)}" >&2' ERR

FAILS=0; WARNS=0
pf_ok()   { ccbs_log "OK    $*"; }
pf_warn() { WARNS=$((WARNS + 1)); ccbs_log "WARN  $*"; }
pf_fail() { FAILS=$((FAILS + 1)); ccbs_log "FAIL  $*"; }

# ------------------------------------------------------------------ settings
PROMPT_ROOT="$(ccbs_cfg prompt_root custom/ccbs/fa)"
ACCEPT_DIGIT="$(ccbs_cfg accept_digit 1)"
INPUT_TIMEOUT="$(ccbs_cfg input_timeout 7)"
REQUIRE_LOCAL="$(ccbs_cfg require_local_device 1)"
OFFER_TIMER="$(ccbs_cfg offer_timer 30)"
CCBS_AVAIL="$(ccbs_cfg ccbs_available_timer 3600)"
CCNR_AVAIL="$(ccbs_cfg ccnr_available_timer 3600)"
RECALL_TIMER="$(ccbs_cfg cc_recall_timer 20)"
MAX_MONITORS="$(ccbs_cfg cc_max_monitors 5)"
MANUAL_CANCEL="$(ccbs_cfg manual_cancel_enabled 0)"
CANCEL_CODE="$(ccbs_cfg manual_cancel_code '*31')"

num_in() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= $2 && $1 <= $3 )); }
validate_config() {
  local bad=0
  [[ "$PROMPT_ROOT" =~ ^[A-Za-z0-9_][A-Za-z0-9_/.-]*$ && "$PROMPT_ROOT" != *..* ]] || { pf_fail "prompt_root '$PROMPT_ROOT' is invalid"; bad=1; }
  [[ "$ACCEPT_DIGIT" =~ ^[0-9*#]$ ]]           || { pf_fail "accept_digit must be one of 0-9 * #"; bad=1; }
  num_in "$INPUT_TIMEOUT" 1 60                 || { pf_fail "input_timeout must be 1-60"; bad=1; }
  num_in "$OFFER_TIMER" 5 600                  || { pf_fail "offer_timer must be 5-600"; bad=1; }
  num_in "$CCBS_AVAIL" 1 86400                 || { pf_fail "ccbs_available_timer must be 1-86400"; bad=1; }
  num_in "$CCNR_AVAIL" 1 86400                 || { pf_fail "ccnr_available_timer must be 1-86400"; bad=1; }
  num_in "$RECALL_TIMER" 5 120                 || { pf_fail "cc_recall_timer must be 5-120"; bad=1; }
  num_in "$MAX_MONITORS" 1 100                 || { pf_fail "cc_max_monitors must be 1-100"; bad=1; }
  [[ "$REQUIRE_LOCAL" =~ ^[01]$ ]]             || { pf_fail "require_local_device must be 0 or 1"; bad=1; }
  [[ "$MANUAL_CANCEL" =~ ^[01]$ ]]             || { pf_fail "manual_cancel_enabled must be 0 or 1"; bad=1; }
  [[ "$CANCEL_CODE" =~ ^[*#0-9]{2,8}$ ]]       || { pf_fail "manual_cancel_code must be 2-8 chars of 0-9 * #"; bad=1; }
  (( bad == 0 )) && pf_ok "settings validated (${CCBS_CONFIG})"
  return 0
}

# ---------------------------------------------------------------- pre-flight
SIP_GENERAL="$CCBS_ETC/sip_general_custom.conf"
CUSTOM="$CCBS_ETC/extensions_custom.conf"
OVERRIDE_NAME="extensions_override_issabelpbx.conf"
for cand in extensions_override_issabelpbx.conf extensions_override_freepbx.conf; do
  if [[ -f "$CCBS_ETC/extensions.conf" ]] && grep -Eq "^[[:space:]]*#include[[:space:]]+\"?${cand//./\\.}" "$CCBS_ETC/extensions.conf"; then
    OVERRIDE_NAME="$cand"; break
  fi
done
OVERRIDE="$CCBS_ETC/$OVERRIDE_NAME"
SOUND_DIR="$CCBS_SOUND_BASE/$PROMPT_ROOT"

preflight() {
  ccbs_log "Issabel CCBS $VERSION - pre-flight"
  local issabel_ver ast_ver
  issabel_ver="$(rpm -q --qf '%{VERSION}-%{RELEASE}' issabel-release 2>/dev/null || true)"
  ast_ver="$(ast 'core show version' | head -n 1)"
  [[ -n "$ast_ver" ]] || { pf_fail "Asterisk is not running / CLI not reachable"; return; }
  pf_ok "Asterisk: $ast_ver | Issabel: ${issabel_ver:-unknown}"

  validate_config

  if ast_has 'module show like chan_sip' 'chan_sip'; then pf_ok "chan_sip is loaded"
  else pf_fail "chan_sip is not loaded. CCSS is NOT implemented for PJSIP, so CCBS cannot work on PJSIP-only systems."; fi

  if ast_has 'module show like res_ccss' 'res_ccss'; then pf_ok "res_ccss is loaded"
  else pf_fail "res_ccss is not loaded (load it in modules.conf)."; fi

  if [[ -f "$CCBS_ETC/sip.conf" ]] && grep -Eq '^[[:space:]]*#include[[:space:]]+"?sip_general_custom\.conf' "$CCBS_ETC/sip.conf"; then
    pf_ok "sip.conf includes sip_general_custom.conf"
  else pf_fail "sip.conf does not #include sip_general_custom.conf - cannot place CC policies"; fi

  if [[ -f "$CCBS_ETC/extensions.conf" ]] && grep -Eq "^[[:space:]]*#include[[:space:]]+\"?${OVERRIDE_NAME//./\\.}" "$CCBS_ETC/extensions.conf"; then
    pf_ok "dialplan override file: $OVERRIDE_NAME"
  else pf_warn "extensions.conf does not #include $OVERRIDE_NAME; the hook may not load"; fi

  local bsy; bsy="$(ast 'dialplan show macro-dial-one')"
  if [[ "$bsy" == *"s-BUSY"* ]]; then
    pf_ok "macro-dial-one has an s-BUSY branch"
    if ! grep -q 'ISSABEL-CCBS' "$OVERRIDE" 2>/dev/null; then
      local n; n="$(ast 'dialplan show s-BUSY@macro-dial-one' | grep -cE "^[[:space:]]*('[^']*'[[:space:]]*=>)?[[:space:]]*[0-9]+\\.[[:space:]]" || true)"
      if (( n >= 2 )); then pf_ok "original s-BUSY has $n priorities (fall-through to original handling will work)"
      else pf_warn "original s-BUSY has only $n priority: after a caller declines, the call will simply end instead of continuing to Issabel's busy handling"; fi
    fi
  else pf_fail "macro-dial-one / s-BUSY not found - this Issabel version uses a different Busy path"; fi

  if grep -rEqs '^[[:space:]]*callcounter[[:space:]]*=[[:space:]]*yes' "$CCBS_ETC"/sip*.conf; then pf_ok "callcounter=yes (needed for SIP busy device-state)"
  else pf_warn "callcounter=yes not found in sip*.conf; generic CC cannot see busy/free state without it"; fi

  local f missing=0 secs total=0
  for f in busy offer accepted cancelled failed; do
    if [[ ! -f "$SRC/sounds/ccbs-$f.wav" ]]; then pf_fail "missing prompt sounds/ccbs-$f.wav"; missing=1
    elif ! ccbs_wav_ok "$SRC/sounds/ccbs-$f.wav"; then pf_fail "sounds/ccbs-$f.wav is not PCM 16-bit mono 8 kHz WAV"; missing=1
    elif [[ "$f" == busy || "$f" == offer ]]; then secs="$(ccbs_wav_seconds "$SRC/sounds/ccbs-$f.wav")"; total=$((total + secs)); fi
  done
  if (( missing == 0 )); then
    pf_ok "prompt files valid"
    if num_in "$OFFER_TIMER" 5 600 && num_in "$INPUT_TIMEOUT" 1 60 && (( OFFER_TIMER < total + INPUT_TIMEOUT )); then
      pf_warn "offer_timer (${OFFER_TIMER}s) < busy+offer prompts (${total}s) + input_timeout (${INPUT_TIMEOUT}s): the offer may expire before the caller can answer"
    fi
  fi
}

preflight
if (( FAILS > 0 )); then
  ccbs_log "Pre-flight: $FAILS failure(s), $WARNS warning(s)."
  if [[ "$MODE" == check ]]; then exit 1; fi
  (( FORCE == 1 )) || ccbs_die "Pre-flight failed. Fix the issues above (or use --force at your own risk)."
  ccbs_warn "--force given: continuing despite failures."
fi
if [[ "$MODE" == check ]]; then ccbs_log "Pre-flight passed ($WARNS warning(s)). Nothing was changed."; exit 0; fi

# -------------------------------------------------------------------- backup
BACKUP_DIR="$CCBS_BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR" "$SOUND_DIR" "$CCBS_PREFIX"
for f in "$SIP_GENERAL" "$OVERRIDE" "$CUSTOM" "$CCBS_ETC/ccss.conf" "$CCBS_CONFIG"; do
  if [[ -e "$f" ]]; then cp -a "$f" "$BACKUP_DIR/$(basename "$f")"; fi
done
ast 'dialplan show s-BUSY@macro-dial-one' > "$BACKUP_DIR/s-BUSY.before.txt"
: > "$BACKUP_DIR/created.list"
echo "$CCBS_ETC" > "$BACKUP_DIR/etc-dir"
ccbs_log "Backup: $BACKUP_DIR"

[[ -f "$CCBS_CONFIG" ]] || { cp -f "$SRC/etc/asterisk/issabel-ccbs.conf.example" "$CCBS_CONFIG"; echo "$CCBS_CONFIG" >> "$BACKUP_DIR/created.list"; ccbs_own_new "$CCBS_CONFIG"; }

# ------------------------------------------------- upgrade: remove legacy bits
for f in "$CCBS_ETC/ccss.conf" "$CUSTOM"; do
  if [[ -f "$f" ]] && grep -qE "$CCBS_BEGIN_RE" "$f"; then ccbs_log "Removing legacy CCBS block from $(basename "$f")"; ccbs_remove_blocks "$f"; fi
done
for f in "$CCBS_SOUND_BASE"/custom/ccbs-*.wav; do
  [[ -e "$f" ]] || continue
  mv -f "$f" "$BACKUP_DIR/legacy-$(basename "$f")"; ccbs_log "Moved legacy prompt $(basename "$f") to backup"
done

# ------------------------------------------------------------------- render
render() {
  local c; c="$(<"$1")"
  local elig=' same => n,Goto(eligible)'
  if [[ "$REQUIRE_LOCAL" == 1 ]]; then elig=' same => n,GotoIf(${DB_EXISTS(DEVICE/${CCBS_DEV}/user)}?eligible:skip)'; fi
  c="${c//@VERSION@/$VERSION}";             c="${c//@PROMPT_ROOT@/$PROMPT_ROOT}"
  c="${c//@ACCEPT_DIGIT@/$ACCEPT_DIGIT}";   c="${c//@INPUT_TIMEOUT@/$INPUT_TIMEOUT}"
  c="${c//@OFFER_TIMER@/$OFFER_TIMER}";     c="${c//@CCBS_AVAILABLE_TIMER@/$CCBS_AVAIL}"
  c="${c//@CCNR_AVAILABLE_TIMER@/$CCNR_AVAIL}"; c="${c//@RECALL_TIMER@/$RECALL_TIMER}"
  c="${c//@MAX_MONITORS@/$MAX_MONITORS}";   c="${c//@CANCEL_CODE@/$CANCEL_CODE}"
  c="${c//@ELIGIBLE_CHECK@/$elig}"
  printf '%s\n' "$c"
}
TMP_SIP="$(mktemp)"; TMP_DP="$(mktemp)"; TMP_CUST="$(mktemp)"
trap 'rm -f "$TMP_SIP" "$TMP_DP" "$TMP_CUST"' EXIT
render "$SRC/etc/asterisk/ccbs-sip.conf.in"      > "$TMP_SIP"
render "$SRC/etc/asterisk/ccbs-dialplan.conf.in" > "$TMP_DP"

ccbs_log "Writing CC policies to $(basename "$SIP_GENERAL")"
ccbs_write_block "$SIP_GENERAL" "$TMP_SIP"
ccbs_log "Writing Busy hook to $OVERRIDE_NAME"
ccbs_write_block "$OVERRIDE" "$TMP_DP"
if [[ "$MANUAL_CANCEL" == 1 ]]; then
  render "$SRC/etc/asterisk/ccbs-custom.conf.in" > "$TMP_CUST"
  ccbs_log "Writing manual-cancel code $CANCEL_CODE to extensions_custom.conf (experimental)"
  ccbs_write_block "$CUSTOM" "$TMP_CUST"
fi
printf '%s\n' "${CCBS_CREATED[@]:-}" | sed '/^$/d' >> "$BACKUP_DIR/created.list"

# ------------------------------------------------------------------ prompts
ccbs_log "Installing Persian prompts into $SOUND_DIR"
for f in busy offer accepted cancelled failed; do
  install -m 0644 "$SRC/sounds/ccbs-$f.wav" "$SOUND_DIR/$f.wav"
done
if [[ "$CCBS_TESTING" != "1" ]]; then chown -R asterisk:asterisk "$CCBS_SOUND_BASE/custom/ccbs" 2>/dev/null || true; fi

# ------------------------------------------------------------------- reload
ccbs_log "Reloading chan_sip and dialplan"
ast 'sip reload' >/dev/null
ast 'dialplan reload' >/dev/null

# ------------------------------------------------------------------- verify
VERIFY_FAIL=0
if ast_has 'dialplan show s-BUSY@macro-dial-one' 'Gosub(ccbs-offer'; then ccbs_log "Verified: Busy hook is active"
else ccbs_warn "Busy hook NOT visible in dialplan."; VERIFY_FAIL=1; fi
if ast_has 'dialplan show s@ccbs-offer' 'CallCompletionRequest'; then ccbs_log "Verified: ccbs-offer context loaded"
else ccbs_warn "ccbs-offer context NOT visible in dialplan."; VERIFY_FAIL=1; fi
grep -q '^cc_agent_policy=generic' "$SIP_GENERAL" && ccbs_log "Verified: CC policies present in $(basename "$SIP_GENERAL")" || VERIFY_FAIL=1
if (( VERIFY_FAIL == 1 )); then ccbs_die "Verification failed. Roll back with: bash $SRC/scripts/rollback.sh $BACKUP_DIR"; fi

# ------------------------------------------------------- install support files
mkdir -p "$CCBS_PREFIX" "$CCBS_SBIN"
if [[ "$(cd "$CCBS_PREFIX" && pwd -P)" != "$SRC" ]]; then   # skip when re-run from the installed copy
  for d in lib scripts docs prompts etc tests sounds usr; do rm -rf "${CCBS_PREFIX:?}/$d"; cp -a "$SRC/$d" "$CCBS_PREFIX/"; done
  cp -a "$SRC"/install.sh "$SRC"/uninstall.sh "$SRC"/README.md "$SRC"/LICENSE "$SRC"/VERSION "$SRC"/CHANGELOG.md "$CCBS_PREFIX/"
fi
install -m 0755 "$SRC/usr/local/sbin/issabel-ccbs-check" "$CCBS_SBIN/issabel-ccbs-check"
install -m 0755 "$SRC/usr/local/sbin/issabel-ccbs-ctl"   "$CCBS_SBIN/issabel-ccbs-ctl"
echo "$BACKUP_DIR" > "$CCBS_STATE_FILE"

ccbs_log "Installation completed (v$VERSION). Backup: $BACKUP_DIR"
ccbs_log "Next: run 'issabel-ccbs-check', then test with two extensions (see docs/TEST-PLAN.md)."
"$CCBS_SBIN/issabel-ccbs-check" || true
