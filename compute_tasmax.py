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
parser.add_argument("--members_file", type=str, help="Fichier contenant un tag mbXXX par ligne")
parser.add_argument("--skip_existing", action="store_true", help="Ne pas recalculer les NetCDF déjà présents")

args = parser.parse_args()

print("Arguments reçus par le script compute_tasmax.py :")
print(f"  - day_tag: {args.day_tag}")
print(f"  - orig_datadir: {args.orig_datadir}")
print(f"  - prepro_datadir: {args.prepro_datadir}")
print(f"  - members_file: {args.members_file}")

EXPECTED_HOURLY_FIELDS = 12
CHUNKS = {"latitude": 200, "longitude": 200}
GRIB_FILTER = {
    "stepType": "instant",
    "typeOfLevel": "heightAboveGround",
    "level": 2,
    "paramId": 167,
}

orig_datadir = Path(args.orig_datadir)
prepro_datadir = Path(args.prepro_datadir)
prepro_datadir.mkdir(parents=True, exist_ok=True)

if args.members_file:
    members_file = Path(args.members_file)
    if not members_file.is_file():
        raise FileNotFoundError(f"Fichier de membres absent: {members_file}")
    member_tags = sorted(
        {
            line.strip()
            for line in members_file.read_text(encoding="utf-8").splitlines()
            if line.strip()
        }
    )
else:
    member_tags = sorted(
        {
            filepath.name.split("_", 1)[0]
            for filepath in orig_datadir.glob(f"mb???_{args.day_tag}_*.grib")
        }
    )

if not member_tags:
    raise FileNotFoundError(f"Aucun membre trouve dans {orig_datadir}")

for member_tag in member_tags:
    if len(member_tag) != 5 or not member_tag.startswith("mb") or not member_tag[2:].isdigit():
        raise ValueError(f"Tag membre invalide: {member_tag}")

    # Forecast lead times depend on the PE-AROME run. The file list selects
    # the daytime window; do not assume fixed lead times in filenames.
    hourly_data_files = sorted(
        orig_datadir.glob(f"{member_tag}_{args.day_tag}_*.grib")
    )
    if not hourly_data_files:
        raise FileNotFoundError(
            f"{member_tag}: aucun fichier GRIB trouve dans {orig_datadir}"
        )

    output_file = prepro_datadir / f"tasmax_PEARO_{member_tag}_{args.day_tag}.nc"
    if args.skip_existing and output_file.is_file() and output_file.stat().st_size > 0:
        print(f"{member_tag}: keeping existing {output_file}")
        continue

    # ouverture lazy + multi-fichiers (tous les fichiers horaires pour un membres donné/un jour donné)
    ds = xr.open_mfdataset(
        [str(filepath) for filepath in hourly_data_files],
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

        if "valid_time" not in ds.coords:
            raise KeyError(f"{member_tag}: coordonnee 'valid_time' absente du GRIB")

        valid_times = np.unique(np.asarray(ds["valid_time"].values))
        if len(valid_times) != EXPECTED_HOURLY_FIELDS:
            raise ValueError(
                f"{member_tag}: {len(valid_times)} instant(s) de validite, "
                f"{EXPECTED_HOURLY_FIELDS} attendu(s)"
            )

        hourly_gaps = np.diff(valid_times).astype("timedelta64[h]")
        if not np.all(hourly_gaps == np.timedelta64(1, "h")):
            raise ValueError(
                f"{member_tag}: les instants de validite ne sont pas horaires et consecutifs"
            )

        # Maximum sur les 12 champs horaires selectionnes par la liste d'entree.
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
