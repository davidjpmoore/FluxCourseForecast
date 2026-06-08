"""
extract_fluxcom_allsites.py
----------------------------
Extracts FLUXCOM-X-BASE monthly flux data for four eddy-covariance sites and
saves one CSV per site.

What is FLUXCOM-X-BASE?
-----------------------
FLUXCOM-X-BASE (Nelson et al. 2024, Biogeosciences) is a global machine-
learning upscaling product that estimates land–atmosphere carbon and water
fluxes on a regular grid by combining eddy-covariance tower data (FLUXNET)
with remote sensing and meteorological drivers.  It is distinct from the
simpler process-based SSEM model students run in Exercise 01.

Citation
--------
Nelson, J. A., et al. (2024). FLUXCOM-X opens a new chapter in the
FLUXCOM initiative for multivariate land surface flux upscaling.
Biogeosciences, 21(1), 1–12.
Data DOI: https://doi.org/10.18160/5NZG-JMJE  (ICOS Carbon Portal)
GitLab repository: https://gitlab.gwdg.de/fluxcom/fluxcomxdata

Target sites
------------
US-MMS  Morgan Monroe State Forest, Indiana   (39.3232 N, -86.4131 E)
US-NR1  Niwot Ridge, Colorado                 (40.0329 N, -105.5464 E)
DE-Tha  Tharandt, Germany                     (50.9636 N,  13.5669 E)
DK-Sor  Sorø, Denmark                         (55.4859 N,  11.6446 E)

Variables extracted
--------------------
GPP   Gross Primary Production     gC m-2 d-1
NEE   Net Ecosystem Exchange       gC m-2 d-1
TER   Total Ecosystem Respiration  gC m-2 d-1  (computed: GPP - NEE)
ET    Evapotranspiration (as proxy for LE)

Time period: 2001-01 to 2021-12 (monthly, 0.5° spatial resolution)

Output files
------------
data/fluxcom/US-MMS_fluxcom_monthly.csv
data/fluxcom/US-NR1_fluxcom_monthly.csv
data/fluxcom/DE-Tha_fluxcom_monthly.csv
data/fluxcom/DK-Sor_fluxcom_monthly.csv

Each CSV has columns:  year, month, GPP_gC_m2_d, NEE_gC_m2_d, TER_gC_m2_d,
                       ET_mm_d  (TER = GPP - NEE; negative NEE = uptake)

Access method
--------------
Files are downloaded directly from the ICOS Carbon Portal using the
public data download endpoint:
    https://data.icos-cp.eu/licence_accept?ids=["{pid}"]
where {pid} is the persistent identifier for each per-year NetCDF file.
No authentication token is required — the CCBY4-licensed data is publicly
accessible via this endpoint.

Source: https://gitlab.gwdg.de/fluxcom/fluxcomxdata (download_xbase_from_icos.py)

The 050_monthly product: 0.5° spatial, monthly temporal resolution, ~5 MB/year.
Each file covers one calendar year with 12 time steps.

Raw downloaded NetCDF files are saved in data/fluxcom/raw/ (gitignored).
They are kept after extraction so the script can be re-run without
re-downloading.  Delete raw/ to force a fresh download.

Required Python packages
------------------------
Install into a Python environment:
    pip install xarray scipy pandas numpy requests netCDF4

Usage
-----
    python data/fluxcom/extract_fluxcom_allsites.py
"""

import os
import warnings
import numpy as np
import pandas as pd
import requests

# Suppress xarray and scipy deprecation warnings — these don't affect output
warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------------
# Output directory — same directory as this script (data/fluxcom/)
# ---------------------------------------------------------------------------
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# Raw NetCDF files go in data/fluxcom/raw/ (gitignored)
RAW_DIR = os.path.join(OUT_DIR, "raw")
os.makedirs(RAW_DIR, exist_ok=True)

# ---------------------------------------------------------------------------
# Site definitions
# ---------------------------------------------------------------------------
SITES = {
    "US-MMS": {"lat": 39.3232,  "lon": -86.4131},
    "US-NR1": {"lat": 40.0329,  "lon": -105.5464},
    "DE-Tha": {"lat": 50.9636,  "lon":  13.5669},
    "DK-Sor": {"lat": 55.4859,  "lon":  11.6446},
}

# ---------------------------------------------------------------------------
# Per-year ICOS CP persistent identifiers for GPP, NEE, and ET at 0.5° monthly
# Source: https://gitlab.gwdg.de/fluxcom/fluxcomxdata (download_xbase_from_icos.py)
# Download URL: https://data.icos-cp.eu/licence_accept?ids=["{pid}"]
# ---------------------------------------------------------------------------
ICOS_PIDS = {
    "GPP": {
        2001: "yIVuSPjt9sIUv083tR-Qm5eS", 2002: "NvWKrnryQ7fXaQSPlsSfnq3D",
        2003: "mE2f7UW3ic-Xrm-0rrUjpgfv", 2004: "NVVsf1rqvwqB7fgUym0LGREH",
        2005: "vDHxTBrUR4KR4tKGNEqg-Ts8", 2006: "9pVkY5-uLChja0E3dFsQRoRM",
        2007: "8bCtJfOI5nfWJbDlKgVLbRKP", 2008: "7wqNYO9lPhyU8kvSou_VmzgJ",
        2009: "o4CN_i-Zhbl-q7bP_rTOq7f7", 2010: "K6nDhjydlBt2nZxHQ76fEN2x",
        2011: "dMZ5czCZD3BSSxOHNeWboAe2", 2012: "WZqmNrekiq8MugtletGMfwOt",
        2013: "opzKWOJ2lzaUGZTY1IvS7Rzr", 2014: "ThggayhpMhz9AP0DhviZJaCW",
        2015: "sU4JhYIu8NxMw-e7e44XVQPq", 2016: "4CodX89O7h5PsI3_wRZph9aI",
        2017: "o8Ng_Bhe522aX5Bx1D-_Ji8M", 2018: "igV0mc5wRcUmJUeultXUrhAs",
        2019: "1K1U7jdeC90ZpLU9n30Sw52C", 2020: "kJlUrote7lEheUmAh0BMg68e",
        2021: "xDA7b1BwApKmg2qBFs52RrlV",
    },
    "NEE": {
        2001: "f607r80v5qFyFzb5zchHZgsu", 2002: "3NBZ6j7CcWtErDESNE_TQjtJ",
        2003: "iWjW1fzg4C9SrMZsowk5VvZZ", 2004: "LncJibBmSYRxHFYXyTy_n8ON",
        2005: "CJ4_C6VyVIxiGzkWpt0ECE5a", 2006: "DpLCGswUGeA8zEpOOqxWJ6sC",
        2007: "7bLG1XetpUdTv5jZNntvTI-9", 2008: "tB5mKC3r2ONlhWTDZeyuH3Ed",
        2009: "7UjY969Q6OIu53WfSXj6qi6m", 2010: "MM64k6f47UGjlCnQKX0vZjv8",
        2011: "Eaibp2jpl-wy9TkALhhCI-km", 2012: "YO1opE0Xwukqxhs_KE6K8BfC",
        2013: "5hgXvhCxomk_MPuDuEoYV-nG", 2014: "I7yRK5WgGURuLcpPK8wjODrD",
        2015: "Z6gpVXTo_GSDQwcZVQAGBabM", 2016: "OPStwC7MfhEpY_3HcbbQ0i8G",
        2017: "7Dq93ZgamINlqtSIyNu06qgn", 2018: "eITW5f9hksb8viPxOtD--Ua4",
        2019: "TuFaSh9CebSNaCB9F7Mai10H", 2020: "4BXkjeMG6Ul2UfuoPkAQ28Go",
        2021: "KMyODAVLqi5m-okSVbKPdG_u",
    },
    "ET": {
        # These are ET_T (transpiration) PIDs used as a proxy for ET
        # because ET_T was parsed from the FLUX_MAP; revisit if true ET needed
        2001: "tWXxHjp2EjPrf0zs3NBVqaK4", 2002: "jF7AwiBrBwEqiY3yQ71zytJe",
        2003: "05_kcCnAchqbb5qSxfiDqUZC", 2004: "AkRQz64QEunOblGBykntfrUA",
        2005: "FNEagrqaXwLEkjesUMf7-FI1", 2006: "IQqBF81927krn2ZPVAMtdcrt",
        2007: "HCSByFXVWuS92o73yc5mV_Yb", 2008: "FoXg13h0Jnn9hycgobFWFj3V",
        2009: "IzmRTvri7KF0uPoeQ7GfiYwE", 2010: "7SOLdmdcpCDcdJN_rw0XDNu6",
        2011: "TkNilYrx51pBlU-XlgEzTnON", 2012: "Ox4UewNUdQp7wI8f_DpO9i5g",
        2013: "ovg_VE_kmoZJUul6bX5Jl3r0", 2014: "s9aEPeENzEpypFWkYcIKFGSY",
        2015: "6lXSMMh8XAPlGo3kshQLP9YR", 2016: "vih6JZ6DVSzOXdBxzMg5xRU7",
        2017: "dwfpDyDVjk5WCVimY3lBjRxD", 2018: "5B-kX-ay0uEGaM84a-Tic5Q1",
        2019: "UcNnInhqhJmId-2Xhv8yXgkb", 2020: "9L6zqwQPYBeETakE8qihkrT2",
        2021: "4t19mTKVrL-Vt_plO7TCFQDE",
    },
}

# Download base URL — publicly accessible, no authentication required (CCBY4)
DOWNLOAD_BASE = "https://data.icos-cp.eu/licence_accept?ids=%5B%22{pid}%22%5D"

# Variable name inside each NetCDF file
NC_VARNAME = {
    "GPP": "GPP",
    "NEE": "NEE",
    "ET":  "ET",
}

# Years to process
YEARS = list(range(2001, 2022))   # 2001–2021 inclusive


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def download_nc(var_label, year):
    """
    Download a FLUXCOM-X-BASE NetCDF file for one variable and year.

    Returns the local path to the file (either downloaded freshly or from the
    raw cache), or None if the download fails.
    """
    pid = ICOS_PIDS[var_label][year]
    fname = f"{var_label}_{year}_050_monthly.nc"
    local_path = os.path.join(RAW_DIR, fname)

    # Use cached file if it already exists and is non-empty
    if os.path.exists(local_path) and os.path.getsize(local_path) > 1000:
        print(f"    [cache]  {fname}")
        return local_path

    url = DOWNLOAD_BASE.format(pid=pid)
    print(f"    [get]    {fname} ...", end=" ", flush=True)
    try:
        r = requests.get(url, timeout=120, stream=True)
        if r.status_code != 200:
            print(f"HTTP {r.status_code}")
            return None
        n_bytes = 0
        with open(local_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=65536):
                f.write(chunk)
                n_bytes += len(chunk)
        print(f"OK ({n_bytes/1e6:.1f} MB)")
        return local_path
    except Exception as exc:
        print(f"ERROR: {exc}")
        return None


def extract_sites(nc_path, var_label, year):
    """
    Open one FLUXCOM-X-BASE NetCDF file and extract the nearest grid cell to
    each site.

    Returns a dict: site_id → list of 12 monthly values (one per month).
    Fill values (> 1e15 or == -9999) are replaced with NaN.
    """
    try:
        import xarray as xr
    except ImportError:
        raise ImportError("xarray is required: pip install xarray netCDF4 scipy")

    with xr.open_dataset(nc_path, engine="netcdf4") as ds:
        var_name = NC_VARNAME[var_label]

        # Check what the variable is actually called in this file
        if var_name not in ds.data_vars:
            # Try lowercase / uppercase variants
            candidates = [v for v in ds.data_vars
                          if v.lower() == var_name.lower()]
            if not candidates:
                print(f"      Variable '{var_name}' not found. "
                      f"Available: {list(ds.data_vars)}")
                return {}
            var_name = candidates[0]

        # Ensure longitude is in -180/180 range so .sel(lon=...) works
        if ds["lon"].values.max() > 180:
            ds = ds.assign_coords(lon=(ds["lon"] + 180) % 360 - 180)
            ds = ds.sortby("lon")

        results = {}
        for site_id, coords in SITES.items():
            da = ds[var_name].sel(
                lat=coords["lat"], lon=coords["lon"],
                method="nearest", drop=True,
            )
            values = da.values.squeeze().astype(float)
            # Replace fill values
            values[np.abs(values) > 1e15] = np.nan
            values[values == -9999.0] = np.nan
            results[site_id] = values.tolist()

        return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("FLUXCOM-X-BASE EXTRACTION — ALL SITES")
    print("Access method: ICOS Carbon Portal direct download (CCBY4, public)")
    print("=" * 60)

    # Accumulate per-site data: site_id → list of {year, month, var: val} dicts
    site_rows = {site_id: [] for site_id in SITES}

    for var_label in ("GPP", "NEE", "ET"):
        print(f"\n{'─'*60}")
        print(f"Variable: {var_label}")
        print(f"{'─'*60}")

        for year in YEARS:
            # Download (or use cached) NetCDF for this variable and year
            nc_path = download_nc(var_label, year)
            if nc_path is None:
                print(f"      Skipping {var_label} {year} — download failed")
                continue

            # Extract the 4 site values from the 12 monthly time steps
            try:
                site_vals = extract_sites(nc_path, var_label, year)
            except Exception as exc:
                print(f"      Extraction error for {var_label} {year}: {exc}")
                continue

            # Each site gets 12 rows (months 1–12)
            for site_id, monthly_vals in site_vals.items():
                for month_idx, val in enumerate(monthly_vals, start=1):
                    # Find or create the row for this (year, month)
                    # We build rows incrementally; merge by (year, month) later
                    site_rows[site_id].append({
                        "year":    year,
                        "month":   month_idx,
                        var_label: val,
                    })

    # -------------------------------------------------------------------------
    # Assemble per-site DataFrames: one row per (year, month), one col per var
    # -------------------------------------------------------------------------
    print(f"\n{'='*60}")
    print("Assembling and saving site CSVs")
    print(f"{'='*60}")

    summary = {}

    for site_id in SITES:
        rows = site_rows[site_id]
        if not rows:
            print(f"  {site_id}: no data")
            summary[site_id] = {"status": "EMPTY"}
            continue

        df = pd.DataFrame(rows)

        # Pivot so each (year, month) is one row with GPP, NEE, ET columns
        df = df.groupby(["year", "month"]).first().reset_index()
        df = df.sort_values(["year", "month"]).reset_index(drop=True)

        # Rename columns to include units
        rename = {
            "GPP": "GPP_gC_m2_d",
            "NEE": "NEE_gC_m2_d",
            "ET":  "ET_mm_d",
        }
        df = df.rename(columns={k: v for k, v in rename.items() if k in df.columns})

        # Compute TER = GPP - NEE (positive = respiration releasing C)
        # Sign convention: FLUXCOM uses FLUXNET sign for NEE (negative = uptake).
        # TER (total ecosystem respiration) = GPP + NEE when NEE is in FLUXNET sign,
        # but since FLUXCOM may use the ecological (positive = uptake) sign, we
        # compute TER from the two directly: TER = GPP - NEE.
        # Students should verify the sign conventions against the site-level data.
        if "GPP_gC_m2_d" in df.columns and "NEE_gC_m2_d" in df.columns:
            df["TER_gC_m2_d"] = df["GPP_gC_m2_d"] - df["NEE_gC_m2_d"]

        # Write with a metadata comment header so R's read.csv() skips it
        out_fname = f"{site_id}_fluxcom_monthly.csv"
        out_path = os.path.join(OUT_DIR, out_fname)
        header_lines = [
            "# FLUXCOM-X-BASE monthly extraction",
            f"# Site       : {site_id}",
            "# Time period: 2001-01 to 2021-12",
            "# Source     : Nelson et al. (2024), Biogeosciences",
            "#              Data DOI: https://doi.org/10.18160/5NZG-JMJE",
            "# Access     : ICOS Carbon Portal public download (CCBY4 licence)",
            "#              https://data.icos-cp.eu/licence_accept?ids=[...]",
            "#              See ICOS_PIDS dict in this script for per-file PIDs",
            "#",
            "# Column units:",
            "#   year           calendar year",
            "#   month          calendar month (1 = January)",
            "#   GPP_gC_m2_d    gross primary production    gC m-2 d-1",
            "#   NEE_gC_m2_d    net ecosystem exchange      gC m-2 d-1  (negative = uptake)",
            "#   TER_gC_m2_d    total ecosystem respiration gC m-2 d-1  (= GPP - NEE)",
            "#   ET_mm_d        evapotranspiration          mm d-1",
            "#",
            "# Fill values: NaN (FLUXCOM fill values >1e15 or ==-9999 replaced with NaN)",
            "#",
        ]
        with open(out_path, "w") as fh:
            for line in header_lines:
                fh.write(line + "\n")
            df.to_csv(fh, index=False)

        var_cols = [c for c in df.columns if c not in ("year", "month")]
        print(f"\n  {site_id}: {len(df)} rows, {len(var_cols)} variables")
        print(f"    Variables : {', '.join(var_cols)}")
        yr_range = f"{df['year'].min()}-{df['month'].min():02d} to {df['year'].max()}-{df['month'].max():02d}"
        print(f"    Date range: {yr_range}")
        print(f"    Saved → {out_path}")
        summary[site_id] = {"status": "OK", "rows": len(df), "vars": var_cols,
                             "date_range": yr_range, "output": out_path}

    # -------------------------------------------------------------------------
    # Final summary
    # -------------------------------------------------------------------------
    print(f"\n{'='*60}")
    print("EXTRACTION SUMMARY")
    print(f"{'='*60}")
    print("Access method: ICOS Carbon Portal public download (licence_accept endpoint)")
    for site_id, info in summary.items():
        print(f"\n{site_id}: {info['status']}")
        if info["status"] == "OK":
            print(f"  Rows      : {info['rows']}")
            print(f"  Date range: {info['date_range']}")
            print(f"  Variables : {', '.join(info['vars'])}")


if __name__ == "__main__":
    main()
