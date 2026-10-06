#!/bin/bash
# Issabel CCBS uninstaller: removes every managed block (any version), prompts and tools.
set -Eeuo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ccbs-common.sh
source "$SRC/lib/ccbs-common.sh"
ccbs_require_root

PROMPT_ROOT="$(ccbs_cfg prompt_root custom/ccbs/fa)"
for f in "$CCBS_ETC/sip_general_custom.conf" "$CCBS_ETC/extensions_override_issabelpbx.conf" \
         "$CCBS_ETC/extensions_override_freepbx.conf" "$CCBS_ETC/extensions_custom.conf" "$CCBS_ETC/ccss.conf"; do
  [[ -f "$f" ]] || continue
  if grep -qE "$CCBS_BEGIN_RE" "$f"; then ccbs_log "Cleaning $(basename "$f")"; ccbs_remove_blocks "$f"; fi
done
rm -rf "$CCBS_SOUND_BASE/custom/ccbs"
[[ "$PROMPT_ROOT" == custom/ccbs/fa ]] || rm -rf "${CCBS_SOUND_BASE:?}/$PROMPT_ROOT"
rm -f "$CCBS_SBIN/issabel-ccbs-check" "$CCBS_SBIN/issabel-ccbs-ctl" "$CCBS_STATE_FILE"
rm -rf "$CCBS_PREFIX"

if ccbs_find_asterisk; then
  ast 'sip reload' >/dev/null; ast 'dialplan reload' >/dev/null
  ast 'database del ccbs disabled' >/dev/null
fi
echo "Issabel CCBS removed. Backups and /etc/asterisk/issabel-ccbs.conf were kept."
