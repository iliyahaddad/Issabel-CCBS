#!/bin/bash
# Restore the Asterisk config files saved by install.sh.
# Usage: rollback.sh [BACKUP_DIR]   (default: the last backup)
set -Eeuo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/ccbs-common.sh
source "$SRC/lib/ccbs-common.sh"
ccbs_require_root

B="${1:-}"
[[ -n "$B" ]] || { [[ -f "$CCBS_STATE_FILE" ]] && B="$(<"$CCBS_STATE_FILE")"; }
[[ -n "$B" && -d "$B" ]] || ccbs_die "No backup directory found. Pass one explicitly."

if [[ -f "$B/etc-dir" ]]; then ETC="$(<"$B/etc-dir")"; else ETC="$CCBS_ETC"; fi
for f in "$B"/*.conf; do
  [[ -e "$f" ]] || continue
  cp -a "$f" "$ETC/$(basename "$f")"; ccbs_log "Restored $(basename "$f")"
done
if [[ -f "$B/created.list" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" && -e "$f" ]] || continue
    # only drop files that the installer created and that now hold nothing but our block
    rm -f "$f"; ccbs_log "Removed file created by installer: $f"
  done < "$B/created.list"
fi
if ccbs_find_asterisk; then ast 'sip reload' >/dev/null; ast 'dialplan reload' >/dev/null; fi
ccbs_log "Rollback from $B done. (Prompt files and /opt/issabel-ccbs were left in place; use uninstall.sh to remove them.)"
