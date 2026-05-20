"""
extract_cmip6.py
----------------
One-time script that pulls monthly carbon and energy flux variables from the
Pangeo Google Cloud CMIP6 catalog for three Earth System Models and saves a
single CSV per model centred on the US-MMS eddy-covariance tower.

Target site
-----------
US-MMS  Morgan Monroe State Forest, Indiana
lat = 39.3232 N
lon = -86.4131 E  (note: some models store longitude as 0-360, handled below)

Models extracted
----------------
CESM2            (NCAR)       member r1i1p1f1  scenarios: historical + ssp370
IPSL-CM6A-LR     (IPSL)       member r1i1p1f1  scenarios: historical + ssp245
UKESM1-0-LL      (MOHC/NERC)  member r1i1p1f2  scenarios: historical only
                                                (no SSP available in Pangeo catalog)

Why different members and scenarios?
  The Pangeo Google Cloud CMIP6 catalog (pangeo-cmip6.json) is a curated
  subset, not a mirror of the full ESGF archive.  As of 2025:
    - CESM2 Lmon is present for historical (r1i1p1f1) and ssp370 (r4i1p1f1)
      but NOT ssp245.
    - UKESM1-0-LL uses forcing label f2, so its member IDs all end in p1f2.
      It has no SSP scenario for Lmon in the Pangeo catalog.
    - IPSL-CM6A-LR has both ssp245 and historical for r1i1p1f1.
  The MODEL_CONFIG dict below makes these choices explicit and documented.

Time range extracted
--------------------
historical   1980-01-01 to 2014-12-31  (common across all three models)
future       2015-01-01 to 2021-12-31  (where a scenario is available)

Variables requested
-------------------
Lmon table (monthly land):
  gpp      gross primary production                  kg m-2 s-1
  npp      net primary production                    kg m-2 s-1
  rh       heterotrophic respiration                 kg m-2 s-1
  ra       autotrophic respiration                   kg m-2 s-1
  nee      net ecosystem exchange                    kg m-2 s-1
  nbp      net biome production                      kg m-2 s-1
  lai      leaf area index                           m2 m-2
  evspsbl  evapotranspiration                        kg m-2 s-1
  hfdsl    downwelling longwave at the surface       W m-2

Amon table (monthly atmosphere):
  rsds     surface downwelling shortwave             W m-2
  rsus     surface upwelling shortwave               W m-2
  rlds     surface downwelling longwave              W m-2
  rlus     surface upwelling longwave                W m-2
  hfls     surface upward latent heat flux           W m-2
  hfss     surface upward sensible heat flux         W m-2

Output
------
data/cmip6/CESM2_usmms_monthly.csv
data/cmip6/IPSL-CM6A-LR_usmms_monthly.csv
data/cmip6/UKESM1-0-LL_usmms_monthly.csv

Each CSV has columns: year, month, scenario, <descriptive variable names>, ...
Missing variables are omitted for that model.
"""

import os
import warnings
import numpy as np
import pandas as pd
import xarray as xr
import intake

# ---------------------------------------------------------------------------
# Site coordinates
# ---------------------------------------------------------------------------

SITE_LAT = 39.3232   # Morgan Monroe State Forest, Indiana
SITE_LON = -86.4131  # stored as -180/180; we convert model lons below

# ---------------------------------------------------------------------------
# Per-model configuration
# Each entry: source_id -> {
#   "member_hist"  : member ID to use for the historical experiment,
#   "member_fut"   : member ID to use for the future scenario (may differ),
#   "scenario"     : CMIP6 experiment_id for the future period,
#   "hist_range"   : (start, end) dates for historical slice,
#   "fut_range"    : (start, end) dates for future slice, or None,
# }
#
# NOTE: member_hist and member_fut differ for CESM2 because the only SSP370
# run with Lmon output on Pangeo uses r4i1p1f1, not r1i1p1f1.
# ---------------------------------------------------------------------------

MODEL_CONFIG = {
    "CESM2": {
        "member_hist": "r1i1p1f1",
        "member_fut":  "r4i1p1f1",   # only member with ssp370 Lmon on Pangeo
        "scenario":    "ssp370",
        "hist_range":  ("1980-01", "2014-12"),   # month-only to avoid 360-day calendar issues
        "fut_range":   ("2015-01", "2021-12"),
    },
    "IPSL-CM6A-LR": {
        "member_hist": "r1i1p1f1",
        "member_fut":  "r1i1p1f1",
        "scenario":    "ssp245",
        "hist_range":  ("1980-01", "2014-12"),
        "fut_range":   ("2015-01", "2021-12"),
    },
    "UKESM1-0-LL": {
        "member_hist": "r1i1p1f2",   # UKESM uses forcing label f2
        "member_fut":  None,          # no SSP Lmon data in Pangeo catalog
        "scenario":    None,
        # Month-only endpoints are essential here: UKESM uses a 360-day
        # calendar (Datetime360Day) where months have exactly 30 days, so
        # "2014-12-31" is an invalid date and xarray raises an error.
        "hist_range":  ("1980-01", "2014-12"),
        "fut_range":   None,
    },
}

# Pangeo public catalog — no credentials required for read access
CATALOG_URL = "https://storage.googleapis.com/cmip6/pangeo-cmip6.json"

# Output directory is the same directory as this script
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Variable definitions
# table_id -> list of (cmip6_short_name, descriptive_output_column_name)
# ---------------------------------------------------------------------------
VARIABLES = {
    "Lmon": [
        ("gpp",      "gpp_kgC_m2_s"),       # gross primary production
        ("npp",      "npp_kgC_m2_s"),       # net primary production
        ("rh",       "rh_kgC_m2_s"),        # heterotrophic respiration
        ("ra",       "ra_kgC_m2_s"),        # autotrophic respiration
        ("nee",      "nee_kgC_m2_s"),       # net ecosystem exchange
        ("nbp",      "nbp_kgC_m2_s"),       # net biome production
        ("lai",      "lai_m2_m2"),           # leaf area index
        ("evspsbl",  "et_kg_m2_s"),         # evapotranspiration
        ("hfdsl",    "lw_down_sfc_W_m2"),   # downwelling LW at surface
    ],
    "Amon": [
        ("rsds",  "sw_down_sfc_W_m2"),      # surface downwelling shortwave
        ("rsus",  "sw_up_sfc_W_m2"),        # surface upwelling shortwave
        ("rlds",  "lw_down_atm_W_m2"),      # surface downwelling longwave
        ("rlus",  "lw_up_sfc_W_m2"),        # surface upwelling longwave
        ("hfls",  "latent_heat_W_m2"),      # surface upward latent heat
        ("hfss",  "sensible_heat_W_m2"),    # surface upward sensible heat
    ],
}


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def normalize_lon(ds):
    """
    Ensure the longitude coordinate uses the -180/180 convention.

    CMIP6 models are inconsistent: some store longitude as 0-360 (e.g. CESM2)
    and others as -180 to 180 (e.g. IPSL).  We shift any values > 180 by
    subtracting 360, then re-sort so .sel(lon=..., method='nearest') works.
    """
    if "lon" not in ds.coords:
        return ds

    lon_vals = ds["lon"].values
    if lon_vals.max() > 180:
        ds = ds.assign_coords(lon=(ds["lon"] + 180) % 360 - 180)
        ds = ds.sortby("lon")
    return ds


def decode_times(da):
    """
    Convert cftime or other CMIP6 time representations to a pandas
    DatetimeIndex.  Returns a 1-D DatetimeIndex aligned to da.time.
    """
    try:
        return da.time.to_index().to_datetimeindex()
    except Exception:
        # Fallback: cast each cftime object to ISO string then parse
        return pd.DatetimeIndex([str(t) for t in da.time.values])


def extract_point(ds, var_name):
    """
    Select the nearest grid cell to the US-MMS site from an xr.Dataset and
    return a tidy DataFrame with columns [year, month, var_name].
    """
    ds = normalize_lon(ds)

    # nearest-neighbour selection on the 2-D lat/lon grid
    da = ds[var_name].sel(lat=SITE_LAT, lon=SITE_LON, method="nearest", drop=True)

    times = decode_times(da)
    values = da.values.squeeze()   # remove residual size-1 dimensions

    return pd.DataFrame({
        "year":    times.year,
        "month":   times.month,
        var_name:  values,
    })


def open_experiment(catalog, source_id, experiment_id, table_id, variable_id, member, start, end):
    """
    Search the catalog for one variable / model / experiment combination,
    open as xarray, slice to [start, end], and return the dataset.

    Returns None if the combination is absent from the catalog.
    """
    subset = catalog.search(
        source_id=source_id,
        experiment_id=experiment_id,
        table_id=table_id,
        variable_id=variable_id,
        member_id=member,
    )

    if len(subset.df) == 0:
        return None

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")   # suppress zarr/dask deprecation noise
        dset_dict = subset.to_dataset_dict(
            xarray_open_kwargs={"consolidated": True, "use_cftime": True},
            progressbar=False,
        )

    ds = list(dset_dict.values())[0]
    return ds.sel(time=slice(start, end))


# ---------------------------------------------------------------------------
# Per-model extraction
# ---------------------------------------------------------------------------

def extract_model(catalog, source_id):
    """
    Extract all variables for one model across historical + future (if available),
    select the US-MMS grid cell, and return a merged DataFrame.

    Prints a per-variable success / failure log.
    """
    cfg = MODEL_CONFIG[source_id]
    print(f"\n{'='*60}")
    print(f"Model      : {source_id}")
    print(f"Hist member: {cfg['member_hist']}  ({cfg['hist_range'][0]} – {cfg['hist_range'][1]})")
    if cfg["scenario"]:
        print(f"Fut member : {cfg['member_fut']}  ({cfg['fut_range'][0]} – {cfg['fut_range'][1]})  [{cfg['scenario']}]")
    else:
        print(f"Future     : none available in catalog")
    print(f"{'='*60}")

    # Build the list of (experiment_id, member, start, end) periods to request
    periods = [("historical", cfg["member_hist"],
                cfg["hist_range"][0], cfg["hist_range"][1])]
    if cfg["scenario"]:
        periods.append((cfg["scenario"], cfg["member_fut"],
                        cfg["fut_range"][0], cfg["fut_range"][1]))

    all_var_dfs = []   # one element per successfully-extracted variable
    succeeded = []
    failed = []

    for table_id, var_list in VARIABLES.items():
        for (var_short, col_name) in var_list:

            exp_dfs = []   # DataFrames for each period (historical, future)

            for (exp_id, member, start, end) in periods:
                print(f"  {source_id} / {exp_id} / {table_id} / {var_short} [{member}] ...",
                      end=" ", flush=True)
                try:
                    ds = open_experiment(
                        catalog, source_id, exp_id, table_id, var_short, member, start, end
                    )
                    if ds is None:
                        print("NOT IN CATALOG")
                        # If historical is missing, skip the future period too
                        break
                    df_exp = extract_point(ds, var_short)
                    # Tag the period so students know which scenario applies
                    df_exp["scenario"] = exp_id
                    print(f"OK ({len(df_exp)} months)")
                    exp_dfs.append(df_exp)

                except Exception as exc:
                    print(f"ERROR: {exc}")
                    break   # don't attempt the future period if historical failed

            if not exp_dfs:
                failed.append(f"{table_id}/{var_short}")
                continue

            # Concatenate historical and future along the time axis
            df_var = pd.concat(exp_dfs, ignore_index=True)
            df_var = df_var.rename(columns={var_short: col_name})
            all_var_dfs.append(df_var)
            succeeded.append(f"{table_id}/{var_short} → {col_name}")

    # ------------------------------------------------------------------
    # Merge all variables into one wide DataFrame keyed on (year, month)
    # ------------------------------------------------------------------
    if not all_var_dfs:
        print(f"\n  No variables extracted for {source_id}.")
        return None

    merged = all_var_dfs[0]
    for df_v in all_var_dfs[1:]:
        # Merge on year + month; scenario is identical across variables so
        # we keep it from the first df only (suffixes handle duplicates).
        merge_cols = ["year", "month", "scenario"]
        # Drop the duplicate scenario column from subsequent dfs before merging
        df_v_clean = df_v.drop(columns=["scenario"])
        merged = merged.merge(df_v_clean, on=["year", "month"], how="outer")

    merged = merged.sort_values(["year", "month"]).reset_index(drop=True)

    # ------------------------------------------------------------------
    # Print extraction summary
    # ------------------------------------------------------------------
    print(f"\n  Extracted ({len(succeeded)}/{len(succeeded)+len(failed)} variables):")
    for s in succeeded:
        print(f"    ✔  {s}")
    if failed:
        print(f"  Not available in catalog ({len(failed)}):")
        for f in failed:
            print(f"    ✘  {f}")
    print(f"\n  Output: {len(merged)} rows × {len(merged.columns)} columns")

    return merged


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Loading Pangeo CMIP6 catalog …")
    catalog = intake.open_esm_datastore(CATALOG_URL)
    print(f"Catalog loaded: {len(catalog.df):,} entries")

    summary = {}

    for model in MODEL_CONFIG:
        df = extract_model(catalog, model)

        if df is not None:
            out_path = os.path.join(OUT_DIR, f"{model}_usmms_monthly.csv")
            df.to_csv(out_path, index=False)
            print(f"  Saved → {out_path}")
            summary[model] = {
                "rows": len(df),
                "vars": [c for c in df.columns if c not in ("year", "month", "scenario")],
                "date_range": f"{df['year'].min()}-{df['month'].min():02d} to "
                              f"{df['year'].max()}-{df['month'].max():02d}",
                "status": "OK",
            }
        else:
            summary[model] = {"status": "FAILED"}

    # ------------------------------------------------------------------
    # Final summary table
    # ------------------------------------------------------------------
    print(f"\n{'='*60}")
    print("EXTRACTION SUMMARY")
    print(f"{'='*60}")
    for model, info in summary.items():
        print(f"\n{model}: {info['status']}")
        if info["status"] == "OK":
            print(f"  Rows       : {info['rows']}")
            print(f"  Date range : {info['date_range']}")
            print(f"  Variables  : {', '.join(info['vars'])}")


if __name__ == "__main__":
    main()
