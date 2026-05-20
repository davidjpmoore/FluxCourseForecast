## download_usmms.R
## ----------------
## Downloads, extracts, reads, and summarises the US-MMS AmeriFlux FLUXNET
## FULLSET record for Morgan Monroe State Forest, Indiana.
##
## US-MMS (DBF, lat 39.32, lon -86.41) is a temperate deciduous broadleaf
## forest with a multi-decade eddy covariance record (1999–2023).
## The data are used in FluxCourseForecast to validate SSEM and to drive
## the particle filter.
##
## Run once before the Fluxcourse exercises.
##
## fluxnet package API (v0.3.1) key notes:
##   flux_download()       → download_dir = "fluxnet" default
##                           BUG: fails if site ZIP already exists in download_dir
##                           (workaround: skip call if ZIP present, see §6)
##   flux_extract()        → zip_dir, output_dir arguments
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
##                             HH: TIMESTAMP_START/END → DATETIME_START/DATETIME_END
##   flux_badm()           → reads BIF metadata; takes manifest + site_ids
##
## Product version downloaded: AMF_US-MMS_FLUXNET_1999-2023_v1.3_r1
##   Available resolutions: DD, WW, MM, YY (FLUXMET + ERA5)
##   HH half-hourly is NOT included in this product version.
##   ERA5 extends back to 1981 (full reanalysis period).
##
## Prerequisites
## -------------
##   R 4.4+, Python 3.11–3.13 (not 3.14+)
##   AMERIFLUX_USER_NAME / AMERIFLUX_USER_EMAIL / AMERIFLUX_INTENDED_USE
##   in ~/.Renviron (optional but required for attribution).

## ==========================================================================
## 0. Directories
## ==========================================================================

out_dir   <- file.path("data", "US-MMS")   ## processed CSVs
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
## The shuttle self-reports as 0.3.7.post0+dirty or 0.3.8 — both expected.

message("Setting up fluxnet-shuttle Python environment …")
flux_install_shuttle()
message("fluxnet-shuttle ready.")

## ==========================================================================
## 4. AmeriFlux attribution (optional but best practice)
## ==========================================================================

for (v in c("AMERIFLUX_USER_NAME","AMERIFLUX_USER_EMAIL","AMERIFLUX_INTENDED_USE")) {
  if (!nzchar(Sys.getenv(v)))
    message("NOTE: ", v, " not set — add to ~/.Renviron for AmeriFlux attribution.")
}

## ==========================================================================
## 5. Confirm US-MMS is in the AmeriFlux site manifest
## ==========================================================================
## flux_listall() queries the AmeriFlux API.
## first_year / last_year are manifest-reported; actual coverage comes from
## the extracted data (ERA5 extends further back than the tower record).

message("\nQuerying AmeriFlux site catalogue …")
site_manifest <- flux_listall()
usmms_meta    <- dplyr::filter(site_manifest, site_id == "US-MMS")

if (nrow(usmms_meta) == 0) stop("US-MMS not found in the AmeriFlux manifest.")

cat("\n--- US-MMS manifest entry ---\n")
print(usmms_meta)
cat(sprintf("\nManifest record span: %s – %s\n",
            usmms_meta$first_year, usmms_meta$last_year))

## ==========================================================================
## 6. Download the full record
## ==========================================================================
## flux_download() v0.3.1 has a bug: it filters already-downloaded ZIPs out
## of the snapshot before passing it to the Python shuttle, so if US-MMS is
## already present the shuttle receives a snapshot with no US-MMS entry and
## raises FLUXNETShuttleError.  Workaround: skip the call when the ZIP exists.

existing_zips <- list.files(raw_dir, pattern = "\\.zip$", full.names = TRUE)

if (length(existing_zips) > 0) {
  message("\nExisting ZIP(s) found — skipping download:")
  message("  ", paste(basename(existing_zips), collapse = "\n  "))
} else {
  message("\nDownloading US-MMS FULLSET data (this may take several minutes) …")
  flux_download(site_ids = "US-MMS", download_dir = raw_dir)
  message("Download complete.")
}

## ==========================================================================
## 7. Extract ZIPs
## ==========================================================================

message("\nExtracting ZIP files …")
flux_extract(zip_dir = raw_dir, output_dir = unzip_dir)
message("Extraction complete.")

## ==========================================================================
## 8. Discover extracted files
## ==========================================================================

message("\nDiscovering extracted files …")
file_manifest <- flux_discover_files(data_dir = unzip_dir)

cat("\n--- File manifest ---\n")
print(file_manifest)

## Convenience: list which resolutions are actually present
avail <- file_manifest |>
  dplyr::filter(dataset %in% c("FLUXMET","ERA5")) |>
  dplyr::select(dataset, time_resolution) |>
  dplyr::distinct() |>
  dplyr::arrange(dataset, time_resolution)
cat("\nAvailable dataset × resolution combinations:\n")
print(as.data.frame(avail))

## ==========================================================================
## 9. Read all available FLUXMET and ERA5 resolutions (discovery-driven)
## ==========================================================================
## flux_read() returns a SINGLE tibble directly (not a list).
## It already replaces -9999 with NA.
## Timestamp columns are renamed based on resolution:
##   YY  → YEAR (integer)
##   MM  → DATE (Date, YYYY-MM-01)
##   WW  → DATE_START / DATE_END (Date)
##   DD  → DATE (Date)
##   HH  → DATETIME_START / DATETIME_END (POSIXct)
##
## We read whatever resolutions the shuttle actually delivered rather than
## assuming any fixed set.  For US-MMS v1.3_r1 the shuttle delivers:
##   FLUXMET: DD, WW, MM, YY  (no HH)
##   ERA5:    DD, WW, MM, YY  (no HH)
## HH is absent at the product level — this is not a download error.
##
## Unit reminders (do NOT convert):
##   YY NEE in gC m-2 yr-1;  DD/MM/WW in gC m-2 per period
##   _F suffix (no _MDS): measured first, ERA5 fill where absent.
## QC flag semantics:
##   _F_MDS_QC: 0–3 scale   (0=measured, 1–3=gap-fill quality)
##   _F_QC:     0/1/2 scale  — do NOT compare these two scales directly.

## Map flux_read resolution codes to their manifest time_resolution labels
## flux_read uses single lowercase letters; the manifest uses doubled uppercase
## (e.g. res_code "d" → manifest label "DD", "h" → "HH")
RES_MAP <- c(h = "HH", d = "DD", w = "WW", m = "MM", y = "YY")

## Discover which resolutions are actually present for each dataset
present_fluxmet <- unique(na.omit(
  file_manifest$time_resolution[file_manifest$dataset == "FLUXMET"]
))
present_era5 <- unique(na.omit(
  file_manifest$time_resolution[file_manifest$dataset == "ERA5"]
))

all_res_codes <- names(RES_MAP)
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
              datasets = dataset_name, site_ids = "US-MMS"),
    error = function(e) { message("  ERROR: ", e$message); NULL }
  )
}

## Read all resolutions for FLUXMET
message("\n--- Reading FLUXMET (all delivered resolutions) ---")
fluxmet_data <- setNames(
  lapply(all_res_codes, read_one, dataset_name = "FLUXMET"),
  paste0("fluxmet_", names(RES_MAP))   # fluxmet_h, fluxmet_d, fluxmet_w, fluxmet_m, fluxmet_y
)

## Convenience aliases matching the rest of the script
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
  flux_badm(file_manifest, site_ids = "US-MMS"),
  error = function(e) {
    message("  flux_badm error: ", e$message)
    ## Fallback: find BIF CSV in manifest directly
    bif_row <- dplyr::filter(file_manifest, dataset == "BIF")
    if (nrow(bif_row) > 0) {
      message("  Falling back to direct CSV read: ", basename(bif_row$path[1]))
      list(`US-MMS` = readr::read_csv(bif_row$path[1], show_col_types = FALSE))
    } else NULL
  }
)
bif <- if (!is.null(bif_raw) && length(bif_raw) > 0) bif_raw[[1]] else NULL
if (!is.null(bif)) cat(sprintf("  BIF: %d rows × %d cols\n", nrow(bif), ncol(bif)))

## ==========================================================================
## 10. Save CSVs
## ==========================================================================

message("\n--- Saving CSV files ---")

save_csv <- function(df, fname, label) {
  if (is.null(df)) { message("  Skipping ", label, " (not available)"); return(invisible(NULL)) }
  path <- file.path(out_dir, fname)
  readr::write_csv(df, path)
  message(sprintf("  %-35s  %d rows × %d cols  (%.1f MB)",
                  fname, nrow(df), ncol(df), file.size(path) / 1e6))
}

save_csv(hh,      "US-MMS_HH.csv",         "FLUXMET HH")
save_csv(dd,      "US-MMS_DD.csv",         "FLUXMET DD")
save_csv(ww,      "US-MMS_WW.csv",         "FLUXMET WW")
save_csv(mm,      "US-MMS_MM.csv",         "FLUXMET MM")
save_csv(yy,      "US-MMS_YY.csv",         "FLUXMET YY")
save_csv(era5_hh, "US-MMS_ERA5_HH.csv",    "ERA5 HH")
save_csv(era5_dd, "US-MMS_ERA5_DD.csv",    "ERA5 DD")
save_csv(era5_ww, "US-MMS_ERA5_WW.csv",    "ERA5 WW")
save_csv(era5_mm, "US-MMS_ERA5_MM.csv",    "ERA5 MM")
save_csv(bif,     "US-MMS_BIF.csv",        "BIF metadata")

## ==========================================================================
## 11. Summary: each FLUXMET resolution
## ==========================================================================

## Helper: extract year range from the renamed timestamp column
ts_year_range <- function(df) {
  ## flux_read() renames: YY→YEAR (int), DD/MM→DATE (Date), WW→DATE_START (Date)
  if ("YEAR" %in% names(df)) {
    return(range(df$YEAR))
  } else if ("DATE" %in% names(df)) {
    return(range(lubridate::year(df$DATE)))
  } else if ("DATE_START" %in% names(df)) {
    return(range(lubridate::year(df$DATE_START)))
  } else if ("DATETIME_START" %in% names(df)) {
    return(range(lubridate::year(df$DATETIME_START)))
  }
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
## 12. Annual NEE spot-check (YY file)
## ==========================================================================
## Units: gC m-2 yr-1.  Negative = net carbon sink, positive = source.
## Both NEE_VUT_REF (variable u* threshold) and NEE_CUT_REF (constant u*
## threshold) are present for US-MMS.

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
## 13. Daily NEE coverage by year (proxy for half-hourly; HH not available)
## ==========================================================================
## Since HH is absent from this product version, we compute daily coverage
## from the DD file.  A year with > 80% of daily NEE_VUT_REF non-missing is
## considered usable for particle filter validation.
##
## Note on QC semantics (DD FULLSET):
##   NEE_VUT_REF_QC = fraction of half-hours that are gap-filled (0–1).
##   Values close to 0 → mostly measured; close to 1 → mostly gap-filled.
##   This is DIFFERENT from the HH QC scale (0–3 integers).

cat("\n", strrep("=", 60), "\n",
    "DAILY NEE_VUT_REF COVERAGE BY YEAR (> 80% non-missing threshold)\n",
    strrep("=", 60), "\n", sep = "")

if (!is.null(dd) && "NEE_VUT_REF" %in% names(dd)) {
  dd_cov <- dd |>
    dplyr::mutate(year = lubridate::year(DATE), is_present = !is.na(NEE_VUT_REF)) |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      n_days       = dplyr::n(),
      n_present    = sum(is_present),
      pct_present  = round(100 * n_present / n_days, 1),
      ## Also report mean gap-filled fraction for context
      mean_qc      = if ("NEE_VUT_REF_QC" %in% names(dd))
                       round(mean(NEE_VUT_REF_QC, na.rm = TRUE), 3) else NA_real_,
      .groups      = "drop"
    ) |>
    dplyr::mutate(usable_80pct = ifelse(pct_present >= 80, "YES", "no")) |>
    dplyr::arrange(year)

  print(as.data.frame(dd_cov), row.names = FALSE)

  usable_years <- dd_cov$year[dd_cov$pct_present >= 80]
  cat(sprintf(
    "\nYears with >= 80%% non-missing daily NEE_VUT_REF (%d / %d):\n  %s\n",
    length(usable_years), nrow(dd_cov), paste(usable_years, collapse = ", ")
  ))
} else {
  cat("DD FLUXMET or NEE_VUT_REF not available.\n")
}

## ==========================================================================
## 14. ERA5 met summary
## ==========================================================================

cat("\n", strrep("=", 60), "\n", "ERA5 MET SUMMARY\n",
    strrep("=", 60), "\n", sep = "")

for (pair in list(list(era5_dd, "ERA5 DD"), list(era5_mm, "ERA5 MM"))) {
  df <- pair[[1]]; label <- pair[[2]]
  if (is.null(df)) { cat(sprintf("\n[%s] NOT AVAILABLE\n", label)); next }
  yr <- ts_year_range(df)
  cat(sprintf("\n[%s]  %d rows | %d cols | %d – %d\n",
              label, nrow(df), ncol(df), yr[1], yr[2]))
  met_vars <- c("SW_IN_F","SW_IN_ERA","TA_F","TA_ERA","VPD_F","P_F","WS_F")
  cat("  Met drivers present:", paste(intersect(met_vars, names(df)), collapse = ", "), "\n")
}

## ==========================================================================
## 15. Gap summary: known issues
## ==========================================================================

cat("\n", strrep("=", 60), "\n", "KNOWN GAPS AND QUALITY NOTES\n",
    strrep("=", 60), "\n", sep = "")
cat("
  - HH (half-hourly) FLUXMET file: NOT included in AMF FLUXNET v1.3_r1.
    This is a product-level limitation, not a download error.
    ERA5 HH is also absent (ERA5 product provides DD resolution here).
    For SSEM model driving at sub-daily timestep, use ERA5 DD data
    aggregated to the desired driver resolution.

  - ERA5 data starts 1981, pre-dating the 1999 tower installation.
    ERA5 records before 1999 are climatology with no tower constraints.

  - Both NEE_VUT_REF and NEE_CUT_REF are present (good — use VUT for
    primary analysis, CUT for sensitivity checks).

  - NEE_VUT_REF_QC at DD resolution gives the gap-filled fraction (0–1),
    NOT the 0–3 integer scale used in HH FULLSET files.
    Do not compare these two QC scales directly (see CLAUDE.md).
")

## ==========================================================================
## 16. Final file inventory
## ==========================================================================

cat("\n", strrep("=", 60), "\n", "OUTPUT FILES IN data/US-MMS/\n",
    strrep("=", 60), "\n", sep = "")
for (f in list.files(out_dir, pattern = "\\.csv$", full.names = TRUE)) {
  cat(sprintf("  %-35s  %.1f MB\n", basename(f), file.size(f) / 1e6))
}

cat("\ndownload_usmms.R complete.\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Commit:", tryCatch(system("git rev-parse --short HEAD", intern = TRUE),
                        error = function(e) "unknown"), "\n")
sessionInfo()
