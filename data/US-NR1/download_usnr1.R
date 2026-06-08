## download_usnr1.R
## ----------------
## Downloads, extracts, reads, and summarises the US-NR1 AmeriFlux FLUXNET
## FULLSET record for Niwot Ridge, Colorado.
##
## US-NR1 (ENF, lat 40.03, lon -105.55, elevation ~3050 m asl) is a subalpine
## conifer forest dominated by Engelmann spruce (Picea engelmannii), subalpine
## fir (Abies lasiocarpa), and lodgepole pine (Pinus contorta).  The site has
## one of the longest continuous eddy covariance records in the AmeriFlux
## network (1998–present) and is the primary validation site in Mike Dietze's
## FluxCourseForecast exercises.  The subalpine setting means a short growing
## season (roughly June–September) with frequent summer afternoon convection,
## substantial winter CO₂ efflux under snowpack, and elevation-dependent
## radiation loading that makes the site useful for testing model responses to
## extreme light and temperature conditions.
##
## Run once before Fluxcourse exercises that use US-NR1 data.
## Before running, set:
##   export RETICULATE_PYTHON=~/.virtualenvs/fluxnet/bin/python
## in your shell, or add to ~/.Renviron:
##   RETICULATE_PYTHON=~/.virtualenvs/fluxnet/bin/python
##
## fluxnet package API (v0.3.2) key notes:
##   flux_download()       → download_dir argument
##                           BUG: fails if site ZIP already exists in download_dir
##                           (workaround: skip call if ZIP present, see §6)
##   flux_extract()        → zip_dir, output_dir arguments
##                           v0.3.2 fix: correctly extracts _HR_ files from
##                           AmeriFlux FLUXNET v1.3_r1 products (was silently
##                           skipping them in v0.3.1 by matching only "_HH_")
##   flux_discover_files() → data_dir argument; returns tibble with columns:
##                           path, dataset, time_resolution, site_id, ...
##   flux_read()           → takes manifest tibble + resolution ("y","m","w","d","h")
##                           + datasets ("FLUXMET","ERA5") arguments.
##                           Returns a SINGLE tibble (not a list).
##                           Already replaces -9999 with NA.
##                           Renames timestamp cols:
##                             YY: TIMESTAMP → YEAR (integer)
##                             MM/DD: TIMESTAMP → DATE (Date)
##                             WW: TIMESTAMP_START/END → DATE_START/DATE_END
##                             HR/HH: TIMESTAMP_START/END → DATETIME_START/DATETIME_END
##   flux_badm()           → reads BIF metadata; takes manifest + site_ids
##
## NOTE on sub-daily naming: AmeriFlux FLUXNET v1.3_r1 products use "_HR_" in
##   file names for the sub-daily (hourly) product; older FLUXNET2015 products
##   use "_HH_" for half-hourly (30-min) data.  The manifest time_resolution
##   label ("HR" vs "HH") tells you which convention this download used.
##   The discovery step in §8 will print the actual label; the RES_MAP in §9
##   is initialised to expect "HR" but the output filename is always written as
##   "US-NR1_HH.csv" to follow the ICOS/FLUXNET half-hourly convention and
##   to distinguish the 30-min data from the US-MMS hourly (_HR_) product.
##
## Product version downloaded: AMF_US-NR1_FLUXNET_1998–YYYY_v1.3_r1 (or latest)
##   Available resolutions: HR (or HH), DD, WW, MM, YY  (FLUXMET + ERA5)
##   ERA5 extends back to 1981 (full reanalysis period).
##
## Prerequisites
## -------------
##   R 4.4+, Python 3.11–3.13 (not 3.14+)
##   AMERIFLUX_USER_NAME / AMERIFLUX_USER_EMAIL / AMERIFLUX_INTENDED_USE
##   in ~/.Renviron (required for AmeriFlux attribution and download access).

## ==========================================================================
## 0. Directories
## ==========================================================================
## All paths are relative to the repository root (run with setwd() or
## Rscript from there).  raw/ and raw/unzipped/ are gitignored; processed
## CSVs in data/US-NR1/ are git-tracked.

out_dir   <- file.path("data", "US-NR1")   ## processed CSVs go here
raw_dir   <- file.path(out_dir, "raw")      ## downloaded ZIPs (gitignored)
unzip_dir <- file.path(raw_dir, "unzipped") ## extracted files (gitignored)

dir.create(out_dir,   showWarnings = FALSE, recursive = TRUE)
dir.create(raw_dir,   showWarnings = FALSE, recursive = TRUE)
dir.create(unzip_dir, showWarnings = FALSE, recursive = TRUE)

## ==========================================================================
## 1. Install / load fluxnet package (pinned to v0.3.2)
## ==========================================================================
## pak::pak() installs from GitHub at the specified tag.  v0.3.2 is the
## first release that correctly extracts _HR_ files via flux_extract().

if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
message("Installing EcosystemEcologyLab/fluxnet-package @ v0.3.2 …")
pak::pak("EcosystemEcologyLab/fluxnet-package@v0.3.2")

library(fluxnet)
library(tidyverse)
library(lubridate)

## ==========================================================================
## 2. Verify Python version WITHOUT initialising a reticulate session
## ==========================================================================
## CRITICAL: Do not call library(reticulate), use_python(), or py_config()
## before flux_install_shuttle().  Those calls lock reticulate into a
## specific interpreter.  flux_install_shuttle() must be the FIRST Python
## initialisation so use_virtualenv("fluxnet") takes effect correctly.

py_candidates <- c(
  Sys.which("python3.12"), Sys.which("python3.11"), Sys.which("python3.13"),
  "/usr/bin/python3.12", "/usr/bin/python3.11", Sys.which("python3")
)
py_exe <- py_candidates[nzchar(py_candidates) & file.exists(py_candidates)][1]
if (is.na(py_exe)) stop("No Python executable found.  Install Python 3.11–3.13.")

py_ver_str <- tryCatch(
  system2(py_exe, "--version", stdout = TRUE, stderr = TRUE),
  error = function(e) character(0)
)
if (!length(py_ver_str)) stop("Could not query Python version from: ", py_exe)
message("Python found: ", py_exe, "  →  ", py_ver_str[1])

ver_match <- regmatches(py_ver_str[1], regexpr("\\d+\\.\\d+", py_ver_str[1]))
ver_parts  <- as.integer(strsplit(ver_match, "\\.")[[1]])
if (!(ver_parts[1] == 3L && ver_parts[2] >= 11L && ver_parts[2] <= 13L)) {
  stop("fluxnet-shuttle needs Python 3.11–3.13, detected: ", ver_match)
}
message("Python version OK (", ver_match, ")")

## ==========================================================================
## 3. Install fluxnet-shuttle Python library
## ==========================================================================
## Creates (or reuses) the "fluxnet" virtualenv and installs fluxnet-shuttle.
## Must be called before any other fluxnet function touches Python.

message("Setting up fluxnet-shuttle Python environment …")
flux_install_shuttle()
message("fluxnet-shuttle ready.")

## ==========================================================================
## 4. AmeriFlux attribution (required for AmeriFlux sites)
## ==========================================================================
## US-NR1 is an AmeriFlux core site; attribution variables must be set in
## ~/.Renviron before running.  The download will proceed without them but
## AmeriFlux requires attribution for data reuse — add them if not present.

for (v in c("AMERIFLUX_USER_NAME", "AMERIFLUX_USER_EMAIL",
            "AMERIFLUX_INTENDED_USE")) {
  if (!nzchar(Sys.getenv(v)))
    message("NOTE: ", v, " not set — add to ~/.Renviron for AmeriFlux attribution.")
}

## ==========================================================================
## 5. Confirm US-NR1 is in the AmeriFlux site manifest
## ==========================================================================
## flux_listall() queries the AmeriFlux API and returns a row per registered
## site.  first_year / last_year are manifest-reported; the actual downloaded
## record may differ (ERA5 extends further back than the tower).

message("\nQuerying AmeriFlux site catalogue …")
site_manifest <- flux_listall()
usnr1_meta    <- dplyr::filter(site_manifest, site_id == "US-NR1")

if (nrow(usnr1_meta) == 0) stop("US-NR1 not found in the AmeriFlux manifest.")

cat("\n--- US-NR1 manifest entry ---\n")
print(usnr1_meta)
cat(sprintf("\nManifest record span: %s – %s\n",
            usnr1_meta$first_year, usnr1_meta$last_year))

## ==========================================================================
## 6. Download the full record
## ==========================================================================
## flux_download() has a bug in v0.3.1 (still present in v0.3.2): it filters
## already-downloaded ZIPs out of the snapshot before passing to the Python
## shuttle, causing the shuttle to raise FLUXNETShuttleError when the site is
## already present in download_dir.  Workaround: skip the call when the ZIP
## exists — the existing file is complete.

existing_zips <- list.files(raw_dir, pattern = "\\.zip$", full.names = TRUE)

if (length(existing_zips) > 0) {
  message("\nExisting ZIP(s) found — skipping download:")
  message("  ", paste(basename(existing_zips), collapse = "\n  "))
} else {
  message("\nDownloading US-NR1 FULLSET data (this may take several minutes) …")
  flux_download(site_ids = "US-NR1", download_dir = raw_dir)
  message("Download complete.")
}

## ==========================================================================
## 7. Extract ZIPs
## ==========================================================================
## flux_extract() in v0.3.2 correctly handles _HR_ files (the v0.3.1 bug
## that silently skipped sub-daily files by searching only for "_HH_" is
## fixed).  All resolutions (HR, DD, WW, MM, YY, BIF) will be extracted.

message("\nExtracting ZIP files …")
flux_extract(zip_dir = raw_dir, output_dir = unzip_dir)
message("Extraction complete.")

## ==========================================================================
## 8. Discover extracted files
## ==========================================================================
## flux_discover_files() scans unzip_dir and returns a tibble with one row
## per file, including the time_resolution label (e.g. "HR", "DD", "WW").
## Printing the manifest here lets you verify what was actually delivered
## before committing to reading it.

message("\nDiscovering extracted files …")
file_manifest <- flux_discover_files(data_dir = unzip_dir)

cat("\n--- File manifest ---\n")
print(file_manifest)

## Which resolutions are actually present for each dataset?
avail <- file_manifest |>
  dplyr::filter(dataset %in% c("FLUXMET", "ERA5")) |>
  dplyr::select(dataset, time_resolution) |>
  dplyr::distinct() |>
  dplyr::arrange(dataset, time_resolution)
cat("\nAvailable dataset × resolution combinations:\n")
print(as.data.frame(avail))

## ==========================================================================
## 9. Read all available FLUXMET and ERA5 resolutions (discovery-driven)
## ==========================================================================
## flux_read() returns a SINGLE tibble (not a list).  It already replaces
## -9999 with NA and renames timestamp columns by resolution:
##   YY  → YEAR (integer)
##   MM/DD → DATE (Date)
##   WW  → DATE_START / DATE_END (Date)
##   HR/HH → DATETIME_START / DATETIME_END (POSIXct)
##
## We read every resolution the shuttle actually delivered rather than
## hard-coding a list.  The RES_MAP below maps the flux_read() single-letter
## resolution code ("h", "d", …) to the manifest time_resolution label.
##
## IMPORTANT — sub-daily label:
##   AmeriFlux v1.3_r1 products use the manifest label "HR" for the sub-daily
##   file; older FLUXNET2015 products use "HH".  The discovery output above
##   tells you which label this product used.  If the manifest shows "HH",
##   change the first entry of RES_MAP from h = "HR" to h = "HH".

## Detect sub-daily label from the manifest — use whichever is present.
## This makes the script portable across AmeriFlux and ICOS products.
subdaily_label <- if ("HR" %in% avail$time_resolution) "HR" else "HH"
message(sprintf("\nSub-daily manifest label detected: '%s'", subdaily_label))

## Map flux_read() resolution codes to manifest time_resolution labels.
## flux_read() uses single lowercase letters; the manifest uses site-specific
## uppercase labels (HR or HH for sub-daily, DD/WW/MM/YY for coarser).
RES_MAP <- c(h = subdaily_label, d = "DD", w = "WW", m = "MM", y = "YY")

## Discover which resolutions are actually in the manifest for each dataset.
present_fluxmet <- unique(na.omit(
  file_manifest$time_resolution[file_manifest$dataset == "FLUXMET"]
))
present_era5 <- unique(na.omit(
  file_manifest$time_resolution[file_manifest$dataset == "ERA5"]
))

all_res_codes  <- names(RES_MAP)
expected_labels <- unname(RES_MAP)

cat("\n--- Shuttle delivery: resolutions present vs expected ---\n")
cat(sprintf("  FLUXMET: %s  (expected: %s)\n",
            paste(sort(present_fluxmet), collapse = ", "),
            paste(expected_labels, collapse = ", ")))
cat(sprintf("  ERA5:    %s  (expected: %s)\n",
            paste(sort(present_era5), collapse = ", "),
            paste(expected_labels, collapse = ", ")))

missing_fluxmet <- setdiff(expected_labels, present_fluxmet)
missing_era5    <- setdiff(expected_labels, present_era5)
if (length(missing_fluxmet)) cat("  FLUXMET missing:", paste(missing_fluxmet, collapse = ", "), "\n")
if (length(missing_era5))    cat("  ERA5    missing:", paste(missing_era5, collapse = ", "), "\n")

## Generic reader: attempt to read one resolution for one dataset.
## Returns NULL silently if the resolution is absent, so save_csv() below
## can handle it gracefully rather than erroring.
read_one <- function(res_code, dataset_name) {
  manifest_label <- RES_MAP[res_code]
  present <- if (dataset_name == "FLUXMET") present_fluxmet else present_era5
  if (!(manifest_label %in% present)) {
    message(sprintf("  %s %s: not in delivery — skipping", dataset_name, manifest_label))
    return(NULL)
  }
  message(sprintf("  Reading %s %s …", dataset_name, manifest_label))
  tryCatch(
    flux_read(file_manifest, resolution = res_code,
              datasets = dataset_name, site_ids = "US-NR1"),
    error = function(e) { message("  ERROR: ", e$message); NULL }
  )
}

## Read all resolutions for FLUXMET.
## Result names follow the pattern fluxmet_h, fluxmet_d, fluxmet_w, fluxmet_m,
## fluxmet_y so they can be accessed programmatically below.
message("\n--- Reading FLUXMET (all delivered resolutions) ---")
fluxmet_data <- setNames(
  lapply(all_res_codes, read_one, dataset_name = "FLUXMET"),
  paste0("fluxmet_", names(RES_MAP))
)

## Convenience aliases that the rest of the script references by name.
hr <- fluxmet_data$fluxmet_h   ## sub-daily (HR or HH depending on product)
dd <- fluxmet_data$fluxmet_d   ## daily
ww <- fluxmet_data$fluxmet_w   ## weekly
mm <- fluxmet_data$fluxmet_m   ## monthly
yy <- fluxmet_data$fluxmet_y   ## annual

## Read all resolutions for ERA5.
message("\n--- Reading ERA5 (all delivered resolutions) ---")
era5_data <- setNames(
  lapply(all_res_codes, read_one, dataset_name = "ERA5"),
  paste0("era5_", names(RES_MAP))
)

era5_hr <- era5_data$era5_h
era5_dd <- era5_data$era5_d
era5_ww <- era5_data$era5_w
era5_mm <- era5_data$era5_m

## BIF site metadata (biological, land-use, and instrument information).
message("\n--- Reading BIF metadata ---")
bif_raw <- tryCatch(
  flux_badm(file_manifest, site_ids = "US-NR1"),
  error = function(e) {
    message("  flux_badm error: ", e$message)
    ## Fallback: read BIF CSV directly from the manifest path.
    bif_row <- dplyr::filter(file_manifest, dataset == "BIF")
    if (nrow(bif_row) > 0) {
      message("  Falling back to direct CSV read: ", basename(bif_row$path[1]))
      list(`US-NR1` = readr::read_csv(bif_row$path[1], show_col_types = FALSE))
    } else NULL
  }
)
bif <- if (!is.null(bif_raw) && length(bif_raw) > 0) bif_raw[[1]] else NULL
if (!is.null(bif)) cat(sprintf("  BIF: %d rows × %d cols\n", nrow(bif), ncol(bif)))

## ==========================================================================
## 10. Save CSVs
## ==========================================================================
## Output filenames use _HH_ for the half-hourly product, following the
## ICOS/FLUXNET convention, regardless of whether the AmeriFlux manifest
## internally labels the file "HR" or "HH".  This distinguishes the 30-min
## US-NR1 file from the genuinely hourly US-MMS _HR_ product.

message("\n--- Saving CSV files ---")

save_csv <- function(df, fname, label) {
  if (is.null(df)) {
    message("  Skipping ", label, " (not available from this product)")
    return(invisible(NULL))
  }
  path <- file.path(out_dir, fname)
  readr::write_csv(df, path)
  message(sprintf("  %-35s  %d rows × %d cols  (%.1f MB)",
                  fname, nrow(df), ncol(df), file.size(path) / 1e6))
}

save_csv(hr,      "US-NR1_HH.csv",        "FLUXMET sub-daily")
save_csv(dd,      "US-NR1_DD.csv",        "FLUXMET DD")
save_csv(ww,      "US-NR1_WW.csv",        "FLUXMET WW")
save_csv(mm,      "US-NR1_MM.csv",        "FLUXMET MM")
save_csv(yy,      "US-NR1_YY.csv",        "FLUXMET YY")
save_csv(era5_hr, "US-NR1_ERA5_HR.csv",   "ERA5 sub-daily")
save_csv(era5_dd, "US-NR1_ERA5_DD.csv",   "ERA5 DD")
save_csv(era5_ww, "US-NR1_ERA5_WW.csv",   "ERA5 WW")
save_csv(era5_mm, "US-NR1_ERA5_MM.csv",   "ERA5 MM")
save_csv(bif,     "US-NR1_BIF.csv",       "BIF metadata")

## ==========================================================================
## 11. Summary: each FLUXMET resolution
## ==========================================================================

## Helper: extract the year range from whichever timestamp column flux_read()
## produced.  The column name depends on resolution (see §9 API notes).
ts_year_range <- function(df) {
  if ("YEAR"           %in% names(df)) return(range(df$YEAR))
  if ("DATE"           %in% names(df)) return(range(lubridate::year(df$DATE)))
  if ("DATE_START"     %in% names(df)) return(range(lubridate::year(df$DATE_START)))
  if ("DATETIME_START" %in% names(df)) return(range(lubridate::year(df$DATETIME_START)))
  return(c(NA, NA))
}

ts_col_name <- function(df) {
  if ("YEAR"           %in% names(df)) return("YEAR")
  if ("DATE"           %in% names(df)) return("DATE")
  if ("DATE_START"     %in% names(df)) return("DATE_START")
  if ("DATETIME_START" %in% names(df)) return("DATETIME_START")
  return(NA_character_)
}

summarise_res <- function(df, label) {
  if (is.null(df)) { cat(sprintf("\n[%s] NOT AVAILABLE\n", label)); return(invisible(NULL)) }
  yr  <- ts_year_range(df)
  cat(sprintf("\n[%s]  %d rows | %d cols | %d – %d  (timestamp: %s)\n",
              label, nrow(df), ncol(df), yr[1], yr[2], ts_col_name(df)))
  ## Key carbon and meteorological variables to check
  key <- c("NEE_VUT_REF", "NEE_CUT_REF", "GPP_NT_VUT_REF", "GPP_DT_VUT_REF",
           "RECO_NT_VUT_REF", "LE_F_MDS", "H_F_MDS",
           "SW_IN_F", "TA_F", "TA_ERA", "NEE_VUT_REF_QC")
  cat("  Present:", paste(intersect(key, names(df)), collapse = ", "), "\n")
  absent <- setdiff(key, names(df))
  if (length(absent)) cat("  Absent :", paste(absent, collapse = ", "), "\n")
  if (!any(c("NEE_VUT_REF", "NEE_CUT_REF") %in% names(df)))
    cat("  WARNING: no NEE variant found.\n")
}

cat("\n", strrep("=", 60), "\n", "FLUXMET RESOLUTION SUMMARY\n",
    strrep("=", 60), "\n", sep = "")

summarise_res(hr, sprintf("sub-daily (%s)", subdaily_label))
summarise_res(dd, "DD daily")
summarise_res(ww, "WW weekly")
summarise_res(mm, "MM monthly")
summarise_res(yy, "YY annual")

## ==========================================================================
## 12. Annual NEE spot-check (YY file)
## ==========================================================================
## Units: gC m-2 yr-1.  Negative = net ecosystem carbon sink (more C absorbed
## than released); positive = net source.
## US-NR1 is a weak annual carbon sink on average, though individual years
## with early snowmelt or late-season frost events can produce source years.

cat("\n", strrep("=", 60), "\n", "ANNUAL NEE SPOT-CHECK (gC m-2 yr-1)\n",
    strrep("=", 60), "\n", sep = "")

if (!is.null(yy)) {
  yy_nee <- yy |>
    dplyr::select(YEAR, dplyr::any_of(
      c("NEE_VUT_REF", "NEE_CUT_REF", "GPP_NT_VUT_REF", "RECO_NT_VUT_REF")
    )) |>
    dplyr::arrange(YEAR)
  print(as.data.frame(yy_nee), digits = 4, row.names = FALSE)
} else {
  cat("YY file not available.\n")
}

## ==========================================================================
## 13. Key variable availability at sub-daily scale
## ==========================================================================
## Check whether the key driver and flux variables needed by SSEM are present
## and how much of the record is gap-free at native sub-daily resolution.
##
## NOTE on US-NR1 v1.3_r1 product: this product provides NEE_CUT_REF (constant
## u*-threshold method) but NOT NEE_VUT_REF (variable u*-threshold method).
## This differs from US-MMS which provides NEE_VUT_REF.  NEE_CUT_REF is used
## as the primary NEE target for all coverage and cost-function analyses here.
## SW_IN_F and TA_F are gap-filled drivers; both are expected to be 100% present.

## Determine which NEE variant is available — prefer VUT, fall back to CUT.
nee_col <- if ("NEE_VUT_REF" %in% names(hr)) "NEE_VUT_REF" else
           if ("NEE_CUT_REF" %in% names(hr)) "NEE_CUT_REF" else NA_character_
nee_qc_col <- paste0(nee_col, "_QC")
if (!is.na(nee_col))
  message(sprintf("NEE column in use: %s", nee_col))
else
  message("WARNING: no NEE variant found in sub-daily data.")

cat("\n", strrep("=", 60), "\n",
    sprintf("KEY VARIABLE AVAILABILITY AT %s SCALE\n", subdaily_label),
    strrep("=", 60), "\n", sep = "")

if (!is.null(hr)) {
  ## Report all key variables: the active NEE column plus the two SSEM drivers.
  key_vars <- c(nee_col, "SW_IN_F", "TA_F")
  key_vars <- key_vars[!is.na(key_vars)]
  for (v in key_vars) {
    if (v %in% names(hr)) {
      n_total <- nrow(hr)
      n_nonNA <- sum(!is.na(hr[[v]]))
      cat(sprintf("  %-30s  %d / %d rows non-NA  (%.1f%%)\n",
                  v, n_nonNA, n_total, 100 * n_nonNA / n_total))
    } else {
      cat(sprintf("  %-30s  NOT PRESENT\n", v))
    }
  }
  ## Also note which NEE variant is absent so students know what to expect.
  absent_nee <- setdiff(c("NEE_VUT_REF", "NEE_CUT_REF"), names(hr))
  if (length(absent_nee))
    cat(sprintf("  NOTE: %s absent from this product version\n",
                paste(absent_nee, collapse = ", ")))
} else {
  cat("Sub-daily file not available — cannot assess variable coverage.\n")
}

## ==========================================================================
## 14. Sub-daily NEE coverage by year (which years exceed 80%?)
## ==========================================================================
## Compute, for each calendar year, the fraction of expected sub-daily
## timesteps where the active NEE column is non-missing.
##
## "Expected" timesteps per year = rows actually recorded in that year
## (handles leap years automatically).  A year with ≥ 80% non-missing NEE
## is considered usable for particle filter validation.
##
## QC semantics at sub-daily scale (FULLSET):
##   NEE_CUT_REF_QC: 0 = directly measured, 1–3 = gap-fill tiers (same scale
##   as NEE_VUT_REF_QC where present).  A non-NA NEE value includes both
##   measured and gap-filled timesteps; pct_measured filters to QC = 0 only.

nee_label <- if (is.na(nee_col)) "NEE" else nee_col

cat("\n", strrep("=", 60), "\n",
    sprintf("SUB-DAILY %s COVERAGE BY YEAR\n", nee_label),
    strrep("=", 60), "\n", sep = "")

## Primary path: compute coverage from sub-daily data.
if (!is.null(hr) && !is.na(nee_col) && nee_col %in% names(hr) &&
    "DATETIME_START" %in% names(hr)) {

  has_qc_col <- !is.na(nee_qc_col) && nee_qc_col %in% names(hr)

  hr_cov <- hr |>
    dplyr::mutate(
      year       = lubridate::year(DATETIME_START),
      is_present = !is.na(.data[[nee_col]]),
      is_meas    = if (has_qc_col) .data[[nee_qc_col]] == 0 else NA
    ) |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      n_steps      = dplyr::n(),
      n_present    = sum(is_present),
      pct_present  = round(100 * n_present / n_steps, 1),
      n_measured   = if (all(is.na(is_meas))) NA_integer_
                     else as.integer(sum(is_meas, na.rm = TRUE)),
      pct_measured = if (all(is.na(is_meas))) NA_real_
                     else round(100 * n_measured / n_steps, 1),
      .groups      = "drop"
    ) |>
    dplyr::mutate(usable_80pct = ifelse(pct_present >= 80, "YES", "no")) |>
    dplyr::arrange(year)

  print(as.data.frame(hr_cov), row.names = FALSE)

  usable_years <- hr_cov$year[hr_cov$pct_present >= 80]
  cat(sprintf(
    "\nYears with >= 80%% non-missing sub-daily %s (%d / %d):\n  %s\n",
    nee_label, length(usable_years), nrow(hr_cov),
    paste(usable_years, collapse = ", ")
  ))

} else {
  ## Fallback: use daily data with the same NEE variant preference logic.
  dd_nee_col <- if (!is.null(dd)) {
    if ("NEE_VUT_REF" %in% names(dd)) "NEE_VUT_REF"
    else if ("NEE_CUT_REF" %in% names(dd)) "NEE_CUT_REF"
    else NA_character_
  } else NA_character_

  if (!is.null(dd) && !is.na(dd_nee_col)) {
    cat(sprintf("Sub-daily data unavailable; falling back to daily %s coverage:\n\n",
                dd_nee_col))
    dd_cov <- dd |>
      dplyr::mutate(year = lubridate::year(DATE),
                    is_present = !is.na(.data[[dd_nee_col]])) |>
      dplyr::group_by(year) |>
      dplyr::summarise(
        n_days      = dplyr::n(),
        n_present   = sum(is_present),
        pct_present = round(100 * n_present / n_days, 1),
        .groups     = "drop"
      ) |>
      dplyr::mutate(usable_80pct = ifelse(pct_present >= 80, "YES", "no")) |>
      dplyr::arrange(year)

    print(as.data.frame(dd_cov), row.names = FALSE)
    usable_years <- dd_cov$year[dd_cov$pct_present >= 80]
    cat(sprintf(
      "\nYears with >= 80%% non-missing daily %s (%d / %d):\n  %s\n",
      dd_nee_col, length(usable_years), nrow(dd_cov),
      paste(usable_years, collapse = ", ")
    ))
  } else {
    cat("No NEE column found in sub-daily or daily data.\n")
  }
}

## ==========================================================================
## 15. ERA5 met summary
## ==========================================================================

cat("\n", strrep("=", 60), "\n", "ERA5 MET SUMMARY\n",
    strrep("=", 60), "\n", sep = "")

for (pair in list(list(era5_dd, "ERA5 DD"), list(era5_mm, "ERA5 MM"))) {
  df <- pair[[1]]; label <- pair[[2]]
  if (is.null(df)) { cat(sprintf("\n[%s] NOT AVAILABLE\n", label)); next }
  yr <- ts_year_range(df)
  cat(sprintf("\n[%s]  %d rows | %d cols | %d – %d\n",
              label, nrow(df), ncol(df), yr[1], yr[2]))
  met_vars <- c("SW_IN_F", "SW_IN_ERA", "TA_F", "TA_ERA", "VPD_F", "P_F", "WS_F")
  cat("  Met drivers present:", paste(intersect(met_vars, names(df)), collapse = ", "), "\n")
}

## ==========================================================================
## 16. Final file inventory
## ==========================================================================

cat("\n", strrep("=", 60), "\n", "OUTPUT FILES IN data/US-NR1/\n",
    strrep("=", 60), "\n", sep = "")
for (f in list.files(out_dir, pattern = "\\.csv$", full.names = TRUE)) {
  cat(sprintf("  %-35s  %.1f MB\n", basename(f), file.size(f) / 1e6))
}

cat("\ndownload_usnr1.R complete.\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Commit:", tryCatch(system("git rev-parse --short HEAD", intern = TRUE),
                        error = function(e) "unknown"), "\n")
sessionInfo()
