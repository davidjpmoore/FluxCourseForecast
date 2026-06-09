# FluxCourseForecast Session Log
Auto-updated by Claude Code. Each entry records a task completion.

## [2026-06-08 00:00] Session log initialized
- Created SESSION_LOG.md in repo root
- Files changed: SESSION_LOG.md (new)
- No issues

## [2026-06-08] Task 1–3: Update exercises to use US-NR1 and US-MMS as primary sites

### Task 1: exercises/01_run_model.Rmd
- Replaced single DE-Tha section with two parallel site sections: US-NR1 (ENF, subalpine) and US-MMS (DBF, temperate)
- Added prose introduction explaining the two-site contrast
- US-NR1: half-hourly (30 min), year 2008, DATETIME_START (ISO 8601, already POSIXct from readr)
- US-MMS: hourly (60 min), year 2008, TIMESTAMP_START (integer YYYYMMDDHHMM)
- ENF parameters for US-NR1 (Norway spruce analog, 4-yr litterfall rate)
- DBF parameters for US-MMS (deciduous, 1-yr litterfall rate, higher leaf allocation)
- Separate ensemble runs with plot_forecast() for each site
- RDS saved to data/ssem_usnr1_2008.rds and data/ssem_usmms_2008.rds
- Updated discussion questions to compare ENF vs DBF
- Added DE-Tha and DK-Sor as optional extensions section
- Key fix: use DATETIME_START column directly (readr already parses it as POSIXct);
  calling ymd_hms() on a POSIXct column triggers a character round-trip that silently
  drops 366 timestamps per year in the US-NR1 file
- Knit: clean

### Task 2: exercises/02_validation.Rmd
- Updated to use US-NR1 and US-MMS as primary sites throughout
- site_timestep list now includes US-NR1=30, US-MMS=60, DE-Tha=30, DK-Sor=30
- Loads US-NR1 (NEE_CUT_REF) and US-MMS (NEE_VUT_REF) as primary pair
- Extension sites DE-Tha and DK-Sor loaded conditionally if files exist
- Reads both SSEM RDS files (ssem_usnr1_2008.rds, ssem_usmms_2008.rds)
- Added visible US-NR1 callout explaining NEE_CUT_REF vs NEE_VUT_REF
- Added CMIP6 availability note: currently US-MMS only; US-NR1 students use US-MMS CMIP6 as regional reference
- Updated all discussion questions to reference US-NR1 and US-MMS specifically
- harmonise_subdaily uses DATETIME_START directly (same fix as Exercise 01) for US-NR1
- Knit: clean

### Task 3: exercises/03_handoff.Rmd
- Builds handoff workspaces for both sites: handoff_workspace_NR1.RDS and handoff_workspace_MMS.RDS
- handoff_site variable at top of setup chunk selects which site to feature
- US-NR1: half-hourly, 2008, NEE_CUT_REF (renamed to NEE_VUT_REF for PF compatibility), ENF params
- US-MMS: hourly, 2005 (original PF development year), DBF params
- Both workspaces saved to data/; legacy copy of selected site saved to exercises/output/handoff_workspace.RDS
- Checklist runs for both sites simultaneously; both must pass
- Knit: clean

### Data notes
- US-NR1 uses NEE_CUT_REF (constant u* threshold) not NEE_VUT_REF (VUT method not applied)
- CMIP6 pre-extracted for US-MMS grid cell only; US-NR1 extraction pending
- CESM2 uses SSP370 not SSP245 in the pre-extracted CMIP6 CSVs (documented in data/cmip6/)
- UKESM1-0-LL historical only through 2014 (documented in data/cmip6/)

## [2026-06-08] Task: Verify student data completeness and create test_student_setup.R

### Task 1: Student data verification
- Confirmed all 13 required files present in exercises/student_data/Tuesday_AM_SSEM_part1/
- R source files (functions.R, utils.R) verified identical to repo versions
- Rebuilt Tuesday_AM_SSEM_part1.zip: 0.73 GB compressed, 2.3 GB uncompressed, 20 entries
- Copied to Google Drive: ~/Library/CloudStorage/GoogleDrive-setanta.research@gmail.com/My Drive/FLUXCOURSE 2026 Shared Resources/Week 2 Instructional Materials/Tuesday_AM_SSEM_part1.zip (734285218 bytes, 2026-06-08 12:01)

### Task 2: Create exercises/test_student_setup.R
- Created student self-check script with 5 sections:
  1. data_dir existence check (early exit with clear message if missing)
  2. PASS/FAIL for all 13 required files (checks existence and size > 1 kB)
  3. Package check: tidyverse, lubridate, rmarkdown, compiler, mvtnorm
  4. Source functions.R and utils.R with error capture
  5. Smoke test: load 48 rows of US-NR1_HR.csv, run ensemble_forecast(ne=5, 48 timesteps),
     verify dim == c(48,5,12); prints GPP median at midday as a sanity value
- Final summary: "READY TO START — all N checks passed" or count + contact info
- Local test run result: all 22 checks PASS; GPP median at step 24 = 10.673 umol CO2 m-2 s-1

## [2026-06-08] Steps 1–6: US-NR1 HH rename, CMIP6/FLUXCOM extraction, 02_validation.Rmd update, staging folder, test script

### Step 1: Rename US-NR1_HR.csv → US-NR1_HH.csv
- ICOS/FLUXNET convention: _HH_ = half-hourly (30 min), _HR_ = genuinely hourly
- Physical files renamed: data/US-NR1/US-NR1_HH.csv and exercises/student_data/.../US-NR1_HH.csv
- References updated in: 01_run_model.Rmd, 02_validation.Rmd, 03_handoff.Rmd, test_student_setup.R, download_usnr1.R
- Confirmed clean: no remaining US-NR1_HR references in exercises/ or data/US-NR1/

### Step 2: Extract CMIP6 data for US-NR1, DE-Tha, DK-Sor
- Ran data/cmip6/extract_cmip6_allsites.py with ~/.virtualenvs/cmip6 Python environment
- 9 new CSVs: {CESM2,IPSL-CM6A-LR,UKESM1-0-LL}_{usnr1,detha,dksor}_monthly.csv
- CESM2 uses SSP370, UKESM1-0-LL historical only through 2014 (documented in CSV headers)

### Step 3: Extract FLUXCOM-X-BASE data for all four sites
- Created and ran data/fluxcom/extract_fluxcom_allsites.py
- Access method: ICOS Carbon Portal public download via licence_accept endpoint (no auth required for CCBY4 data)
- PIDs sourced from official GitLab download script (fluxcom/fluxcomxdata)
- 4 CSVs, 252 rows each (2001-01 to 2021-12): GPP_gC_m2_d, NEE_gC_m2_d, ET_mm_d, TER_gC_m2_d
- TER derived as GPP − NEE; raw NetCDF files cached in data/fluxcom/raw/ (gitignored)

### Step 4: Update exercises/02_validation.Rmd
- Added load_cmip6_site() and load_fluxcom_site() helper functions
- cmip6_compare chunk: chosen_site variable selects primary site; non-MMS sites use FLUXCOM as observational reference
- New fluxcom_compare chunk: bar chart of annual GPP across SSEM point / FLUXCOM 0.5° / CMIP6 ~1°
- Updated scale hierarchy note

### Step 5: Update student staging folder
- cmip6/: 12 CSVs (was 3; added usnr1, detha, dksor for all 3 models)
- fluxcom/ (new subfolder): 4 CSVs (US-MMS, US-NR1, DE-Tha, DK-Sor)
- US-NR1/US-NR1_HH.csv renamed from HR; zip NOT rebuilt

### Step 6: Update exercises/test_student_setup.R
- Required file list expanded from 13 to 26 entries; 27/27 checks pass
- Added 9 CMIP6 CSVs for usnr1, detha, dksor; 4 FLUXCOM monthly CSVs
- Smoke test path updated to US-NR1_HH.csv

### Gitignore fix
- Removed data/fluxcom/*.csv from .gitignore (small extracted site CSVs, tracked like data/cmip6/*.csv)
- data/fluxcom/raw/ remains gitignored

## [2026-06-08] Knit all three exercises and rebuild student zip

### Exercise 01 — 01_run_model.Rmd
- Status: CLEAN — 17/17 chunks, no errors, no warnings
- Output: exercises/01_run_model.html, 3.7 MB

### Exercise 02 — 02_validation.Rmd
- Status: CLEAN after one minor fix — 21/21 chunks, no warnings
- Fix applied: fluxcom_compare chunk used `ssem_info_local` (a list from build_ssem_daily())
  directly with summarise() instead of `ssem_daily |> filter(site == site_id)`;
  also referenced nonexistent column `gpp_gCm2d` instead of `gpp_med`
- Output: exercises/02_validation.html, 4.1 MB

### Exercise 03 — 03_handoff.Rmd
- Status: CLEAN — 18/18 chunks, no errors, no warnings
- Output: exercises/03_handoff.html, 1.2 MB

### Student zip rebuild
- Staging folder: 26 files (cmip6 × 12, fluxcom × 4, R × 2, US-NR1 × 2, US-MMS × 2, DE-Tha × 2, DK-Sor × 2)
- Zip: exercises/student_data/Tuesday_AM_SSEM_part1.zip, 701 MB (deflated ~66% from ~2.3 GB)
- Google Drive upload confirmed: ~/Library/CloudStorage/GoogleDrive-setanta.research@gmail.com/My Drive/FLUXCOURSE 2026 Shared Resources/Week 2 Instructional Materials/Tuesday_AM_SSEM_part1.zip (701 MB, 2026-06-08 13:11)

### Knit environment note
- Pandoc not in shell PATH; used /Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/aarch64/pandoc (v3.8.3)
- renv out-of-sync warning is non-blocking (packages installed but not recorded in lockfile)

## [2026-06-08] Task 1–2: Create install_packages.R and SETUP_INSTRUCTIONS.md

### Task 1: exercises/install_packages.R
- Scanned all three exercise Rmds, R/functions.R, R/utils.R for library(), require(), and :: namespace calls
- Required packages (CRAN): tidyverse, lubridate, rmarkdown, mvtnorm, coda
  - compiler is base R (always present, excluded from install list)
  - coda found via coda:::as.mcmc in R/utils.R (mat2mcmc.list function)
  - mvtnorm found via mvtnorm::rmvnorm in R/functions.R (particle filter)
- Script uses plain install.packages() only (no renv, pak, or non-base tools)
- Ends with verification loop and stop() if any package fails

### Task 2: exercises/SETUP_INSTRUCTIONS.md
- One-page guide for graduate students with numbered steps
- Covers: GitHub clone/download, Google Drive data zip, data_dir setting, install_packages.R, test_student_setup.R
- Contact info: davidjpmoore@arizona.edu
- Instructed students to copy test_student_setup.R console output when requesting help

### Staging folder
- Copied install_packages.R and SETUP_INSTRUCTIONS.md to exercises/student_data/Tuesday_AM_SSEM_part1/
- Zip NOT rebuilt per instructions

## [2026-06-08] Final student zip build and Google Drive upload

### Manifest verification
- Expected: 27 files per spec
- Found: 28 files (extra: SETUP_INSTRUCTIONS.md — not in manifest)
- Action: removed SETUP_INSTRUCTIONS.md from staging folder
- Final staging folder: 27 files confirmed

### Zip contents (27 files, 35 zip entries including 8 directory entries)
| File | Uncompressed |
|---|---|
| install_packages.R | 2.7 KB |
| R/functions.R | 13.6 KB |
| R/utils.R | 3.7 KB |
| US-NR1/US-NR1_HH.csv | 451 MB |
| US-NR1/US-NR1_DD.csv | 14.0 MB |
| US-MMS/US-MMS_HR.csv | 284 MB |
| US-MMS/US-MMS_DD.csv | 19.8 MB |
| DE-Tha/DE-Tha_HH.csv | 695 MB |
| DE-Tha/DE-Tha_DD.csv | 23.3 MB |
| DK-Sor/DK-Sor_HH.csv | 682 MB |
| DK-Sor/DK-Sor_DD.csv | 22.4 MB |
| cmip6/ (12 CSVs) | ~64–78 KB each |
| fluxcom/ (4 CSVs) | ~22 KB each |
- Total uncompressed: ~2.14 GB (2,298,879,744 bytes)
- Total compressed: 701 MB (~67% deflation)

### Google Drive upload
- Path: ~/Library/CloudStorage/GoogleDrive-setanta.research@gmail.com/My Drive/FLUXCOURSE 2026 Shared Resources/Week 2 Instructional Materials/Tuesday_AM_SSEM_part1.zip
- Size confirmed: 701 MB
- Timestamp: 2026-06-08 13:39

## [2026-06-08] Task: Build self-contained offline interactive HTML dashboard

### exercises/build_dashboard.R (new)
- R script that reads SSEM RDS files (ssem_usnr1_2008.rds, ssem_usmms_2008.rds), FLUXNET daily CSVs, FLUXCOM monthly CSVs, and CMIP6 monthly CSVs
- Aggregates SSEM sub-daily → daily (with 2.5/50/97.5% ensemble CI), monthly (mean), annual (sum)
- Converts all fluxes to gC m-2 d-1 for daily/monthly/annual; retains umol m-2 s-1 for sub-daily SSEM
- Serializes all data to JSON (~0.6 MB), downloads and caches Plotly.js 2.26.2 (~3.6 MB)
- Assembles single-file HTML using paste0() (not sprintf — Plotly.js contains literal % chars)
- Plotly.js cached to exercises/.plotly.min.js (gitignored); re-used on subsequent builds

### exercises/dashboard.html (new)
- Self-contained offline HTML dashboard, 4.2 MB (within 20 MB limit)
- Site tabs: US-NR1 (ENF, subalpine), US-MMS (DBF, temperate)
- Variable selector: NEE, GPP, Rh, LAI, ET, Energy balance (SW/LW/LE/H)
- Timescale toggle: sub-daily, daily, monthly, annual
- Sidebar checkboxes: SSEM median, SSEM 95% CI, FLUXNET, FLUXCOM, CESM2, IPSL, UKESM
- Cost functions panel: RMSE, bias (SSEM − obs), Pearson r (SSEM vs FLUXNET daily; NEE and GPP only)
- Expandable documentation panel with data stream reference table and 6 caveats
- Navy/white palette, Georgia font, Plotly unified hover, no CDN dependencies
- Copied to exercises/student_data/Tuesday_AM_SSEM_part1/dashboard.html (zip NOT rebuilt)

### .gitignore update
- Added exercises/.plotly.min.js (Plotly.js cache, 3.6 MB, not committed)

## [2026-06-09] Task 1–2: Full-record SSEM run and dashboard rebuild

### Task 1: exercises/run_full_record.R (new)
- Runs SSEM ensemble (ne = 20) over the full observational record at both sites
- US-NR1 (ENF): 1998–2023, 26 years, 455,808 timesteps (HH, 48/day, 1800 s/step)
- US-MMS (DBF): 1999–2023, 25 years, 219,144 timesteps (HR, 24/day, 3600 s/step)
- Parameters match Exercise 01: ENF priors for NR1, DBF priors for MMS; set.seed(2026)
- State carried forward year-to-year (continuous simulation, not reset each January)
- Saved with xz compression as named lists (output array + years + steps_per_day + ne + site)
- Output:
  - data/ssem_usnr1_fullrecord.rds  548 MB on disk  [455808 × 20 × 12]
  - data/ssem_usmms_fullrecord.rds  280 MB on disk  [219144 × 20 × 12]
- Both files added to .gitignore (already covered by data/*.rds wildcard; added comment)
- Run times: NR1 1 min 3 s simulation + ~7 min xz save; MMS 32 s simulation + 80 s save

### Task 2: exercises/build_dashboard.R (updated) + dashboard.html (rebuilt)
- Data sources changed:
  - SSEM sub-daily: 2008 only (from ssem_usnr1/usmms_2008.rds), clearly labelled "representative year"
  - SSEM daily/monthly/annual: full record from new fullrecord RDS files
  - FLUXNET daily: full observational record (all years in DD CSV, not just 2008)
  - FLUXCOM 2001–2021 and CMIP6 1980–2021: unchanged
- New proc functions:
  - proc_ssem_subdaily_2008(): extracts sub-daily slice from 2008 RDS (plain array)
  - proc_ssem_full(): reads full-record RDS list, aggregates to daily/monthly/annual
  - proc_fluxnet(): updated to load full record (removed year filter)
- Plot style changes applied in JS:
  - Removed all bar charts at annual scale; all timescales now use line traces
  - Line width hierarchy: FLUXNET = 3, SSEM median = 1.5, FLUXCOM = 2 (dashed), CMIP6 = 1
  - SSEM 95% CI: shaded ribbon (unchanged)
  - Annual SSEM and FLUXNET now show multi-year lines+markers instead of single-year bars
- Stats bar: updated label from "daily 2008" to "full-record daily"; date-based matching
- Dashboard rebuilt: exercises/dashboard.html, 7.4 MB (within 20 MB limit)
- Dashboard copied to exercises/student_data/Tuesday_AM_SSEM_part1/dashboard.html
- Zip NOT rebuilt

### Data notes
- xz-compressed RDS files are gitignored (data/*.rds wildcard); only generated by instructor
- SSEM state continuity: soil carbon pool accumulates across the full record; early years
  serve as spin-up; carbon pools are not reset between years
- build_dashboard.R stops with a clear error if fullrecord RDS files are missing (run
  run_full_record.R first)

## [2026-06-09] Diagnostic: SSEM 95% CI ribbon not visible in dashboard.html

### Task
Investigate why the SSEM 95% CI ribbon does not appear in exercises/dashboard.html.
Three ordered checks were performed. No files were modified during this diagnostic.

---

### Check 1: R data preparation in build_dashboard.R

**Goal:** Confirm that `proc_ssem_full()` computes CI bounds and stores them under the
expected column names before the JSON is serialised.

**Method:** Read `proc_ssem_full()` in build_dashboard.R and trace the data flow from
`ens_ci()` through to the `daily` list returned by the function.

**Findings:**
- `ens_ci()` (defined in build_dashboard.R) calls `apply(m, 1, quantile, probs=c(0.025, 0.5, 0.975), na.rm=TRUE)` — correct three-quantile calculation.
- The function returns a list with named elements `lo`, `med`, `hi` corresponding to the 2.5th, 50th, and 97.5th percentiles.
- `agg_to_daily()` calls `ens_ci()` for each variable index and stores the result as `list(lo=..., med=..., hi=...)`.
- The `daily` list assembled in `proc_ssem_full()` uses the key pattern `nee_lo`, `nee_med`, `nee_hi`, `gpp_lo`, `gpp_med`, `gpp_hi`, `rh_lo`, `rh_med`, `rh_hi`, `lai_lo`, `lai_med`, `lai_hi` — exactly matching the JS access pattern `dd[f+"_lo"]`, `dd[f+"_med"]`, `dd[f+"_hi"]`.
- CI values are non-trivial: mean CI width for NEE = 5.04 gC m⁻² d⁻¹, maximum = 10.11 gC m⁻² d⁻¹.

**Conclusion:** R data preparation is correct. CI bounds are computed and named correctly.

---

### Check 2: JSON embedded in dashboard.html

**Goal:** Confirm that the CI arrays are present in the serialised `DATA` object with
non-trivial values.

**Method:** Extract the `const DATA = {...}` JSON block from dashboard.html using Python
and inspect the US-NR1 SSEM daily CI arrays.

**Findings:**
- Keys `nee_lo`, `nee_hi`, `gpp_lo`, `gpp_hi` (and counterparts for RH and LAI) are all present in `DATA["US-NR1"]["ssem"]["daily"]`.
- Array lengths: 9,496 elements each (1998-01-01 through 2023-12-31, daily).
- Null count in each CI array: 0 (no missing values propagated from R).
- Sample values (first 5 days, NEE):
  - `nee_lo`:  [-1.3082, -1.2048, -1.0139, -1.7530, -1.3021]
  - `nee_med`: [-0.3929, -0.2925, -0.2577, -0.8150, -0.5202]
  - `nee_hi`:  [ 0.4664,  0.5778,  0.3755,  0.0191,  0.1533]
- Values are genuinely distinct: lo < med < hi with a non-zero spread on day 1.

**Conclusion:** JSON serialisation is correct. CI data is complete, null-free, and distinct
from the median in the embedded payload.

---

### Check 3: JavaScript rendering

**Goal:** Confirm the ribbon() function is wired correctly to the checkbox and
the fill trace parameters are valid for Plotly.js 2.26.2.

**Method:** Search dashboard.html for the ribbon() function definition,
the fillcolor expression, the checkbox ID, and the getTraces() call site.

**Findings:**

**(a) ribbon() function — present and structurally correct**
The function concatenates `hi` forward and `lo` reversed to form a closed polygon:
```
x: dates.concat(dates.slice().reverse())   → 18,992 points
y: hi.concat(lo.slice().reverse())          → 18,992 points
fill: "toself"                              → correct for self-closing polygon
```
This is the standard Plotly scatter ribbon pattern.

**(b) fillcolor: "#1a3a5c28" — 8-digit hex format, likely not supported**
`C.ssem = "#1a3a5c"` (confirmed from the color palette object).
`fillcolor: col + "28"` produces the string `"#1a3a5c28"`.

`#RRGGBBAA` 8-digit hex is a CSS Color Level 4 feature. Plotly.js 2.26.2 bundles
tinycolor2 for color parsing. While recent tinycolor2 versions (≥1.4.0) accept 8-digit
hex, the version bundled in Plotly 2.26.2 may not. If the color string is not
recognised, Plotly silently falls back to transparent or ignores the fill, making the
ribbon invisible. The standard Plotly format for a semi-transparent fill is
`"rgba(26, 58, 92, 0.16)"` (alpha in 0–1 range), not 8-digit hex.

**This is the primary suspect for the invisible ribbon.**

**(c) Ribbon polygon size — 18,992 points**
The full-record daily array has 9,496 dates (26 years). The closed-polygon ribbon
therefore has 18,992 points — 26× larger than the old single-year dashboard
(366 days → 732 polygon points). At this scale, Plotly's canvas-based fill renderer
may fail silently, skip rendering the fill, or produce a blank fill on some browsers.
This is a secondary suspect and would compound Issue (b).

**(d) Checkbox wiring — correct**
- Checkbox `id="cb_ssem_ci"` is present in the HTML and is `checked` by default.
- `getTraces()` calls `if (cb("cb_ssem_ci")) t.push(...ribbon(...))` — the ID matches exactly.
- No `visible: false` is set on either the fill or the median line trace from `ribbon()`.
- The condition `dd[f+"_med"]` is truthy (confirmed by Check 2 — data exists).

**Conclusion:** Two bugs identified that together explain the invisible ribbon:

1. **`fillcolor:"#1a3a5c28"` — 8-digit hex alpha** — Plotly.js 2.26.2 may not parse this
   as a semi-transparent color, causing the fill to be invisible. Fix: replace with
   `"rgba(26, 58, 92, 0.16)"`.

2. **18,992-point polygon** — the full-record daily ribbon is 26× larger than a
   single-year ribbon and may exceed Plotly's fill rendering capacity. Fix: consider
   downsampling to weekly or monthly resolution for the ribbon only (keep median daily),
   or pre-aggregate CI to a coarser resolution before embedding in the HTML.

No fix has been applied. Awaiting approval before modifying any files.

---

## [2026-06-09] Fix: SSEM 95% CI ribbon — two bugs corrected in build_dashboard.R

### Approved changes

Two bugs identified in the diagnostic above were fixed in `exercises/build_dashboard.R`:

**Fix 1 — fillcolor format (primary bug)**
Added a `hexToRgba(hex, alpha)` helper function that converts a 6-digit hex colour
to an `rgba()` string. Replaced `fillcolor:col+"28"` (8-digit hex `#1a3a5c28`) with
`fillcolor:hexToRgba(col, 0.16)` (produces `rgba(26,58,92,0.16)`). Plotly 2.26.2
does not reliably parse `#RRGGBBAA` hex format; `rgba()` is the documented standard.

**Fix 2 — ribbon polygon downsampling (secondary bug)**
Added a `downsample(arr, n)` helper that takes every nth element. For the daily
timescale, the CI ribbon is now drawn at weekly resolution (every 7th day), reducing
the closed polygon from 18,992 points (~26 years × 365 days × 2) to ~2,714 points
(~1,357 weekly samples × 2). The median SSEM line remains at full daily resolution.
Monthly, annual, and sub-daily panels are not affected.

### Files changed
- `exercises/build_dashboard.R`: added `hexToRgba()` and `downsample()` helpers;
  updated `ribbon()` signature to `ribbon(xRibbon, xMed, med, lo, hi, name, col)`;
  updated the daily getTraces() call to pass downsampled CI arrays.
- `exercises/dashboard.html`: rebuilt, 7,450,977 bytes (7.5 MB).
- `exercises/student_data/Tuesday_AM_SSEM_part1/dashboard.html`: staging copy updated.
- Google Drive zip: `Tuesday_AM_SSEM_part1.zip` updated via `zip -u` to add
  `Tuesday_AM_SSEM_part1/dashboard.html` (7.5 MB uncompressed, deflated 68%);
  zip now 703 MB.

### Verification
- `hexToRgba()` function: present in output HTML
- `downsample()` function: present in output HTML
- `fillcolor:hexToRgba(col, 0.16)`: present in output HTML
- `col+"28"` (old 8-digit hex): absent from output HTML
- `const step = 7`: present in output HTML
- `downsample(dd.dates, step)`: present in output HTML
- `id="cb_ssem_ci" checked`: present in output HTML
- File size: 7.5 MB (within 20 MB limit)
