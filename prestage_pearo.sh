#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./prestage_pearo.sh <lof_file> [options]

Options:
  --chunk-size N       Number of files per hstage/hfstat batch (default: 300)
  --poll-seconds N     Delay between status polls (default: 120)
  --max-polls N        Maximum number of polling rounds (default: 180)
  --retries N          Retries for a failed hstage/hfstat command (default: 3)
  --workdir DIR        Directory used for manifests and logs
  --verify-only        Skip hstage and only poll file status
  -h, --help           Show this help

Input format:
  <lof_file> can be either:
  - a plain list of Hendrix paths, one per line
  - a PEARO toolkit file with two columns:
      <hendrix_path><TAB><local_filename>

Prerequisites on Belenos:
  module load hpss/1.0
EOF
}

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

retry_cmd() {
    local tries="$1"
    shift
    local attempt=1

    while true; do
        if "$@"; then
            return 0
        fi

        if [ "$attempt" -ge "$tries" ]; then
            return 1
        fi

        log "Command failed (attempt ${attempt}/${tries}): $*"
        attempt=$((attempt + 1))
        sleep 5
    done
}

extract_hendrix_paths() {
    local input_file="$1"
    local output_file="$2"

    awk -F '\t' '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        {
            path = $1
            sub(/^[[:space:]]+/, "", path)
            sub(/[[:space:]]+$/, "", path)
            if (path != "") {
                print path
            }
        }
    ' "$input_file" | sort -u > "$output_file"
}

collect_pending_paths() {
    local input_file="$1"
    local output_file="$2"
    local raw_status="$3"
    : > "$output_file"
    : > "$raw_status"

    while IFS= read -r chunk_file; do
        [ -n "$chunk_file" ] || continue
        retry_cmd "$RETRIES" hfstat -f "$chunk_file" >> "$raw_status"
    done < <(find "$CHUNK_DIR" -type f -name 'chunk_[0-9][0-9][0-9][0-9]' | sort)

    awk '
        /: ONL\(/ { next }
        /: OFF\(/ || /: STA\(/ {
            line = $0
            sub(/^.*: /, "", line)
            sub(/: (OFF|STA)\(.*/, "", line)
            print line
        }
    ' "$raw_status" | sort -u > "$output_file"
}

LOF_FILE=""
CHUNK_SIZE=300
POLL_SECONDS=120
MAX_POLLS=180
RETRIES=3
VERIFY_ONLY=0
WORKDIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --chunk-size)
            CHUNK_SIZE="$2"
            shift 2
            ;;
        --poll-seconds)
            POLL_SECONDS="$2"
            shift 2
            ;;
        --max-polls)
            MAX_POLLS="$2"
            shift 2
            ;;
        --retries)
            RETRIES="$2"
            shift 2
            ;;
        --workdir)
            WORKDIR="$2"
            shift 2
            ;;
        --verify-only)
            VERIFY_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            if [ -n "$LOF_FILE" ]; then
                die "Only one input file is supported"
            fi
            LOF_FILE="$1"
            shift
            ;;
    esac
done

[ -n "$LOF_FILE" ] || {
    usage
    exit 1
}

[ -f "$LOF_FILE" ] || die "Input file not found: $LOF_FILE"
command -v hstage >/dev/null 2>&1 || die "hstage not found. Run 'module load hpss/1.0' first."
command -v hfstat >/dev/null 2>&1 || die "hfstat not found. Run 'module load hpss/1.0' first."

if [ -z "$WORKDIR" ]; then
    base_name="$(basename "$LOF_FILE")"
    base_name="${base_name%.*}"
    WORKDIR="$(pwd)/logs/prestage_${base_name}"
fi

mkdir -p "$WORKDIR"
CHUNK_DIR="$WORKDIR/chunks"
mkdir -p "$CHUNK_DIR"

MANIFEST_ALL="$WORKDIR/all_paths.txt"
MANIFEST_PENDING="$WORKDIR/pending_paths.txt"
RAW_STATUS="$WORKDIR/hfstat_latest.txt"

extract_hendrix_paths "$LOF_FILE" "$MANIFEST_ALL"
cp "$MANIFEST_ALL" "$MANIFEST_PENDING"

TOTAL_FILES="$(wc -l < "$MANIFEST_ALL" | tr -d ' ')"
[ "$TOTAL_FILES" -gt 0 ] || die "No Hendrix path found in $LOF_FILE"

log "Working directory: $WORKDIR"
log "Files to process: $TOTAL_FILES"
log "Chunk size: $CHUNK_SIZE"

poll=0
while true; do
    remaining="$(wc -l < "$MANIFEST_PENDING" | tr -d ' ')"

    if [ "$remaining" -eq 0 ]; then
        log "Prestaging complete: all files are ONL."
        break
    fi

    if [ "$poll" -ge "$MAX_POLLS" ]; then
        die "Maximum number of polls reached with $remaining file(s) still not ONL. Resume with --workdir $WORKDIR --verify-only or rerun the script."
    fi

    rm -f "$CHUNK_DIR"/chunk_*
    split -l "$CHUNK_SIZE" -d -a 4 "$MANIFEST_PENDING" "$CHUNK_DIR/chunk_"

    if [ "$VERIFY_ONLY" -eq 0 ]; then
        log "Submitting hstage for $remaining pending file(s)."
        while IFS= read -r chunk_file; do
            [ -n "$chunk_file" ] || continue
            retry_cmd "$RETRIES" hstage -a -f "$chunk_file" > "$chunk_file.hstage.log" 2>&1 || die "hstage failed for $chunk_file"
        done < <(find "$CHUNK_DIR" -type f -name 'chunk_[0-9][0-9][0-9][0-9]' | sort)
    else
        log "Verification round for $remaining pending file(s)."
    fi

    log "Polling HFSTAT status."
    collect_pending_paths "$MANIFEST_PENDING" "$WORKDIR/pending_next.txt" "$RAW_STATUS"

    mv "$WORKDIR/pending_next.txt" "$MANIFEST_PENDING"
    pending_after_poll="$(wc -l < "$MANIFEST_PENDING" | tr -d ' ')"
    onl_count=$((TOTAL_FILES - pending_after_poll))

    log "Status after poll ${poll}: ${onl_count}/${TOTAL_FILES} ONL, ${pending_after_poll} pending."

    if [ "$pending_after_poll" -eq 0 ]; then
        log "Prestaging complete: all files are ONL."
        break
    fi

    poll=$((poll + 1))
    log "Sleeping ${POLL_SECONDS}s before next round."
    sleep "$POLL_SECONDS"
done
