#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./fetch_one_day.sh <lof_file> <output_dir> [--retries N] [--failed-file FILE] [--continue-on-error]

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

is_connectivity_error() {
    grep -Eqi 'No route to host|Network is unreachable|Connection (refused|timed out|reset)|connect.*return (101|111|113)' "$1"
}

[ $# -ge 2 ] || { usage; exit 1; }
LOF_FILE="$1"
OUTPUT_DIR="$2"
shift 2
RETRIES=3
FAILED_FILE=""
CONTINUE_ON_ERROR=0

while [ $# -gt 0 ]; do
    case "$1" in
        --retries) RETRIES="$2"; shift 2 ;;
        --failed-file) FAILED_FILE="$2"; shift 2 ;;
        --continue-on-error) CONTINUE_ON_ERROR=1; shift ;;
        *) echo "ERROR: unknown option: $1" >&2; exit 1 ;;
    esac
done

[ -f "$LOF_FILE" ] || {
    log "ERROR: input file not found: $LOF_FILE"
    exit 1
}

mkdir -p "$OUTPUT_DIR"
[ -z "$FAILED_FILE" ] || : > "$FAILED_FILE"
FAILED_MEMBERS_FILE="$OUTPUT_DIR/.failed_members.$$"
TRANSFER_ATTEMPT_LOG="$OUTPUT_DIR/.ftget_attempt.$$"
: > "$FAILED_MEMBERS_FILE"
trap 'rm -f "$FAILED_MEMBERS_FILE" "$TRANSFER_ATTEMPT_LOG"' EXIT

command -v ftget >/dev/null 2>&1 || {
    log "ERROR: ftget not found. Run this script on a Belenos transfert node after 'module load hpss/1.0'."
    exit 1
}

log "Using ftget"
while IFS=$'\t' read -r rem_file loc_file; do
    [ -n "${rem_file:-}" ] || continue
    [ -n "${loc_file:-}" ] || continue
    member_tag="${loc_file%%_*}"
    if grep -qx "$member_tag" "$FAILED_MEMBERS_FILE"; then
        log "Skipping $loc_file: $member_tag already failed."
        continue
    fi
    attempt=1
    while true; do
        if ftget "$rem_file" "$OUTPUT_DIR/$loc_file" > "$TRANSFER_ATTEMPT_LOG" 2>&1; then
            cat "$TRANSFER_ATTEMPT_LOG"
            break
        fi
        cat "$TRANSFER_ATTEMPT_LOG"
        if is_connectivity_error "$TRANSFER_ATTEMPT_LOG"; then
            log "ERROR: Hendrix connectivity failure while transferring $loc_file."
            exit 2
        fi
        if [ "$attempt" -ge "$RETRIES" ]; then
            rm -f "$OUTPUT_DIR/$loc_file"
            if [ -n "$FAILED_FILE" ]; then
                printf '%s\t%s\n' "$rem_file" "$loc_file" >> "$FAILED_FILE"
            fi
            printf '%s\n' "$member_tag" >> "$FAILED_MEMBERS_FILE"
            if [ "$CONTINUE_ON_ERROR" -eq 0 ]; then
                exit 1
            fi
            break
        fi
        log "Transfer failed for $loc_file (attempt ${attempt}/${RETRIES}); retrying."
        attempt=$((attempt + 1))
        sleep 5
    done
done < "$LOF_FILE"
