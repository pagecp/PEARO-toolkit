#!/bin/bash
set -euo pipefail

DO_GET_DATA=1 # valeur par défaut
[ $# -ge 1 ] && DO_GET_DATA=$1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "$0: SCRIPT_DIR: $SCRIPT_DIR"
CONFIG_DIR=$SCRIPT_DIR/config_input
# shellcheck disable=SC1091
. "$SCRIPT_DIR/load_pearo_config.sh"

mkdir -p $SCRIPT_DIR/logs

i=0
while read DAY_FMT; do 

    # traitement des jours en parallèle
    i=$((i+1))

    echo "Traitement du jour $DAY_FMT"

    DATA_INDIR=$PEARO_DATA_ROOT/orig_data/$DAY_FMT
    DATA_OUTDIR=$PEARO_DATA_ROOT/prepro_data/$DAY_FMT
    mkdir -p $DATA_INDIR
    mkdir -p $DATA_OUTDIR

    # 1. job  de transfert
    if [ $DO_GET_DATA -eq 1 ]
    then
        jid_transfer=$(sbatch --parsable get_one_day.job "$DAY_FMT" "$DATA_INDIR")
    fi

    # 2. job de preprocessing
    if [ $DO_GET_DATA -eq 1 ]
    then
        jid_prepro=$(sbatch --parsable --dependency=afterok:$jid_transfer preprocess_one_day.job "$DAY_FMT" "$DATA_INDIR" "$DATA_OUTDIR")
    else
        jid_prepro=$(sbatch --parsable preprocess_one_day.job "$DAY_FMT" "$DATA_INDIR" "$DATA_OUTDIR")
    fi
        
    # 3. send results at cerfacs
    if [ "${PEARO_DO_SEND}" -eq 1 ]
    then
        sbatch --dependency=afterok:$jid_prepro send_data_one_day.job "$DATA_OUTDIR" "$PEARO_SEND_HOST" "$PEARO_SEND_USER" "$PEARO_SEND_DEST_ROOT/$DAY_FMT"
    fi

    # 4. cleaning
    # rm -f $DATA_INDIR/*.grib
    
done < $PEARO_DAYS_FILE

echo "Nombre de jours traités : $i"
