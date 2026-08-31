#!/bin/bash
set -euo pipefail

DO_GET_DATA=1
[ $# -ge 1 ] && DO_GET_DATA="$1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/load_pearo_config.sh"

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

count_expected_files() {
    local lof_file="$1"
    awk -F '\t' '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        NF >= 1 { count++ }
        END { print count + 0 }
    ' "$lof_file"
}

count_output_files() {
    local pattern="$1"
    find "$2" -maxdepth 1 -type f -name "$pattern" | wc -l | tr -d ' '
}

mkdir -p "$SCRIPT_DIR/logs" "$PEARO_STATE_ROOT"

while IFS= read -r DAY_FMT; do
    [ -n "$DAY_FMT" ] || continue

    DAY_STATE_DIR="$PEARO_STATE_ROOT/$DAY_FMT"
    LOF_FILE="$SCRIPT_DIR/config_input/lof_${DAY_FMT}.txt"
    DATA_INDIR="$PEARO_DATA_ROOT/orig_data/$DAY_FMT"
    DATA_OUTDIR="$PEARO_DATA_ROOT/prepro_data/$DAY_FMT"
    TRANSFER_MARK="$DAY_STATE_DIR/transfer.ok"
    PREPROCESS_MARK="$DAY_STATE_DIR/preprocess.ok"
    SEND_MARK="$DAY_STATE_DIR/send.ok"
    DONE_MARK="$DAY_STATE_DIR/done.ok"

    [ -f "$LOF_FILE" ] || die "Missing file list for $DAY_FMT: $LOF_FILE"

    mkdir -p "$DAY_STATE_DIR" "$DATA_INDIR" "$DATA_OUTDIR"

    if [ -f "$DONE_MARK" ]; then
        log "Skipping $DAY_FMT: already done."
        continue
    fi

    EXPECTED_FILES="$(count_expected_files "$LOF_FILE")"
    [ "$EXPECTED_FILES" -gt 0 ] || die "Empty file list for $DAY_FMT: $LOF_FILE"

    log "Processing $DAY_FMT"

    if [ "$DO_GET_DATA" -eq 1 ]; then
        "$SCRIPT_DIR/prestage_pearo.sh" \
            "$LOF_FILE" \
            --chunk-size "$PEARO_PRESTAGE_CHUNK_SIZE" \
            --poll-seconds "$PEARO_PRESTAGE_POLL_SECONDS" \
            --max-polls "$PEARO_PRESTAGE_MAX_POLLS" \
            --workdir "$DAY_STATE_DIR/prestage"

        CURRENT_FILES="$(count_output_files '*.grib' "$DATA_INDIR")"
        if [ ! -f "$TRANSFER_MARK" ] || [ "$CURRENT_FILES" -lt "$EXPECTED_FILES" ]; then
            log "Submitting transfer job for $DAY_FMT"
            sbatch \
                --wait \
                --partition="$PEARO_TRANSFER_PARTITION" \
                --time="$PEARO_TRANSFER_TIME" \
                "$SCRIPT_DIR/get_one_day.job" \
                "$DAY_FMT" \
                "$DATA_INDIR"
            touch "$TRANSFER_MARK"
        else
            log "Transfer already complete for $DAY_FMT"
        fi
    fi

    CURRENT_NC="$(count_output_files 'tasmax_PEARO_*.nc' "$DATA_OUTDIR")"
    if [ ! -f "$PREPROCESS_MARK" ] || [ "$CURRENT_NC" -lt "$PEARO_NB_MEMBERS" ]; then
        log "Submitting preprocess job for $DAY_FMT"
        sbatch \
            --wait \
            --partition="$PEARO_PREPROCESS_PARTITION" \
            --time="$PEARO_PREPROCESS_TIME" \
            "$SCRIPT_DIR/preprocess_one_day.job" \
            "$DAY_FMT" \
            "$DATA_INDIR" \
            "$DATA_OUTDIR"
        touch "$PREPROCESS_MARK"
    else
        log "Preprocess already complete for $DAY_FMT"
    fi

    if [ "$PEARO_DO_SEND" -eq 1 ]; then
        [ -n "$PEARO_SEND_HOST" ] || die "PEARO_SEND_HOST is empty"
        [ -n "$PEARO_SEND_USER" ] || die "PEARO_SEND_USER is empty"
        [ -n "$PEARO_SEND_DEST_ROOT" ] || die "PEARO_SEND_DEST_ROOT is empty"

        if [ ! -f "$SEND_MARK" ]; then
            log "Submitting send job for $DAY_FMT"
            sbatch \
                --wait \
                --partition="$PEARO_SEND_PARTITION" \
                --time="$PEARO_SEND_TIME" \
                "$SCRIPT_DIR/send_data_one_day.job" \
                "$DATA_OUTDIR" \
                "$PEARO_SEND_HOST" \
                "$PEARO_SEND_USER" \
                "$PEARO_SEND_DEST_ROOT/$DAY_FMT"
            touch "$SEND_MARK"
        else
            log "Send already complete for $DAY_FMT"
        fi
    fi

    if [ "$PEARO_CLEAN_ORIG" -eq 1 ]; then
        log "Cleaning scratch input for $DAY_FMT"
        rm -f "$DATA_INDIR"/*.grib
    fi

    touch "$DONE_MARK"
    log "Day $DAY_FMT completed"
done < "$PEARO_DAYS_FILE"
