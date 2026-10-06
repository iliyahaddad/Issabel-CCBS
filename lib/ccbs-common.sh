#!/bin/bash
# issabel-ccbs shared helpers. Source this file; do not execute it.
# Pure bash + coreutils + awk/grep/sed: no Python, no `file` dependency.

CCBS_NAME="issabel-ccbs"
CCBS_ETC="${CCBS_ETC_DIR:-/etc/asterisk}"
CCBS_SOUND_BASE="${CCBS_SOUND_BASE:-/var/lib/asterisk/sounds}"
CCBS_PREFIX="${CCBS_PREFIX:-/opt/issabel-ccbs}"
CCBS_SBIN="${CCBS_SBIN:-/usr/local/sbin}"
CCBS_BACKUP_ROOT="${CCBS_BACKUP_ROOT:-/var/backups/issabel-ccbs}"
CCBS_STATE_FILE="${CCBS_STATE_FILE:-/var/lib/issabel-ccbs-last-backup}"
CCBS_CONFIG="${CCBS_CONFIG:-$CCBS_ETC/issabel-ccbs.conf}"
CCBS_TESTING="${CCBS_TESTING:-0}"

# Managed-block markers are version-free so upgrades can always find them.
# Legacy (1.0/1.1) markers carried a version number and are matched as well.
CCBS_BEGIN_MARK='; ===== ISSABEL-CCBS BEGIN ====='
CCBS_END_MARK='; ===== ISSABEL-CCBS END ====='
CCBS_BEGIN_RE='^; ===== ISSABEL-CCBS( [0-9][0-9.]*)? BEGIN =====[[:space:]]*$'
CCBS_END_RE='^; ===== ISSABEL-CCBS( [0-9][0-9.]*)? END =====[[:space:]]*$'

ccbs_log()  { echo "[issabel-ccbs] $*"; }
ccbs_warn() { echo "[issabel-ccbs] WARNING: $*" >&2; }
ccbs_die()  { echo "[issabel-ccbs] ERROR: $*" >&2; exit 1; }

ccbs_require_root() {
  [[ "$CCBS_TESTING" == "1" || $EUID -eq 0 ]] || ccbs_die "Run as root."
}

# ---------------------------------------------------------------- Asterisk CLI
ASTERISK_BIN=""
ASTERISK_ARGS=(-rx)
ccbs_find_asterisk() {
  if command -v asterisk >/dev/null 2>&1; then
    ASTERISK_BIN="$(command -v asterisk)"; ASTERISK_ARGS=(-rx)
  elif command -v rasterisk >/dev/null 2>&1; then
    ASTERISK_BIN="$(command -v rasterisk)"; ASTERISK_ARGS=(-x)
  else
    return 1
  fi
}
# ast "cli command"  -> prints output, never aborts the caller
ast() { "$ASTERISK_BIN" "${ASTERISK_ARGS[@]}" "$1" 2>/dev/null || true; }
# ast_has "cli command" "substring"
ast_has() { local out; out="$(ast "$1")"; [[ "$out" == *"$2"* ]]; }

# --------------------------------------------------------------------- config
# ccbs_cfg key default  (reads KEY=VALUE lines from $CCBS_CONFIG, INI-style)
ccbs_cfg() {
  local k="$1" d="$2" v=""
  if [[ -f "$CCBS_CONFIG" ]]; then
    v="$(awk -v k="$k" '
      /^[[:space:]]*[;#]/ { next }
      /^[[:space:]]*\[/   { next }
      {
        i = index($0, "="); if (i == 0) next
        key = substr($0, 1, i - 1); gsub(/[[:space:]]/, "", key)
        if (key == k) {
          val = substr($0, i + 1)
          sub(/[[:space:]]*;.*$/, "", val)
          gsub(/^[[:space:]]+/, "", val); gsub(/[[:space:]]+$/, "", val)
          print val; exit
        }
      }' "$CCBS_CONFIG")"
  fi
  printf '%s' "${v:-$d}"
}

# ------------------------------------------------------------ managed blocks
ccbs_block_balanced() {
  local b e
  [[ -f "$1" ]] || return 0
  b="$(grep -cE "$CCBS_BEGIN_RE" "$1" || true)"
  e="$(grep -cE "$CCBS_END_RE" "$1" || true)"
  [[ "$b" == "$e" ]]
}

ccbs_trim_trailing_blank() {
  local f="$1" tmp; tmp="$(mktemp)"
  awk '{a[NR]=$0} END{n=NR; while(n>0 && a[n] ~ /^[[:space:]]*$/) n--; for(i=1;i<=n;i++) print a[i]}' "$f" > "$tmp"
  cat "$tmp" > "$f"; rm -f "$tmp"       # cat > keeps owner/mode of $f
}

# Remove every managed block (any version) from a file; refuse if unbalanced.
ccbs_remove_blocks() {
  local f="$1" tmp
  [[ -f "$f" ]] || return 0
  grep -qE "$CCBS_BEGIN_RE" "$f" || return 0
  ccbs_block_balanced "$f" || ccbs_die "$f has unbalanced ISSABEL-CCBS markers; fix it manually (refusing to edit)."
  tmp="$(mktemp)"
  awk -v b="$CCBS_BEGIN_RE" -v e="$CCBS_END_RE" '
    $0 ~ b { skip=1; next }
    skip && $0 ~ e { skip=0; next }
    !skip { print }' "$f" > "$tmp"
  cat "$tmp" > "$f"; rm -f "$tmp"
  ccbs_trim_trailing_blank "$f"
}

CCBS_CREATED=()
ccbs_own_new() {
  [[ "$CCBS_TESTING" == "1" ]] && return 0
  chown asterisk:asterisk "$1" 2>/dev/null || true
  chmod 0664 "$1" 2>/dev/null || true
}

# ccbs_write_block FILE CONTENT_FILE : replace/append the managed block in FILE
ccbs_write_block() {
  local f="$1" src="$2"
  if [[ ! -e "$f" ]]; then : > "$f"; CCBS_CREATED+=("$f"); ccbs_own_new "$f"; fi
  ccbs_remove_blocks "$f"
  ccbs_trim_trailing_blank "$f"
  {
    if [[ -s "$f" ]]; then printf '\n'; fi
    printf '%s\n' "$CCBS_BEGIN_MARK"
    cat "$src"
    printf '%s\n' "$CCBS_END_MARK"
  } >> "$f"
}

# ---------------------------------------------------------------------- WAV
# ccbs_wav_info FILE -> prints "format channels rate bits seconds" ; rc!=0 if not a WAV
ccbs_wav_info() {
  local f="$1" total off=12 id size fmt="" ch="" rate="" bits="" dsize=""
  [[ -s "$f" ]] || return 1
  [[ "$(head -c4 "$f" 2>/dev/null)" == "RIFF" ]] || return 1
  [[ "$(dd if="$f" bs=1 skip=8 count=4 2>/dev/null)" == "WAVE" ]] || return 1
  total="$(stat -c %s "$f")"
  while (( off + 8 <= total )); do
    id="$(dd if="$f" bs=1 skip=$off count=4 2>/dev/null | tr -d '\000')"
    size="$(od -An -t u4 -j $((off + 4)) -N4 "$f" | tr -d ' ')"
    if [[ "$id" == "fmt " ]]; then
      fmt="$(od -An -t u2 -j $((off + 8))  -N2 "$f" | tr -d ' ')"
      ch="$(od -An -t u2 -j $((off + 10)) -N2 "$f" | tr -d ' ')"
      rate="$(od -An -t u4 -j $((off + 12)) -N4 "$f" | tr -d ' ')"
      bits="$(od -An -t u2 -j $((off + 22)) -N2 "$f" | tr -d ' ')"
    elif [[ "$id" == "data" ]]; then
      dsize="$size"; break
    fi
    off=$(( off + 8 + size + (size & 1) ))
  done
  [[ -n "$fmt" && -n "$dsize" ]] || return 1
  local secs=0
  if (( rate > 0 && ch > 0 && bits > 0 )); then secs=$(( dsize / (rate * ch * bits / 8) )); fi
  echo "$fmt $ch $rate $bits $secs"
}

# PCM(1) / mono / 8000 Hz / 16-bit
ccbs_wav_ok() {
  local info; info="$(ccbs_wav_info "$1")" || return 1
  [[ "${info% *}" == "1 1 8000 16" ]]
}
ccbs_wav_seconds() { local i; i="$(ccbs_wav_info "$1")" || { echo 0; return; }; echo "${i##* }"; }
