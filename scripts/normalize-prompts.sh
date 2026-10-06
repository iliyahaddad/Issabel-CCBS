#!/bin/bash
# Convert recorded prompts (wav/mp3/flac/ogg) to Asterisk-friendly PCM 16-bit mono 8 kHz WAV.
# Usage: normalize-prompts.sh SOURCE_DIR DEST_DIR
# Expects busy / offer / accepted / cancelled / failed (any supported extension) in SOURCE_DIR.
set -Eeuo pipefail

SRC="${1:-}"; DST="${2:-}"
[[ -n "$SRC" && -n "$DST" ]] || { echo "Usage: $0 SOURCE_DIR DEST_DIR" >&2; exit 2; }
command -v sox >/dev/null 2>&1 || { echo "SoX is required (yum/dnf install sox)." >&2; exit 1; }
mkdir -p "$DST"

for name in busy offer accepted cancelled failed; do
  in=""
  for ext in wav WAV mp3 flac ogg; do [[ -f "$SRC/$name.$ext" ]] && { in="$SRC/$name.$ext"; break; }; done
  [[ -n "$in" ]] || { echo "Missing: $SRC/$name.{wav,mp3,flac,ogg}" >&2; exit 1; }
  out="$DST/$name.wav"
  # trim leading/trailing silence, peak-normalize to -3 dB, then resample/downmix to telephony format
  sox "$in" -e signed-integer -b 16 -c 1 -r 8000 "$out" \
      silence 1 0.1 0.5% reverse silence 1 0.1 0.5% reverse norm -3
  dur="$(soxi -D "$out" 2>/dev/null || echo 0)"
  awk -v d="$dur" 'BEGIN{exit !(d > 0.2)}' || { echo "Output for $name is (nearly) empty - the silence trim removed everything. Check the source." >&2; exit 1; }
  soxi "$out"
done
echo "Prompt pack normalized successfully: $DST"
