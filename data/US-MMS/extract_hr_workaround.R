## =============================================================================
## extract_hr_workaround.R
##
## PURPOSE
## -------
## This script is a standalone workaround for a bug in the fluxnet R package
## (v0.3.1) that causes flux_extract() to silently skip the half-hourly (HR)
## data files present in the AmeriFlux FLUXNET v1.3_r1 product.
##
## THE BUG
## -------
## flux_extract() in fluxnet v0.3.1 matches filenames using the pattern "_HH_",
## which was the convention in the legacy FLUXNET-2015 product for half-hourly
## data.  The AmeriFlux FLUXNET v1.3_r1 product changed this naming convention
## and now uses "_HR_" for the same time resolution.  For example:
##
##   Old (FLUXNET-2015):   AMF_US-MMS_FLUXNET_FLUXMET_HH_1999-2023_v1.2.zip
##   New (v1.3_r1):        AMF_US-MMS_FLUXNET_FLUXMET_HR_1999-2023_v1.3_r1.csv
##
## Because no filenames inside the v1.3_r1 ZIP match "_HH_", flux_extract()
## extracts all the coarser-resolution aggregations (DD, WW, MM, YY) and
## simply never touches the HR files — without printing any warning.
##
## This script bypasses flux_extract() entirely and reads the HR files directly
## from the ZIP using the zip package, which has no awareness of these naming
## conventions and will extract whatever you ask it to.
##
## UPSTREAM ISSUE
## --------------
## Tracked at: https://github.com/EcosystemEcologyLab/fluxnet-package/issues
## Issue title: HR files silently skipped in v0.3.1
##
## When a fix is released, this workaround should be retired and replaced with
## the standard flux_extract() + flux_read() workflow in download_usmms.R.
##
## OUTPUTS
## -------
##   data/US-MMS/US-MMS_HR.csv       — FLUXMET half-hourly, -9999 replaced with NA
##   data/US-MMS/US-MMS_ERA5_HR.csv  — ERA5 reanalysis half-hourly, -9999 → NA
##
## PREREQUISITES
## -------------
##   Packages: zip, data.table
##   Input:    data/US-MMS/raw/AMF_US-MMS_FLUXNET_*.zip must already exist.
##             Run data/US-MMS/download_usmms.R first if the ZIP is absent.
##
## HOW TO RUN
## ----------
##   From the project root (not from data/US-MMS/):
##     Rscript data/US-MMS/extract_hr_workaround.R
##   Or from inside an R session:
##     source("data/US-MMS/extract_hr_workaround.R")
## =============================================================================

## ---------------------------------------------------------------------------
## Metadata header — printed at the start so any log output is timestamped
## and pinned to a specific git commit for reproducibility.
## ---------------------------------------------------------------------------
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Commit:", tryCatch(system("git rev-parse --short HEAD", intern = TRUE),
                        error = function(e) "unknown"), "\n\n")

## ---------------------------------------------------------------------------
## 0. Packages
## ---------------------------------------------------------------------------
## zip:        Provides zip_list() (reads the ZIP index without decompressing
##             any data) and unzip() (extracts selected entries).  The zip
##             package masks utils::unzip() — that is intentional here.
##
## data.table: fread() is the fastest CSV reader in R for large files.  The
##             FLUXMET HR file is ~302 MB uncompressed; fread() reads it with
##             multi-threading and low overhead.
## ---------------------------------------------------------------------------

if (!requireNamespace("zip", quietly = TRUE))
  stop("The 'zip' package is required. Install it with: install.packages('zip')")
if (!requireNamespace("data.table", quietly = TRUE))
  stop("The 'data.table' package is required. Install it with: install.packages('data.table')")

library(zip)         # zip_list(), unzip() — overwrites utils::unzip intentionally
library(data.table)  # fread(), fwrite()

## ---------------------------------------------------------------------------
## 1. Directory paths
## ---------------------------------------------------------------------------
## All paths are relative to the project root so the script works whether you
## source() it from inside R or run it with Rscript from the command line.

out_dir   <- file.path("data", "US-MMS")    # processed CSVs (git-tracked)
raw_dir   <- file.path(out_dir, "raw")      # downloaded ZIPs (git-ignored)
unzip_dir <- file.path(raw_dir, "unzipped") # extracted files

## Create the extraction directory if it does not already exist.
## (It should already be there from the flux_extract() run in download_usmms.R,
## but we create it here defensively so this script can run stand-alone.)
dir.create(unzip_dir, showWarnings = FALSE, recursive = TRUE)

## ---------------------------------------------------------------------------
## 2. Locate the ZIP file programmatically
## ---------------------------------------------------------------------------
## We do NOT hardcode "AMF_US-MMS_FLUXNET_1999-2023_v1.3_r1.zip" because
## AmeriFlux may release updated versions (e.g., _v1.3_r2) that increment the
## version suffix.  The glob pattern below matches any version.

zip_files <- list.files(
  path    = raw_dir,
  pattern = "^AMF_US-MMS_FLUXNET_.*\\.zip$",
  full.names = TRUE
)

if (length(zip_files) == 0) {
  stop(
    "No AMF_US-MMS_FLUXNET_*.zip found in: ", raw_dir, "\n",
    "Run data/US-MMS/download_usmms.R first to download the data."
  )
}

if (length(zip_files) > 1) {
  ## More than one version present.  Warn and use the alphabetically last one,
  ## which will be the most recent revision (r1, r2, ... sort correctly).
  warning(
    length(zip_files), " ZIP files found — using the last one alphabetically:\n",
    paste("  ", basename(zip_files), collapse = "\n")
  )
  zip_files <- tail(sort(zip_files), 1)
}

zip_path <- zip_files[1]
cat("ZIP file selected:", zip_path, "\n")
cat(sprintf("  (size on disk: %.1f MB)\n\n", file.size(zip_path) / 1e6))

## ---------------------------------------------------------------------------
## 3. Inspect the ZIP and confirm the three HR files are present
## ---------------------------------------------------------------------------
## zip_list() reads the ZIP's central directory — a small index at the end of
## the file — without decompressing any of the actual data.  This is fast even
## for large ZIPs and lets us verify the expected files exist before we commit
## to a potentially time-consuming extraction.

cat(strrep("=", 70), "\n")
cat("STEP 3: Inspecting ZIP contents\n")
cat(strrep("=", 70), "\n\n")

zip_contents <- zip::zip_list(zip_path)

## Show the full manifest so users can see everything in the ZIP.
cat("All entries in ZIP:\n")
cat(sprintf("  %-65s  %15s\n", "Filename", "Uncompressed"))
cat(sprintf("  %s  %s\n", strrep("-", 65), strrep("-", 15)))
for (i in seq_len(nrow(zip_contents))) {
  cat(sprintf("  %-65s  %15s\n",
              zip_contents$filename[i],
              format(zip_contents$uncompressed_size[i],
                     big.mark = ",", scientific = FALSE)))
}

## Filter to HR files only.
## The pattern "_HR_" uniquely identifies the half-hourly entries in the v1.3_r1
## naming convention.  If AmeriFlux changes this again in a future version, this
## grep() will stop matching and the script will tell you explicitly.
hr_entries <- zip_contents[grepl("_HR_", zip_contents$filename), ]

cat(sprintf("\nHR files found: %d (expected: 3)\n", nrow(hr_entries)))
cat(sprintf("  %-65s  %15s\n", "Filename", "Uncompressed"))
cat(sprintf("  %s  %s\n", strrep("-", 65), strrep("-", 15)))
for (i in seq_len(nrow(hr_entries))) {
  cat(sprintf("  %-65s  %15s bytes\n",
              hr_entries$filename[i],
              format(hr_entries$uncompressed_size[i],
                     big.mark = ",", scientific = FALSE)))
}

## Hard stop if we do not see exactly 3 HR entries.
## Expected: FLUXMET_HR, ERA5_HR, BIFVARINFO_HR.
if (nrow(hr_entries) != 3) {
  stop(
    "Expected exactly 3 HR files (FLUXMET, ERA5, BIFVARINFO) but found ",
    nrow(hr_entries), ".\n",
    "The ZIP structure may have changed. Inspect zip_contents printed above."
  )
}
cat("\nAll 3 HR files confirmed present in ZIP.\n")

## ---------------------------------------------------------------------------
## 4. Extract only the HR files from the ZIP
## ---------------------------------------------------------------------------
## We pass hr_entries$filename as the 'files' argument to extract only those
## three entries, avoiding the need to re-decompress the large DD/WW/MM/YY
## files that were already extracted by flux_extract() in download_usmms.R.
##
## junkpaths = TRUE: discard any directory prefix stored inside the ZIP and
## write the files directly into exdir.  The HR entries in this ZIP have no
## directory prefix (they are at the ZIP root), so junkpaths = TRUE is both
## consistent with the actual structure and robust against future versions that
## might add a subdirectory layer.

cat("\n", strrep("=", 70), "\n", sep = "")
cat("STEP 4: Extracting HR files\n")
cat(strrep("=", 70), "\n\n")

cat("Extracting to:", unzip_dir, "\n")
cat("(This may take 30–90 seconds for the 302 MB FLUXMET file.)\n\n")

zip::unzip(
  zipfile   = zip_path,
  files     = hr_entries$filename,  # extract only these three entries
  exdir     = unzip_dir,
  junkpaths = TRUE                  # write flat, no subdirectory nesting
)

## Verify each extracted file actually landed on disk.
extracted_paths <- file.path(unzip_dir, basename(hr_entries$filename))
cat("Extracted files:\n")
for (p in extracted_paths) {
  if (!file.exists(p)) {
    stop("Expected extracted file not found after unzip: ", p,
         "\nThis is unexpected — check that the ZIP is not corrupted.")
  }
  cat(sprintf("  %-65s  %.1f MB\n", basename(p), file.size(p) / 1e6))
}

## ---------------------------------------------------------------------------
## 5. Identify which extracted path is FLUXMET and which is ERA5
## ---------------------------------------------------------------------------
## We grep the path string rather than relying on positional order so that if
## the ZIP's internal ordering changes between product versions, the assignment
## still works correctly.

fluxmet_path <- extracted_paths[grepl("FLUXMET", extracted_paths)]
era5_path    <- extracted_paths[grepl("ERA5",    extracted_paths)]

if (length(fluxmet_path) != 1)
  stop("Could not uniquely identify the FLUXMET HR file among: ",
       paste(basename(extracted_paths), collapse = ", "))
if (length(era5_path) != 1)
  stop("Could not uniquely identify the ERA5 HR file among: ",
       paste(basename(extracted_paths), collapse = ", "))

cat("\nFLUXMET HR path: ", fluxmet_path, "\n")
cat("ERA5 HR path:    ", era5_path, "\n")

## ---------------------------------------------------------------------------
## 6. Helper function: read a FLUXNET CSV and replace -9999 with NA
## ---------------------------------------------------------------------------
## FLUXNET products use -9999 as the universal missing-value sentinel for all
## numeric data columns.  By passing na.strings = "-9999" to fread(), we ask
## data.table to recognise the string "-9999" as a missing value at parse time.
## This is more efficient than reading the data and then doing a post-hoc
## replacement because fread() allocates NA directly without allocating -9999
## first and then overwriting it.
##
## The timestamp columns (TIMESTAMP_START, TIMESTAMP_END) contain 12-digit
## integers in YYYYMMDDHHMM format (e.g., 199901010000 = midnight 1 Jan 1999).
## These integers exceed the range of 32-bit integers, so fread() reads them as
## 64-bit integers (integer64 from the bit64 package) or as numeric doubles —
## both are fine for the date-parsing we do in the summary step below.

read_fluxnet_hr <- function(path) {
  message("Reading: ", basename(path), " ...")
  dt <- data.table::fread(
    file         = path,
    na.strings   = c("NA", "-9999"),  # FLUXNET missing-value sentinel → NA
    showProgress = TRUE               # print a progress bar for large files
  )
  message(sprintf("  Done: %s rows x %d columns",
                  format(nrow(dt), big.mark = ","), ncol(dt)))
  dt
}

## ---------------------------------------------------------------------------
## 7. Read FLUXMET HR file and save
## ---------------------------------------------------------------------------
## FLUXMET contains the eddy covariance measurements and gap-filled met drivers
## for Morgan Monroe State Forest (US-MMS), 1999–2023, at half-hourly resolution.
##
## Variables used in FluxCourseForecast:
##   NEE_VUT_REF      net ecosystem exchange (umol m-2 s-1),
##                    variable u* threshold partitioning
##   GPP_NT_VUT_REF   gross primary production (umol m-2 s-1),
##                    nighttime partitioning method
##   SW_IN_F          incoming shortwave radiation (W m-2), ERA5-filled
##   TA_F             air temperature (deg C), ERA5-filled
##   VPD_F            vapour pressure deficit (hPa), ERA5-filled
##   NEE_VUT_REF_QC   QC flag: 0 = measured, 1–3 = increasing gap-fill reliance

cat("\n", strrep("=", 70), "\n", sep = "")
cat("STEP 7: Reading FLUXMET HR file\n")
cat(strrep("=", 70), "\n\n")

hr_fluxmet <- read_fluxnet_hr(fluxmet_path)

hr_fluxmet_out <- file.path(out_dir, "US-MMS_HR.csv")
message("Saving to: ", hr_fluxmet_out)
data.table::fwrite(hr_fluxmet, hr_fluxmet_out)
message(sprintf("  Saved: %.1f MB\n", file.size(hr_fluxmet_out) / 1e6))

## ---------------------------------------------------------------------------
## 8. Read ERA5 HR file and save
## ---------------------------------------------------------------------------
## ERA5 contains the ECMWF reanalysis meteorological variables interpolated to
## the US-MMS grid cell, 1981–2025.  The record predates the tower installation
## (1999) by 18 years; ERA5 values before 1999 have no tower constraint and
## represent pure reanalysis climatology.
##
## ERA5 provides a gap-free forcing record useful for driving the SSEM model
## during periods when tower met observations are unavailable.
##
## Key variables:
##   TA_ERA      air temperature from ERA5 (deg C)
##   SW_IN_ERA   incoming shortwave radiation from ERA5 (W m-2)
##   VPD_ERA     vapour pressure deficit from ERA5 (hPa)

cat("\n", strrep("=", 70), "\n", sep = "")
cat("STEP 8: Reading ERA5 HR file\n")
cat(strrep("=", 70), "\n\n")

hr_era5 <- read_fluxnet_hr(era5_path)

hr_era5_out <- file.path(out_dir, "US-MMS_ERA5_HR.csv")
message("Saving to: ", hr_era5_out)
data.table::fwrite(hr_era5, hr_era5_out)
message(sprintf("  Saved: %.1f MB\n", file.size(hr_era5_out) / 1e6))

## ---------------------------------------------------------------------------
## 9. Confirmation summaries
## ---------------------------------------------------------------------------
## For each output file we print:
##   - Row count and column count
##   - Date range derived from TIMESTAMP_START (YYYYMMDDHHMM integer format)
##   - Whether the variables required by FluxCourseForecast are present
##
## If any required variable is absent, we print a warning rather than stopping,
## because the data is still useful and the student should investigate.

## Helper: convert a YYYYMMDDHHMM integer column to a Date vector.
## We extract only the first 8 characters (YYYYMMDD) and parse as a Date.
## as.character() handles both integer and integer64 (bit64) types safely.
ts_to_date <- function(ts_col) {
  as.Date(substr(as.character(ts_col), 1, 8), format = "%Y%m%d")
}

## Helper: print one summary block.
## 'required_vars' is a character vector of column names that must be present.
print_summary <- function(dt, label, required_vars) {
  cat("\n", strrep("-", 70), "\n", sep = "")
  cat("SUMMARY:", label, "\n")
  cat(strrep("-", 70), "\n")

  ## Basic dimensions
  cat(sprintf("  Rows:    %s\n", format(nrow(dt), big.mark = ",")))
  cat(sprintf("  Columns: %d\n", ncol(dt)))

  ## Date range from the TIMESTAMP_START column.
  ## FLUXNET FULLSET files always contain TIMESTAMP_START for sub-daily data.
  if ("TIMESTAMP_START" %in% names(dt)) {
    dates <- ts_to_date(dt[["TIMESTAMP_START"]])
    dates <- dates[!is.na(dates)]
    if (length(dates) > 0) {
      cat(sprintf("  Date range: %s  to  %s\n", min(dates), max(dates)))
    } else {
      cat("  WARNING: TIMESTAMP_START could not be parsed as dates.\n")
    }
  } else {
    cat("  WARNING: TIMESTAMP_START column not found — cannot determine date range.\n")
  }

  ## Required variable check
  present <- required_vars[required_vars %in%  names(dt)]
  absent  <- required_vars[!required_vars %in% names(dt)]

  cat(sprintf("  Required variables (%d checked):\n", length(required_vars)))
  for (v in present) cat(sprintf("    [OK]     %s\n", v))
  for (v in absent)  cat(sprintf("    [MISSING] %s  <-- WARNING\n", v))

  if (length(absent) == 0) {
    cat("  All required variables confirmed present.\n")
  } else {
    warning("Missing required variables in ", label, ": ",
            paste(absent, collapse = ", "))
  }
}

## Variables that the FluxCourseForecast exercises require from each file.
## Defined here so they are easy to update if the exercises change.
fluxmet_required <- c("NEE_VUT_REF", "SW_IN_F", "TA_F")
era5_required    <- c("TA_ERA", "SW_IN_ERA")

cat("\n", strrep("=", 70), "\n", sep = "")
cat("STEP 9: Confirmation summaries\n")
cat(strrep("=", 70), "\n")

print_summary(hr_fluxmet, "US-MMS_HR.csv (FLUXMET half-hourly)",   fluxmet_required)
print_summary(hr_era5,    "US-MMS_ERA5_HR.csv (ERA5 half-hourly)", era5_required)

## ---------------------------------------------------------------------------
## 10. Final output inventory
## ---------------------------------------------------------------------------

cat("\n", strrep("=", 70), "\n", sep = "")
cat("OUTPUT FILES WRITTEN\n")
cat(strrep("=", 70), "\n")
for (f in c(hr_fluxmet_out, hr_era5_out)) {
  cat(sprintf("  %-40s  %.1f MB\n", basename(f), file.size(f) / 1e6))
}

cat("\nextract_hr_workaround.R complete.\n")
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Commit:", tryCatch(system("git rev-parse --short HEAD", intern = TRUE),
                        error = function(e) "unknown"), "\n")
sessionInfo()
