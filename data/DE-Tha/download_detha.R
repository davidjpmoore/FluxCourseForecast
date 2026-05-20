## download_detha.R
## ----------------
## Downloads, extracts, reads, and summarises the DE-Tha AmeriFlux / ICOS
## FLUXNET FULLSET record for Tharandt, Germany.
##
## DE-Tha (ENF, lat 50.96, lon 13.57) is a temperate evergreen needleleaf
## forest (Norway spruce, Picea abies) in Saxony, Germany, with a long-running
## eddy covariance record (1996–2024).  It is operated by the European Fluxes
## Database and ICOS networks.
##
## Why DE-Tha?
##   Paired with DK-Sor (DBF) and US-MMS (DBF), DE-Tha illustrates the
##   contrast between an evergreen needleleaf forest and deciduous broadleaf
##   forests.  Unlike deciduous sites, DE-Tha maintains low but non-zero
##   photosynthesis year-round.  SSEM (which has no phenology routine and
##   treats LAI as constant) will fail to reproduce the strong spring flush
##   and autumn senescence visible in the deciduous sites, while producing
##   a more plausible flat seasonal profile for DE-Tha — providing a useful
##   teaching comparison.
##
## Key difference from US-MMS:
##   This site is served by the ICOS data hub, not AmeriFlux.  The ICOS FLUXNET
##   product delivers HH (half-hourly) data, unlike the AMF v1.3_r1 product
##   that US-MMS uses.  No ICOS-specific credentials are required; the shuttle
##   downloads the ICOS product without authentication.
##
## fluxnet package API (v0.3.1) notes — same as download_usmms.R:
##   flux_download()       → BUG: fails if ZIP already present (workaround below)
##   flux_extract()        → zip_dir, output_dir arguments
##   flux_discover_files() → data_dir argument; returns tibble with columns:
##                           path, dataset, time_resolution, site_id, ...
##   flux_read()           → returns a SINGLE tibble directly (not a list).
##                           Already replaces -9999 with NA.
##                           Renames timestamp cols:
##                             YY: TIMESTAMP → YEAR (integer)
##                             MM/DD: TIMESTAMP → DATE (Date)
##                             WW: TIMESTAMP_START/END → DATE_START/DATE_END
##                             HH: TIMESTAMP_START/END → DATETIME_START/DATETIME_END
##
## HH QC flag semantics (DIFFERENT from DD):
##   HH NEE_VUT_REF_QC  : integer 0–3
##                         0 = original measured value
##                         1 = good quality gap-fill (high confidence)
##                         2 = medium quality gap-fill
##                         3 = poor quality gap-fill (use with caution)
##   DD NEE_VUT_REF_QC  : fraction 0–1 (fraction of constituent HH that are gap-filled)
##   Do NOT compare these two scales directly (see CLAUDE.md).
##
## Product version downloaded: ICOS_DE-Tha_FLUXNET_1996-2024_v1.3_r1
##   Available resolutions: HH, DD, WW, MM, YY (FLUXMET + ERA5)
##   ERA5 extends back to 1981 (full reanalysis period).
##   DE-Tha HH FLUXMET has 243 columns vs DK-Sor's 250 — some sensor variables
##   differ between sites (expected; column count varies by instrumentation).
##
## Prerequisites
## -------------
##   R 4.4+, Python 3.11–3.13 (not 3.14+)
##   No ICOS credentials required (product is freely downloadable).

## ==========================================================================
## 0. Directories
## ==========================================================================

out_dir   <- file.path("data", "DE-Tha")   ## processed CSVs
raw_dir   <- file.path(out_dir, "raw")      ## downloaded ZIPs (not git-tracked)
unzip_dir <- file.path(raw_dir, "unzipped") ## extracted files

dir.create(out_dir,   showWarnings = FALSE, recursive = TRUE)
dir.create(raw_dir,   showWarnings = FALSE, recursive = TRUE)
dir.create(unzip_dir, showWarnings = FALSE, recursive = TRUE)

## ==========================================================================
## 1. Install / load fluxnet package (pinned to v0.3.1)
## ==========================================================================

if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
message("Installing EcosystemEcologyLab/fluxnet-package @ v0.3.1 …")
pak::pak("EcosystemEcologyLab/fluxnet-package@v0.3.1")

library(fluxnet)
library(tidyverse)
library(lubridate)

## ==========================================================================
## 2. Verify Python version WITHOUT initialising a reticulate session
## ==========================================================================
## CRITICAL: Do not call library(reticulate), use_python(), or py_config()
## before flux_install_shuttle().  Those calls lock reticulate into a
## specific interpreter.  flux_install_shuttle() must be the first Python
## initialisation so use_virtualenv("fluxnet") takes effect.

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
## 4. Confirm DE-Tha is in the AmeriFlux/ICOS site manifest
## ==========================================================================
## flux_listall() returns sites from all data hubs including ICOS.
## DE-Tha is listed under data_hub = "ICOS" and network =
## "European Fluxes Database;ICOS".

message("\nQuerying site catalogue …")
site_manifest <- flux_listall()
detha_meta    <- dplyr::filter(site_manifest, site_id == "DE-Tha")

if (nrow(detha_meta) == 0) stop("DE-Tha not found in the site manifest.")

cat("\n--- DE-Tha manifest entry ---\n")
print(detha_meta)
cat(sprintf(
  "\nData hub: %s | Network: %s | IGBP: %s\n",
  detha_meta$data_hub, detha_meta$network, detha_meta$igbp
))
cat(sprintf("Manifest record span: %s – %s\n",
            detha_meta$first_year, detha_meta$last_year))

## ==========================================================================
## 5. Download the full record
## ==========================================================================
## ICOS FLUXNET data is freely downloadable without credentials.
## The same flux_download() bug as US-MMS applies: skip if ZIP present.

existing_zips <- list.files(raw_dir, pattern = "\\.zip$", full.names = TRUE)

if (length(existing_zips) > 0) {
  message("\nExisting ZIP(s) found — skipping download:")
  message("  ", paste(basename(existing_zips), collapse = "\n  "))
} else {
  message("\nDownloading DE-Tha FULLSET data (this may take several minutes) …")
  flux_download(site_ids = "DE-Tha", download_dir = raw_dir)
  message("Download complete.")
}

## ==========================================================================
## 6. Extract ZIPs
## ==========================================================================

message("\nExtracting ZIP files …")
flux_extract(zip_dir = raw_dir, output_dir = unzip_dir)
message("Extraction complete.")

## ==========================================================================
## 7. Discover extracted files
## ==========================================================================

message("\nDiscovering extracted files …")
file_manifest <- flux_discover_files(data_dir = unzip_dir)

cat("\n--- File manifest ---\n")
print(file_manifest)

## Convenience: show available resolutions
avail <- file_manifest |>
  dplyr::filter(dataset %in% c("FLUXMET","ERA5")) |>
  dplyr::select(dataset, time_resolution) |>
  dplyr::distinct() |>
  dplyr::arrange(dataset, time_resolution)
cat("\nAvailable dataset × resolution combinations:\n")
print(as.data.frame(avail))

## ==========================================================================
## 8. Read all available FLUXMET and ERA5 resolutions (discovery-driven)
## ==========================================================================
## ICOS product delivers HH, DD, WW, MM, YY for both FLUXMET and ERA5.
## This is different from the US-MMS AmeriFlux v1.3_r1 product which
## does not include HH.
##
## Unit reminders (do NOT convert):
##   HH/DD/WW/MM NEE in umol m-2 s-1;  YY in gC m-2 yr-1
##   _F suffix: measured first, ERA5 fill where absent.
##
## QC flag semantics (do NOT compare directly):
##   HH NEE_VUT_REF_QC: 0=measured, 1=good fill, 2=medium fill, 3=poor fill
##   DD NEE_VUT_REF_QC: fraction 0–1 (fraction gap-filled)

## Map flux_read resolution codes to their manifest time_resolution labels
RES_MAP <- c(h = "HH", d = "DD", w = "WW", m = "MM", y = "YY")

## Discover which resolutions are present in the extracted files
present_fluxmet <- unique(na.omit(
  file_manifest$time_resolution[file_manifest$dataset == "FLUXMET"]
))
present_era5 <- unique(na.omit(
  file_manifest$time_resolution[file_manifest$dataset == "ERA5"]
))

all_res_codes <- names(RES_MAP)

cat("\n--- Shuttle delivery: resolutions present vs expected ---\n")
cat(sprintf("  FLUXMET: %s\n", paste(sort(present_fluxmet), collapse = ", ")))
cat(sprintf("  ERA5:    %s\n", paste(sort(present_era5), collapse = ", ")))

missing_fluxmet <- setdiff(unname(RES_MAP), present_fluxmet)
missing_era5    <- setdiff(unname(RES_MAP), present_era5)
if (length(missing_fluxmet)) cat("  FLUXMET missing:", paste(missing_fluxmet, collapse=", "), "\n")
if (length(missing_era5))    cat("  ERA5    missing:", paste(missing_era5,    collapse=", "), "\n")

## Generic reader: read one resolution for one dataset
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
              datasets = dataset_name, site_ids = "DE-Tha"),
    error = function(e) { message("  ERROR: ", e$message); NULL }
  )
}

## Read all resolutions for FLUXMET
message("\n--- Reading FLUXMET (all delivered resolutions) ---")
fluxmet_data <- setNames(
  lapply(all_res_codes, read_one, dataset_name = "FLUXMET"),
  paste0("fluxmet_", names(RES_MAP))
)

## Convenience aliases matching the summary sections below
hh <- fluxmet_data$fluxmet_h
dd <- fluxmet_data$fluxmet_d
ww <- fluxmet_data$fluxmet_w
mm <- fluxmet_data$fluxmet_m
yy <- fluxmet_data$fluxmet_y

## Read all resolutions for ERA5
message("\n--- Reading ERA5 (all delivered resolutions) ---")
era5_data <- setNames(
  lapply(all_res_codes, read_one, dataset_name = "ERA5"),
  paste0("era5_", names(RES_MAP))
)

era5_hh <- era5_data$era5_h
era5_dd <- era5_data$era5_d
era5_ww <- era5_data$era5_w
era5_mm <- era5_data$era5_m

## BIF site metadata
message("\n--- Reading BIF metadata ---")
bif_raw <- tryCatch(
  flux_badm(file_manifest, site_ids = "DE-Tha"),
  error = function(e) {
    message("  flux_badm error: ", e$message)
    ## Fallback: find BIF CSV in manifest directly
    bif_row <- dplyr::filter(file_manifest, dataset == "BIF")
    if (nrow(bif_row) > 0) {
      message("  Falling back to direct CSV read: ", basename(bif_row$path[1]))
      list(`DE-Tha` = readr::read_csv(bif_row$path[1], show_col_types = FALSE))
    } else NULL
  }
)
bif <- if (!is.null(bif_raw) && length(bif_raw) > 0) bif_raw[[1]] else NULL
if (!is.null(bif)) cat(sprintf("  BIF: %d rows × %d cols\n", nrow(bif), ncol(bif)))

## ==========================================================================
## 9. Save CSVs
## ==========================================================================

message("\n--- Saving CSV files ---")

save_csv <- function(df, fname, label) {
  if (is.null(df)) { message("  Skipping ", label, " (not available)"); return(invisible(NULL)) }
  path <- file.path(out_dir, fname)
  readr::write_csv(df, path)
  message(sprintf("  %-35s  %d rows × %d cols  (%.1f MB)",
                  fname, nrow(df), ncol(df), file.size(path) / 1e6))
}

save_csv(hh,      "DE-Tha_HH.csv",         "FLUXMET HH")
save_csv(dd,      "DE-Tha_DD.csv",         "FLUXMET DD")
save_csv(ww,      "DE-Tha_WW.csv",         "FLUXMET WW")
save_csv(mm,      "DE-Tha_MM.csv",         "FLUXMET MM")
save_csv(yy,      "DE-Tha_YY.csv",         "FLUXMET YY")
save_csv(era5_hh, "DE-Tha_ERA5_HH.csv",    "ERA5 HH")
save_csv(era5_dd, "DE-Tha_ERA5_DD.csv",    "ERA5 DD")
save_csv(era5_ww, "DE-Tha_ERA5_WW.csv",    "ERA5 WW")
save_csv(era5_mm, "DE-Tha_ERA5_MM.csv",    "ERA5 MM")
save_csv(bif,     "DE-Tha_BIF.csv",        "BIF metadata")

## ==========================================================================
## 10. Summary: each FLUXMET resolution
## ==========================================================================

## Helper: extract year range from the renamed timestamp column
ts_year_range <- function(df) {
  if ("YEAR" %in% names(df))           return(range(df$YEAR))
  if ("DATE" %in% names(df))           return(range(lubridate::year(df$DATE)))
  if ("DATE_START" %in% names(df))     return(range(lubridate::year(df$DATE_START)))
  if ("DATETIME_START" %in% names(df)) return(range(lubridate::year(df$DATETIME_START)))
  return(c(NA, NA))
}

ts_col_name <- function(df) {
  if ("YEAR" %in% names(df))           return("YEAR")
  if ("DATE" %in% names(df))           return("DATE")
  if ("DATE_START" %in% names(df))     return("DATE_START")
  if ("DATETIME_START" %in% names(df)) return("DATETIME_START")
  return(NA)
}

summarise_res <- function(df, label) {
  if (is.null(df)) { cat(sprintf("\n[%s] NOT AVAILABLE\n", label)); return(invisible(NULL)) }
  yr <- ts_year_range(df)
  cat(sprintf("\n[%s]  %d rows | %d cols | %d – %d  (timestamp: %s)\n",
              label, nrow(df), ncol(df), yr[1], yr[2], ts_col_name(df)))
  key <- c("NEE_VUT_REF", "NEE_CUT_REF", "GPP_NT_VUT_REF", "GPP_DT_VUT_REF",
           "RECO_NT_VUT_REF", "LE_F_MDS", "H_F_MDS", "SW_IN_F", "TA_F",
           "TA_ERA", "NEE_VUT_REF_QC")
  cat("  Present:", paste(intersect(key, names(df)), collapse = ", "), "\n")
  absent <- setdiff(key, names(df))
  if (length(absent)) cat("  Absent :", paste(absent, collapse = ", "), "\n")
  if (!any(c("NEE_VUT_REF","NEE_CUT_REF") %in% names(df)))
    cat("  WARNING: no NEE variant found.\n")
}

cat("\n", strrep("=", 60), "\n", "FLUXMET RESOLUTION SUMMARY\n",
    strrep("=", 60), "\n", sep = "")

summarise_res(hh, "HH half-hourly")
summarise_res(dd, "DD daily")
summarise_res(ww, "WW weekly")
summarise_res(mm, "MM monthly")
summarise_res(yy, "YY annual")

## ==========================================================================
## 11. Annual NEE spot-check (YY file)
## ==========================================================================
## Units: gC m-2 yr-1.  Negative = net carbon sink, positive = source.
## DE-Tha is an ENF — expect weaker seasonality than DBF sites, lower peak
## GPP but non-zero winter photosynthesis.  The 2018 Central European drought
## (and subsequent bark beetle outbreak) is a notable disturbance signal.

cat("\n", strrep("=", 60), "\n", "ANNUAL NEE SPOT-CHECK (gC m-2 yr-1)\n",
    strrep("=", 60), "\n", sep = "")

if (!is.null(yy)) {
  yy_nee <- yy |>
    dplyr::select(YEAR, dplyr::any_of(
      c("NEE_VUT_REF","NEE_CUT_REF","GPP_NT_VUT_REF","RECO_NT_VUT_REF")
    )) |>
    dplyr::arrange(YEAR)
  print(as.data.frame(yy_nee), digits = 4, row.names = FALSE)
} else {
  cat("YY file not available.\n")
}

## ==========================================================================
## 12. Half-hourly NEE coverage by year (primary QC check for HH data)
## ==========================================================================
## Unlike US-MMS (where HH is absent), the ICOS product includes HH.
## We report two coverage metrics per year:
##
##   pct_present : fraction of half-hours where NEE_VUT_REF is non-missing
##                 (includes both measured and gap-filled values)
##   pct_measured: fraction where NEE_VUT_REF_QC == 0 (original measurement,
##                 no gap-filling)
##
## A year with > 80% measured half-hours is considered high quality for
## particle filter validation.
##
## Note: NEE_VUT_REF_QC here is on the HH integer 0–3 scale.
## This is DIFFERENT from the DD file where the same column is a fraction.

cat("\n", strrep("=", 60), "\n",
    "HH NEE_VUT_REF COVERAGE BY YEAR (> 80% measured threshold)\n",
    strrep("=", 60), "\n", sep = "")

if (!is.null(hh) && "NEE_VUT_REF" %in% names(hh)) {
  hh_cov <- hh |>
    dplyr::mutate(
      year        = lubridate::year(DATETIME_START),
      is_present  = !is.na(NEE_VUT_REF),
      is_measured = !is.na(NEE_VUT_REF_QC) & NEE_VUT_REF_QC == 0L
    ) |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      n_hh         = dplyr::n(),
      n_present    = sum(is_present),
      n_measured   = sum(is_measured),
      pct_present  = round(100 * n_present  / n_hh, 1),
      pct_measured = round(100 * n_measured / n_hh, 1),
      .groups      = "drop"
    ) |>
    dplyr::mutate(usable_80pct = ifelse(pct_measured >= 80, "YES", "no")) |>
    dplyr::arrange(year)

  print(as.data.frame(hh_cov), row.names = FALSE)

  usable_years <- hh_cov$year[hh_cov$pct_measured >= 80]
  cat(sprintf(
    "\nYears with >= 80%% directly measured HH NEE_VUT_REF (%d / %d):\n  %s\n",
    length(usable_years), nrow(hh_cov), paste(usable_years, collapse = ", ")
  ))
} else {
  cat("HH FLUXMET or NEE_VUT_REF not available.\n")
}

## ==========================================================================
## 13. ERA5 met summary
## ==========================================================================

cat("\n", strrep("=", 60), "\n", "ERA5 MET SUMMARY\n",
    strrep("=", 60), "\n", sep = "")

for (pair in list(list(era5_hh, "ERA5 HH"), list(era5_dd, "ERA5 DD"),
                  list(era5_mm, "ERA5 MM"))) {
  df <- pair[[1]]; label <- pair[[2]]
  if (is.null(df)) { cat(sprintf("\n[%s] NOT AVAILABLE\n", label)); next }
  yr <- ts_year_range(df)
  cat(sprintf("\n[%s]  %d rows | %d cols | %d – %d\n",
              label, nrow(df), ncol(df), yr[1], yr[2]))
  met_vars <- c("SW_IN_F","SW_IN_ERA","TA_F","TA_ERA","VPD_F","P_F","WS_F")
  cat("  Met drivers present:", paste(intersect(met_vars, names(df)), collapse = ", "), "\n")
}

## ==========================================================================
## 14. Site comparison notes (ENF vs DBF)
## ==========================================================================

cat("\n", strrep("=", 60), "\n", "SITE COMPARISON NOTES\n",
    strrep("=", 60), "\n", sep = "")
cat("
  DE-Tha (ENF) vs DK-Sor (DBF) at similar latitudes:
    Both are mid-latitude European sites (51 °N vs 55 °N), but the vegetation
    type drives fundamentally different seasonal GPP patterns.
    - DE-Tha (Norway spruce): maintains photosynthesis year-round; broad,
      flatter seasonal curve; typically a stronger annual sink in cool years.
    - DK-Sor (beech): near-zero GPP Nov–Mar; sharp spring onset; high peak
      summer GPP; more sensitive to spring temperature anomalies.
    SSEM treats LAI as constant and has no phenology routine, so it will
    predict a nearly symmetric seasonal GPP curve for both sites.  The ENF
    prediction will be closer to observations; the DBF prediction will
    systematically over-predict winter GPP and under-predict the spring flush.

  2018 Central European drought:
    DE-Tha experienced severe drought stress in 2018 followed by a bark beetle
    outbreak that caused significant tree mortality.  This may appear in the
    annual NEE record as a transition from sink to near-neutral or source.
    SSEM has no drought stress or disturbance parameterisation, so it will
    miss this feature entirely.

  HH availability:
    ICOS product includes HH; US-MMS AmeriFlux v1.3_r1 does not.
    This means half-hourly particle filter validation is feasible for
    DE-Tha and DK-Sor but not for US-MMS with the current products.

  Column count difference (243 for DE-Tha vs 250 for DK-Sor in HH FLUXMET):
    Column counts vary between sites because optional sensor measurements
    (e.g., soil heat flux at multiple depths, CO2 profile, additional chamber
    fluxes) are site-specific.  All primary variables (NEE, GPP, RECO, LE, H,
    SW_IN, TA) are present at both sites.
")

## ==========================================================================
## 15. Final file inventory
## ==========================================================================

cat("\n", strrep("=", 60), "\n", "OUTPUT FILES IN data/DE-Tha/\n",
    strrep("=", 60), "\n", sep = "")
for (f in list.files(out_dir, pattern = "\\.csv$", full.names = TRUE)) {
  cat(sprintf("  %-35s  %.1f MB\n", basename(f), file.size(f) / 1e6))
}

cat("\ndownload_detha.R complete.\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Commit:", tryCatch(system("git rev-parse --short HEAD", intern = TRUE),
                        error = function(e) "unknown"), "\n")
sessionInfo()
