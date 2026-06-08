"""
extract_cmip6_allsites.py
--------------------------
Extends extract_cmip6.py to pull the same monthly CMIP6 variables for four
eddy-covariance tower sites:

    US-MMS  Morgan Monroe State Forest, Indiana   (39.3232 N, -86.4131 E)
    US-NR1  Niwot Ridge, Colorado                 (40.0329 N, -105.5464 E)
    DE-Tha  Tharandt, Germany                     (50.9636 N,  13.5669 E)
    DK-Sor  Sorø, Denmark                         (55.4859 N,  11.6446 E)

US-MMS is skipped because its CSVs were already produced by extract_cmip6.py.

Why a separate script rather than modifying extract_cmip6.py?
  The original script produces files used directly by the exercise Rmd files.
  Keeping it unchanged protects reproducibility for US-MMS.  This script adds
  the remaining sites without touching existing outputs.

Models, variables, member IDs, and time ranges are identical to extract_cmip6.py.
See that file for detailed commentary on why each model/member combination was
chosen and how the Pangeo catalog is structured.

Output files
------------
data/cmip6/CESM2_{site_file_id}_monthly.csv
data/cmip6/IPSL-CM6A-LR_{site_file_id}_monthly.csv
data/cmip6/UKESM1-0-LL_{site_file_id}_monthly.csv

where {site_file_id} is the site ID converted to lowercase with hyphens
removed (e.g. US-NR1 → usnr1, DE-Tha → detha, DK-Sor → dksor).

Required Python packages
------------------------
Install into whichever environment you use to run this script:
    pip install intake intake-esm xarray zarr pandas numpy gcsfs

The fluxnet virtualenv (~/.virtualenvs/fluxnet) does NOT include these —
use a separate environment (e.g. a conda env with conda-forge packages).

Usage
-----
    python data/cmip6/extract_cmip6_allsites.py
"""

import os
import warnings
import numpy as np
import pandas as pd
import xarray as xr
import intake

# ---------------------------------------------------------------------------
# Site definitions
# ---------------------------------------------------------------------------
# lat/lon in decimal degrees; lon uses the -180 to 180 convention.
# The normalize_lon() function below converts model output that uses 0-360.

SITES = {
    "US-MMS": {"lat": 39.3232,  "lon": -86.4131},   # Indiana, USA
    "US-NR1": {"lat": 40.0329,  "lon": -105.5464},  # Colorado, USA
    "DE-Tha": {"lat": 50.9636,  "lon":  13.5669},   # Tharandt, Germany
    "DK-Sor": {"lat": 55.4859,  "lon":  11.6446},   # Sorø, Denmark
}

# US-MMS output was already produced by extract_cmip6.py — skip it here
# to avoid redownloading ~20 GB of Pangeo data unnecessarily.
SKIP_SITES = {"US-MMS"}

# ---------------------------------------------------------------------------
# Per-model configuration
# (identical to extract_cmip6.py — see that file for the reasoning)
# ---------------------------------------------------------------------------
# Each entry: source_id -> {
#   "member_hist"  : member ID to use for the historical experiment,
#   "member_fut"   : member ID to use for the future scenario (may differ),
#   "scenario"     : CMIP6 experiment_id for the future period,
#   "hist_range"   : (start, end) month strings for the historical slice,
#   "fut_range"    : (start, end) month strings for the future slice, or None,
# }
#
# Month-only endpoints ("1980-01" not "1980-01-01") are essential for UKESM1,
# which uses a 360-day calendar (30 days per month) where day 31 does not exist.

MODEL_CONFIG = {
    "CESM2": {
        "member_hist": "r1i1p1f1",
        "member_fut":  "r4i1p1f1",   # only member with ssp370 Lmon on Pangeo
        "scenario":    "ssp370",
        "hist_range":  ("1980-01", "2014-12"),
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
        "hist_range":  ("1980-01", "2014-12"),
        "fut_range":   None,
    },
}

# Pangeo Google Cloud CMIP6 catalog — publicly readable, no credentials needed
CATALOG_URL = "https://storage.googleapis.com/cmip6/pangeo-cmip6.json"

# Output files land in the same directory as this script (data/cmip6/)
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------
# Variable definitions
# table_id -> list of (cmip6_short_name, descriptive_output_column_name)
# (identical to extract_cmip6.py — units are in the column names)
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
        ("hfdsl",    "lw_down_sfc_W_m2"),   # downwelling longwave at surface
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

def site_file_id(site_id):
    """
    Convert a site ID string to a filename-safe token.

    We use lowercase with hyphens removed to match the convention already
    established for US-MMS (extract_cmip6.py → CESM2_usmms_monthly.csv).

    Examples
    --------
    "US-NR1" → "usnr1"
    "DE-Tha" → "detha"
    "DK-Sor" → "dksor"
    """
    return site_id.lower().replace("-", "")


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
        # Shift the coordinate so everything is in -180..180, then re-sort
        ds = ds.assign_coords(lon=(ds["lon"] + 180) % 360 - 180)
        ds = ds.sortby("lon")
    return ds


def decode_times(da):
    """
    Convert cftime or other CMIP6 time representations to a pandas
    DatetimeIndex.  Returns a 1-D DatetimeIndex aligned to da.time.

    CMIP6 models use non-standard calendars (360-day, noleap, etc.) that
    xarray represents as cftime objects.  pandas needs a standard datetime.
    We first try the fast path (.to_datetimeindex()), then fall back to
    parsing the ISO string representation of each timestamp.
    """
    try:
        return da.time.to_index().to_datetimeindex()
    except Exception:
        # The 360-day calendar (UKESM1-0-LL) falls through to here.
        # str(t) on a cftime.Datetime360Day gives "YYYY-MM-DD 00:00:00"
        # which pandas can parse even though the date may be non-standard.
        return pd.DatetimeIndex([str(t) for t in da.time.values])


def extract_point(ds, var_name, site_lat, site_lon):
    """
    Select the nearest grid cell to (site_lat, site_lon) from an xr.Dataset
    and return a tidy DataFrame with columns [year, month, var_name].

    Parameters
    ----------
    ds        : xr.Dataset containing var_name with lat/lon/time dimensions
    var_name  : CMIP6 short variable name (e.g. "gpp")
    site_lat  : site latitude in decimal degrees
    site_lon  : site longitude in decimal degrees (-180 to 180)
    """
    # Convert model longitudes to -180/180 if needed before selection
    ds = normalize_lon(ds)

    # Select nearest grid cell; drop=True removes lat/lon as residual
    # scalar dimensions from the result
    da = ds[var_name].sel(lat=site_lat, lon=site_lon, method="nearest", drop=True)

    times = decode_times(da)
    values = da.values.squeeze()   # collapse any remaining size-1 dimensions

    return pd.DataFrame({
        "year":    times.year,
        "month":   times.month,
        var_name:  values,
    })


def open_experiment(catalog, source_id, experiment_id, table_id,
                    variable_id, member, start, end):
    """
    Search the Pangeo catalog for one variable / model / experiment, open the
    dataset as xarray, slice to [start, end], and return it.

    Returns None if the combination is absent from the catalog.

    Parameters
    ----------
    catalog       : intake-esm ESM datastore object
    source_id     : CMIP6 model name (e.g. "CESM2")
    experiment_id : "historical" or a scenario name (e.g. "ssp245")
    table_id      : "Lmon" or "Amon"
    variable_id   : CMIP6 short name (e.g. "gpp")
    member        : member ID string (e.g. "r1i1p1f1")
    start, end    : month strings for time slice (e.g. "1980-01", "2014-12")
    """
    subset = catalog.search(
        source_id=source_id,
        experiment_id=experiment_id,
        table_id=table_id,
        variable_id=variable_id,
        member_id=member,
    )

    if len(subset.df) == 0:
        # The requested combination simply is not in the Pangeo catalog
        return None

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")   # suppress zarr/dask deprecation noise
        dset_dict = subset.to_dataset_dict(
            xarray_open_kwargs={"consolidated": True, "use_cftime": True},
            progressbar=False,
        )

    # The dict has one entry; extract it and slice to the desired time window
    ds = list(dset_dict.values())[0]
    return ds.sel(time=slice(start, end))


# ---------------------------------------------------------------------------
# Per-model extraction for a single site
# ---------------------------------------------------------------------------

def extract_model_for_site(catalog, source_id, site_id, site_lat, site_lon):
    """
    Extract all configured variables for one model and one site.

    Concatenates the historical and future periods (where available), selects
    the nearest grid cell, and returns a merged wide DataFrame.

    Prints a per-variable success/failure log as it goes.

    Parameters
    ----------
    catalog   : intake-esm ESM datastore
    source_id : CMIP6 model name (e.g. "CESM2")
    site_id   : site identifier string (e.g. "US-NR1"), used only for logging
    site_lat  : site latitude in decimal degrees
    site_lon  : site longitude in decimal degrees

    Returns
    -------
    pd.DataFrame or None
        Wide DataFrame with columns [year, month, scenario, ...variable cols...]
        Returns None if no variables were successfully extracted.
    """
    cfg = MODEL_CONFIG[source_id]

    print(f"\n{'='*60}")
    print(f"Site       : {site_id}")
    print(f"Model      : {source_id}")
    print(f"Hist member: {cfg['member_hist']}  "
          f"({cfg['hist_range'][0]} – {cfg['hist_range'][1]})")
    if cfg["scenario"]:
        print(f"Fut member : {cfg['member_fut']}  "
              f"({cfg['fut_range'][0]} – {cfg['fut_range'][1]})  "
              f"[{cfg['scenario']}]")
    else:
        print(f"Future     : none available in catalog")
    print(f"{'='*60}")

    # Build the list of (experiment_id, member, start, end) periods to request.
    # For models without a future scenario, the list has only one entry.
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

            exp_dfs = []   # DataFrames for each time period (hist, future)

            for (exp_id, member, start, end) in periods:
                print(
                    f"  {source_id} / {site_id} / {exp_id} / "
                    f"{table_id} / {var_short} [{member}] ...",
                    end=" ", flush=True,
                )
                try:
                    ds = open_experiment(
                        catalog, source_id, exp_id, table_id,
                        var_short, member, start, end,
                    )
                    if ds is None:
                        print("NOT IN CATALOG")
                        # If the historical period is missing, there is no
                        # point trying the future period for this variable.
                        break
                    df_exp = extract_point(ds, var_short, site_lat, site_lon)
                    # Tag each row with the scenario so students know whether
                    # a given year is from the historical run or a projection.
                    df_exp["scenario"] = exp_id
                    print(f"OK ({len(df_exp)} months)")
                    exp_dfs.append(df_exp)

                except Exception as exc:
                    print(f"ERROR: {exc}")
                    break   # skip the future period if the historical failed

            if not exp_dfs:
                failed.append(f"{table_id}/{var_short}")
                continue

            # Stack historical and future rows along the time axis
            df_var = pd.concat(exp_dfs, ignore_index=True)
            # Rename the raw CMIP6 name (e.g. "gpp") to the descriptive column
            # name that includes units (e.g. "gpp_kgC_m2_s")
            df_var = df_var.rename(columns={var_short: col_name})
            all_var_dfs.append(df_var)
            succeeded.append(f"{table_id}/{var_short} → {col_name}")

    # ------------------------------------------------------------------
    # Merge all per-variable DataFrames into one wide table keyed on
    # (year, month).  We merge iteratively rather than in one call so
    # that a missing variable does not create NaN rows for other variables.
    # ------------------------------------------------------------------
    if not all_var_dfs:
        print(f"\n  No variables extracted for {source_id} at {site_id}.")
        return None

    merged = all_var_dfs[0]
    for df_v in all_var_dfs[1:]:
        # Drop the duplicate "scenario" column from all but the first DataFrame
        # before joining — every variable has the same scenario value for a
        # given (year, month) so we only need it once.
        df_v_clean = df_v.drop(columns=["scenario"])
        merged = merged.merge(df_v_clean, on=["year", "month"], how="outer")

    merged = merged.sort_values(["year", "month"]).reset_index(drop=True)

    # ------------------------------------------------------------------
    # Print extraction summary for this model × site combination
    # ------------------------------------------------------------------
    n_vars = len(VARIABLES["Lmon"]) + len(VARIABLES["Amon"])
    print(f"\n  Extracted ({len(succeeded)}/{n_vars} variables):")
    for s in succeeded:
        print(f"    ✔  {s}")
    if failed:
        print(f"  Not available in catalog ({len(failed)}):")
        for f_var in failed:
            print(f"    ✘  {f_var}")
    print(f"\n  Output: {len(merged)} rows × {len(merged.columns)} columns")

    return merged


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Loading Pangeo CMIP6 catalog …")
    catalog = intake.open_esm_datastore(CATALOG_URL)
    print(f"Catalog loaded: {len(catalog.df):,} entries")

    # Nested summary: site → model → result metadata
    summary = {}

    for site_id, coords in SITES.items():

        if site_id in SKIP_SITES:
            print(f"\n[SKIP] {site_id} — CSVs already exist from extract_cmip6.py")
            summary[site_id] = {"status": "SKIPPED"}
            continue

        summary[site_id] = {}

        for model in MODEL_CONFIG:
            df = extract_model_for_site(
                catalog, model,
                site_id, coords["lat"], coords["lon"],
            )

            if df is not None:
                # Construct the output filename using the same convention as
                # extract_cmip6.py:  {MODEL}_{site_file_id}_monthly.csv
                fid = site_file_id(site_id)
                out_path = os.path.join(OUT_DIR, f"{model}_{fid}_monthly.csv")
                df.to_csv(out_path, index=False)
                print(f"  Saved → {out_path}")
                summary[site_id][model] = {
                    "rows": len(df),
                    "vars": [c for c in df.columns
                             if c not in ("year", "month", "scenario")],
                    "date_range": (
                        f"{df['year'].min()}-{df['month'].min():02d} to "
                        f"{df['year'].max()}-{df['month'].max():02d}"
                    ),
                    "status": "OK",
                    "output": out_path,
                }
            else:
                summary[site_id][model] = {"status": "FAILED"}

    # ------------------------------------------------------------------
    # Final summary across all sites and models
    # ------------------------------------------------------------------
    print(f"\n{'='*60}")
    print("EXTRACTION SUMMARY — ALL SITES")
    print(f"{'='*60}")
    for site_id, site_info in summary.items():
        print(f"\n{site_id}:")
        if isinstance(site_info, dict) and site_info.get("status") == "SKIPPED":
            print("  SKIPPED (existing files retained)")
            continue
        for model, info in site_info.items():
            print(f"  {model}: {info['status']}")
            if info["status"] == "OK":
                print(f"    Rows      : {info['rows']}")
                print(f"    Date range: {info['date_range']}")
                print(f"    Variables : {', '.join(info['vars'])}")
                print(f"    Output    : {info['output']}")


if __name__ == "__main__":
    main()
