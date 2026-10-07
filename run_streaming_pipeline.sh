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
        NF >= 2 {
            filename = $2
            sub(/^[[:space:]]+/, "", filename)
            sub(/[[:space:]]+$/, "", filename)
            if (filename != "") {
                expected[filename] = 1
            }
        }
        END { for (filename in expected) { count++ }; print count + 0 }
    ' "$lof_file"
}

extract_expected_filenames() {
    awk -F '\t' '
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        NF >= 2 {
            filename = $2
            sub(/^[[:space:]]+/, "", filename)
            sub(/[[:space:]]+$/, "", filename)
            if (filename != "") {
                print filename
            }
        }
    ' "$1" | sort -u
}

extract_expected_members() {
    awk -F '\t' '
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        {
            if (match($2, /^mb[0-9][0-9][0-9]_/) != 0) {
                print substr($2, RSTART, 5)
            } else if (match($1, /\/mb[0-9][0-9][0-9]\//) != 0) {
                print substr($1, RSTART + 1, 5)
            }
        }
    ' "$1" | sort -u
}

missing_manifest_entries() {
    local manifest="$1"
    local directory="$2"
    local prefix="$3"
    local suffix="$4"

    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        [ -s "$directory/$prefix$entry$suffix" ] || printf '%s\n' "$entry"
    done < "$manifest"
}

filter_lof_by_filenames() {
    local lof_file="$1"
    local filenames_file="$2"

    awk -F '\t' '
        FNR == NR { wanted[$1] = 1; next }
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        NF >= 2 {
            filename = $2
            sub(/^[[:space:]]+/, "", filename)
            sub(/[[:space:]]+$/, "", filename)
            if (filename in wanted && !emitted[filename]++) {
                print
            }
        }
    ' "$filenames_file" "$lof_file"
}

extract_member_tags() {
    sed -n 's|.*\/\(mb[0-9][0-9][0-9]\)\/.*|\1|p; s|^\(mb[0-9][0-9][0-9]\)_.*|\1|p' "$1" | sort -u
}

filter_lof_excluding_members() {
    local lof_file="$1"
    local excluded_members="$2"

    awk -F '\t' '
        FNR == NR { excluded[$1] = 1; next }
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        {
            if (match($2, /^mb[0-9][0-9][0-9]_/) != 0) {
                member = substr($2, RSTART, 5)
            } else if (match($1, /\/mb[0-9][0-9][0-9]\//) != 0) {
                member = substr($1, RSTART + 1, 5)
            } else {
                next
            }
            if (!(member in excluded)) {
                print
            }
        }
    ' "$excluded_members" "$lof_file"
}

filter_lof_by_members() {
    local lof_file="$1"
    local members_file="$2"

    awk -F '\t' '
        FNR == NR { wanted[$1] = 1; next }
        /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
        {
            if (match($2, /^mb[0-9][0-9][0-9]_/) != 0) {
                member = substr($2, RSTART, 5)
            } else if (match($1, /\/mb[0-9][0-9][0-9]\//) != 0) {
                member = substr($1, RSTART + 1, 5)
            } else {
                next
            }
            if (member in wanted) {
                print
            }
        }
    ' "$members_file" "$lof_file"
}

refresh_expected_manifests() {
    EXPECTED_FILES="$(count_expected_files "$LOF_FILE")"
    extract_expected_filenames "$LOF_FILE" > "$EXPECTED_FILES_FILE"
    extract_expected_members "$LOF_FILE" > "$EXPECTED_MEMBERS_FILE"
    EXPECTED_MEMBERS="$(wc -l < "$EXPECTED_MEMBERS_FILE" | tr -d ' ')"
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
    EXPECTED_FILES_FILE="$DAY_STATE_DIR/expected_grib_files.txt"
    EXPECTED_MEMBERS_FILE="$DAY_STATE_DIR/expected_members.txt"
    MISSING_NC_FILE="$DAY_STATE_DIR/missing_members.txt"
    UNAVAILABLE_MEMBERS_FILE="$DAY_STATE_DIR/unavailable_members.tsv"
    USABLE_LOF_FILE="$DAY_STATE_DIR/usable_lof.txt"

    [ -f "$LOF_FILE" ] || die "Missing file list for $DAY_FMT: $LOF_FILE"

    mkdir -p "$DAY_STATE_DIR" "$DATA_INDIR" "$DATA_OUTDIR"

    EXPECTED_FILES="$(count_expected_files "$LOF_FILE")"
    [ "$EXPECTED_FILES" -gt 0 ] || die "Empty file list for $DAY_FMT: $LOF_FILE"
    extract_expected_filenames "$LOF_FILE" > "$EXPECTED_FILES_FILE"
    extract_expected_members "$LOF_FILE" > "$EXPECTED_MEMBERS_FILE"
    EXPECTED_MEMBERS="$(wc -l < "$EXPECTED_MEMBERS_FILE" | tr -d ' ')"
    [ "$EXPECTED_MEMBERS" -gt 0 ] || die "No member tag found in $LOF_FILE"

    missing_manifest_entries \
        "$EXPECTED_MEMBERS_FILE" "$DATA_OUTDIR" "tasmax_PEARO_" "_${DAY_FMT}.nc" \
        > "$MISSING_NC_FILE"
    MISSING_NC="$(wc -l < "$MISSING_NC_FILE" | tr -d ' ')"

    if [ -f "$DONE_MARK" ] && [ "$MISSING_NC" -eq 0 ]; then
        log "Skipping $DAY_FMT: all $EXPECTED_MEMBERS member(s) already done."
        continue
    fi

    if [ -f "$DONE_MARK" ]; then
        log "Reopening $DAY_FMT: $MISSING_NC member(s) are missing."
        rm -f "$DONE_MARK"
    fi

    if [ "$MISSING_NC" -gt 0 ]; then
        filter_lof_by_members "$LOF_FILE" "$MISSING_NC_FILE" > "$USABLE_LOF_FILE"
        LOF_FILE="$USABLE_LOF_FILE"
        refresh_expected_manifests
        log "Processing only $EXPECTED_MEMBERS missing member(s) for $DAY_FMT."
    fi

    log "Processing $DAY_FMT"

    if [ "$DO_GET_DATA" -eq 1 ]; then
        "$SCRIPT_DIR/prestage_pearo.sh" \
            "$LOF_FILE" \
            --chunk-size "$PEARO_PRESTAGE_CHUNK_SIZE" \
            --poll-seconds "$PEARO_PRESTAGE_POLL_SECONDS" \
            --max-polls "$PEARO_PRESTAGE_MAX_POLLS" \
            --workdir "$DAY_STATE_DIR/prestage" \
            --continue-on-error

        : > "$UNAVAILABLE_MEMBERS_FILE"
        extract_member_tags "$DAY_STATE_DIR/prestage/failed_paths.txt" > "$DAY_STATE_DIR/unavailable_tags.txt"
        while IFS= read -r member; do
            [ -n "$member" ] || continue
            printf '%s\t%s\tprestage\n' "$DAY_FMT" "$member" >> "$UNAVAILABLE_MEMBERS_FILE"
        done < "$DAY_STATE_DIR/unavailable_tags.txt"

        if [ -s "$DAY_STATE_DIR/unavailable_tags.txt" ]; then
            filter_lof_excluding_members "$LOF_FILE" "$DAY_STATE_DIR/unavailable_tags.txt" > "$USABLE_LOF_FILE"
            LOF_FILE="$USABLE_LOF_FILE"
            refresh_expected_manifests
        fi

        if [ "$EXPECTED_MEMBERS" -eq 0 ]; then
            log "Skipping $DAY_FMT: no recoverable member."
            touch "$DAY_STATE_DIR/skipped.ok"
            continue
        fi

        MISSING_GRIB_FILE="$DAY_STATE_DIR/missing_grib_files.txt"
        MISSING_GRIB_LOF="$DAY_STATE_DIR/missing_grib_lof.txt"
        TRANSFER_FAILED_FILE="$DAY_STATE_DIR/transfer_failed.tsv"
        missing_manifest_entries "$EXPECTED_FILES_FILE" "$DATA_INDIR" "" "" > "$MISSING_GRIB_FILE"
        MISSING_GRIB="$(wc -l < "$MISSING_GRIB_FILE" | tr -d ' ')"
        if [ "$MISSING_GRIB" -gt 0 ]; then
            filter_lof_by_filenames "$LOF_FILE" "$MISSING_GRIB_FILE" > "$MISSING_GRIB_LOF"
            log "Submitting transfer job for $DAY_FMT"
            sbatch \
                --wait \
                --partition="$PEARO_TRANSFER_PARTITION" \
                --time="$PEARO_TRANSFER_TIME" \
                "$SCRIPT_DIR/get_one_day.job" \
                "$DAY_FMT" \
                "$DATA_INDIR" \
                "$MISSING_GRIB_LOF" \
                "$TRANSFER_FAILED_FILE"
            touch "$TRANSFER_MARK"
        elif [ ! -f "$TRANSFER_MARK" ]; then
            log "All GRIB files are already present for $DAY_FMT"
            touch "$TRANSFER_MARK"
        else
            log "Transfer already complete for $DAY_FMT"
        fi

        if [ -s "$TRANSFER_FAILED_FILE" ]; then
            cut -f 2 "$TRANSFER_FAILED_FILE" | extract_member_tags /dev/stdin > "$DAY_STATE_DIR/transfer_failed_members.txt"
            while IFS= read -r member; do
                [ -n "$member" ] || continue
                printf '%s\t%s\ttransfer\n' "$DAY_FMT" "$member" >> "$UNAVAILABLE_MEMBERS_FILE"
            done < "$DAY_STATE_DIR/transfer_failed_members.txt"
            sort -u "$DAY_STATE_DIR/unavailable_tags.txt" "$DAY_STATE_DIR/transfer_failed_members.txt" > "$DAY_STATE_DIR/all_unavailable_tags.txt"
            filter_lof_excluding_members "$LOF_FILE" "$DAY_STATE_DIR/all_unavailable_tags.txt" > "$USABLE_LOF_FILE"
            LOF_FILE="$USABLE_LOF_FILE"
            refresh_expected_manifests
        fi

        if [ "$EXPECTED_MEMBERS" -eq 0 ]; then
            log "Skipping $DAY_FMT: no recoverable member."
            touch "$DAY_STATE_DIR/skipped.ok"
            continue
        fi

        missing_manifest_entries "$EXPECTED_FILES_FILE" "$DATA_INDIR" "" "" > "$MISSING_GRIB_FILE"
        MISSING_GRIB="$(wc -l < "$MISSING_GRIB_FILE" | tr -d ' ')"
        [ "$MISSING_GRIB" -eq 0 ] || die "Transfer incomplete for $DAY_FMT: $MISSING_GRIB file(s) missing"
    fi

    missing_manifest_entries \
        "$EXPECTED_MEMBERS_FILE" "$DATA_OUTDIR" "tasmax_PEARO_" "_${DAY_FMT}.nc" \
        > "$MISSING_NC_FILE"
    MISSING_NC="$(wc -l < "$MISSING_NC_FILE" | tr -d ' ')"
    if [ ! -f "$PREPROCESS_MARK" ] || [ "$MISSING_NC" -gt 0 ]; then
        log "Submitting preprocess job for $DAY_FMT"
        rm -f "$SEND_MARK" "$DONE_MARK"
        sbatch \
            --wait \
            --partition="$PEARO_PREPROCESS_PARTITION" \
            --time="$PEARO_PREPROCESS_TIME" \
            "$SCRIPT_DIR/preprocess_one_day.job" \
            "$DAY_FMT" \
            "$DATA_INDIR" \
            "$DATA_OUTDIR" \
            "$EXPECTED_MEMBERS_FILE"
        touch "$PREPROCESS_MARK"
    else
        log "Preprocess already complete for $DAY_FMT"
    fi

    missing_manifest_entries \
        "$EXPECTED_MEMBERS_FILE" "$DATA_OUTDIR" "tasmax_PEARO_" "_${DAY_FMT}.nc" \
        > "$MISSING_NC_FILE"
    MISSING_NC="$(wc -l < "$MISSING_NC_FILE" | tr -d ' ')"
    [ "$MISSING_NC" -eq 0 ] || die "Preprocess incomplete for $DAY_FMT: $MISSING_NC member(s) missing"

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

UNAVAILABLE_REPORT="$PEARO_STATE_ROOT/unavailable_members.tsv"
find "$PEARO_STATE_ROOT" -mindepth 2 -maxdepth 2 -type f -name 'unavailable_members.tsv' \
    -exec cat {} + | sort -u > "$UNAVAILABLE_REPORT"
if [ -s "$UNAVAILABLE_REPORT" ]; then
    log "Unavailable members report: $UNAVAILABLE_REPORT"
fi
