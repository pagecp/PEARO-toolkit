# -*- coding: utf-8 -*-
import argparse
from datetime import datetime
from pathlib import Path

import numpy as np
import xarray as xr

parser = argparse.ArgumentParser()

parser.add_argument("--day_tag", required=True, type=str, help="Jour à traiter (format YYYY-MM-DD)")
parser.add_argument("--orig_datadir", required=True, type=str, help="Répertoire des données d'origine à traiter")
parser.add_argument("--prepro_datadir", required=True,type=str, help="Répertoire des données prétraitées à générer")
parser.add_argument("--nb_members", type=int, default=16, help="Nombre de membres à traiter")

args = parser.parse_args()

print("Arguments reçus par le script compute_tasmax.py :")
print(f"  - day_tag: {args.day_tag}")
print(f"  - orig_datadir: {args.orig_datadir}")
print(f"  - prepro_datadir: {args.prepro_datadir}")
print(f"  - nb_members: {args.nb_members}")

FIX_STAMP = "grid.arome-forecast.eurw1s40+00"
DAY_HOURS = range(12, 24)
CHUNKS = {"latitude": 200, "longitude": 200}
GRIB_FILTER = {
    "stepType": "instant",
    "typeOfLevel": "heightAboveGround",
    "level": 2,
    "paramId": 167,
}

Path(args.prepro_datadir).mkdir(parents=True, exist_ok=True)

for mbr in range(1, args.nb_members + 1):
    # lecture séquentielle des membres
    member_tag = f"mb{mbr:03d}"

    # exemple de nom de ficher d'origine: mb001_2022-08-11_grid.arome-forecast.eurw1s40+0013:00.grib
    hourly_data_files = [
        f"{args.orig_datadir}/{member_tag}_{args.day_tag}_{FIX_STAMP}{hour}:00.grib"
        for hour in DAY_HOURS  # données diurnes
    ]

    missing_files = [filepath for filepath in hourly_data_files if not Path(filepath).is_file()]
    if missing_files:
        raise FileNotFoundError(
            f"{member_tag}: {len(missing_files)} fichier(s) horaire(s) manquant(s), "
            f"ex. {missing_files[0]}"
        )

    # ouverture lazy + multi-fichiers (tous les fichiers horaires pour un membres donné/un jour donné)
    ds = xr.open_mfdataset(
        hourly_data_files,
        engine="cfgrib",
        combine="nested",
        concat_dim="step",  # ou "time" selon cfgrib
        parallel=True,
        chunks=CHUNKS,
        backend_kwargs={"filter_by_keys": GRIB_FILTER},
    )

    try:
        if "t2m" not in ds:
            raise KeyError(f"{member_tag}: variable 't2m' absente du GRIB")

        # Max journalier (diurne) de la température de l'air à 2 m.
        tasmax = (
            ds["t2m"]
            .max(dim="step")
            .expand_dims(time=[np.datetime64(args.day_tag)])
            .rename("tasmax")
            .to_dataset()
        )

        tasmax.attrs["title"] = "Daily maximum near-surface air temperature from PEARO"
        tasmax.attrs["source"] = "PEARO (Meteo-France)"
        tasmax.attrs["history"] = f"Created on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} by compute_tasmax.py"
        tasmax.attrs["author"] = "M-P. Moine (CERFACS)"
        tasmax["tasmax"].attrs["long_name"] = "Daily maximum near-surface air temperature"
        tasmax["tasmax"].attrs["standard_name"] = "air_temperature"
        tasmax["tasmax"].attrs["units"] = "K"

        output_file = f"{args.prepro_datadir}/tasmax_PEARO_{member_tag}_{args.day_tag}.nc"
        tasmax.to_netcdf(output_file)
        print(f"{member_tag}: wrote {output_file}")
    finally:
        ds.close()

    # clefs possibles pour filter_by_keys pour les fichiers grib PEARO:
    #
    # filter_by_keys={'typeOfLevel': 'surface'}
    # filter_by_keys={'typeOfLevel': 'isobaricInhPa'}
    # filter_by_keys={'typeOfLevel': 'heightAboveGround'}
    # filter_by_keys={'typeOfLevel': 'unknown'}
    # filter_by_keys={'typeOfLevel': 'nominalTop'}
    # filter_by_keys={'typeOfLevel': 'meanSea'}
    #
    # filter_by_keys={'stepType': 'instant', 'typeOfLevel': 'heightAboveGround', 'level': 2, 'paramId': 167}
    # filter_by_keys={'stepType': 'accum', 'typeOfLevel': 'surface'}
    # filter_by_keys={'stepType': 'min', 'typeOfLevel': 'surface'}
    # filter_by_keys={'stepType': 'avg', 'typeOfLevel': 'surface'}
    # filter_by_keys={'stepType': 'max', 'typeOfLevel': 'surface'}
