#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./fetch_one_day.sh <lof_file> <output_dir>

Input format:
  <lof_file> must contain tab-separated lines:
    <hendrix_path><TAB><local_filename>

Prerequisites on Belenos:
  - run on a transfert node
  - module load hpss/1.0
  - ftmotpasse -h hendrix -u <user> already done
EOF
}

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

[ $# -eq 2 ] || {
    usage
    exit 1
}

LOF_FILE="$1"
OUTPUT_DIR="$2"

[ -f "$LOF_FILE" ] || {
    log "ERROR: input file not found: $LOF_FILE"
    exit 1
}

mkdir -p "$OUTPUT_DIR"

command -v ftget >/dev/null 2>&1 || {
    log "ERROR: ftget not found. Run this script on a Belenos transfert node after 'module load hpss/1.0'."
    exit 1
}

log "Using ftget"
while IFS=$'\t' read -r rem_file loc_file; do
    [ -n "${rem_file:-}" ] || continue
    [ -n "${loc_file:-}" ] || continue
    ftget "$rem_file" "$OUTPUT_DIR/$loc_file"
done < "$LOF_FILE"
