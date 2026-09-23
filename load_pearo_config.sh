#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="$SCRIPT_DIR/config_input/pearo.env"
PEARO_CONFIG_FILE="${PEARO_CONFIG:-$DEFAULT_CONFIG}"

die() {
    echo "ERROR: $*" >&2
    return 1 2>/dev/null || exit 1
}

[ -f "$PEARO_CONFIG_FILE" ] || die "Missing config file: $PEARO_CONFIG_FILE"

# shellcheck disable=SC1090
. "$PEARO_CONFIG_FILE"

if [ -n "${WORKDIR:-}" ]; then
    default_data_root="$WORKDIR/PEARO_data"
else
    default_data_root="$HOME/PEARO_data"
fi

: "${PEARO_DATA_ROOT:=$default_data_root}"
: "${PEARO_STATE_ROOT:=$HOME/.pearo-toolkit-state}"
: "${PEARO_DAYS_FILE:=$SCRIPT_DIR/config_input/lof_days.txt}"
: "${PEARO_CONDA_SH:=/home/ext/cf/cglo/moinemp/SAVE/miniforge3/etc/profile.d/conda.sh}"
: "${PEARO_CONDA_ENV:=pearo_env}"
: "${PEARO_PRESTAGE_CHUNK_SIZE:=300}"
: "${PEARO_PRESTAGE_POLL_SECONDS:=120}"
: "${PEARO_PRESTAGE_MAX_POLLS:=180}"
: "${PEARO_TRANSFER_PARTITION:=transfert}"
: "${PEARO_TRANSFER_TIME:=02:00:00}"
: "${PEARO_PREPROCESS_PARTITION:=normal256}"
: "${PEARO_PREPROCESS_TIME:=01:00:00}"
: "${PEARO_SEND_PARTITION:=transfert}"
: "${PEARO_SEND_TIME:=00:10:00}"
: "${PEARO_SEND_HOST:=}"
: "${PEARO_SEND_USER:=}"
: "${PEARO_SEND_DEST_ROOT:=}"
: "${PEARO_DO_SEND:=1}"
: "${PEARO_CLEAN_ORIG:=1}"

export PEARO_CONFIG_FILE
export PEARO_DATA_ROOT
export PEARO_STATE_ROOT
export PEARO_DAYS_FILE
export PEARO_CONDA_SH
export PEARO_CONDA_ENV
export PEARO_PRESTAGE_CHUNK_SIZE
export PEARO_PRESTAGE_POLL_SECONDS
export PEARO_PRESTAGE_MAX_POLLS
export PEARO_TRANSFER_PARTITION
export PEARO_TRANSFER_TIME
export PEARO_PREPROCESS_PARTITION
export PEARO_PREPROCESS_TIME
export PEARO_SEND_PARTITION
export PEARO_SEND_TIME
export PEARO_SEND_HOST
export PEARO_SEND_USER
export PEARO_SEND_DEST_ROOT
export PEARO_DO_SEND
export PEARO_CLEAN_ORIG
