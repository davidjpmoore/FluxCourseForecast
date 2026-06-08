# =============================================================================
# test_student_setup.R — Fluxcourse 2026 · Tuesday AM: SSEM exercises
# =============================================================================
#
# PURPOSE
#   Run this script BEFORE the session starts to confirm your R setup is ready.
#   It checks data files, required packages, model source code, and runs a
#   quick smoke test of the SSEM model.  Fix any FAIL items before the session.
#
# HOW TO RUN
#   1. Unzip the Tuesday_AM_SSEM_part1.zip you downloaded from Google Drive.
#   2. Open RStudio (or any R console).
#   3. Set data_dir below to the path of the unzipped folder on your computer.
#      Examples:
#        Windows: data_dir <- "C:/Users/YourName/Downloads/Tuesday_AM_SSEM_part1"
#        Mac:     data_dir <- "/Users/YourName/Downloads/Tuesday_AM_SSEM_part1"
#   4. Run the whole script: Source it (Ctrl+Shift+S in RStudio) or run line by line.
#   5. Look at the final summary.  Every line should say PASS.
#      If anything says FAIL, follow the instructions printed below that line.
#
# NOTE FOR CODESPACE USERS
#   If you are running in the GitHub Codespace, keep data_dir as "../data" (the
#   default below) and run from the exercises/ directory.
# =============================================================================

# ── Step 0: set your data directory ──────────────────────────────────────────
# CHANGE THIS LINE to the path where you unzipped Tuesday_AM_SSEM_part1.zip
data_dir <- "Tuesday_AM_SSEM_part1"   # relative path: works if you run from the
                                       # same folder you unzipped into
# Or use an absolute path, e.g.:
# data_dir <- "/Users/YourName/Downloads/Tuesday_AM_SSEM_part1"
# data_dir <- "C:/Users/YourName/Downloads/Tuesday_AM_SSEM_part1"

# code_dir points to the R/ subfolder inside the unzipped data folder
code_dir <- file.path(data_dir, "R")


# =============================================================================
# Internal helper — print a coloured PASS / FAIL line
# =============================================================================
pass_fail <- function(label, ok, hint = NULL) {
  status <- if (ok) "PASS" else "FAIL"
  cat(sprintf("  [%s]  %s\n", status, label))
  if (!ok && !is.null(hint)) cat(sprintf("         --> %s\n", hint))
  invisible(ok)
}

results <- list()   # accumulate TRUE/FALSE for summary at the end

cat("\n")
cat(strrep("=", 70), "\n")
cat("  Fluxcourse 2026 — Tuesday AM SSEM setup check\n")
cat(strrep("=", 70), "\n\n")


# =============================================================================
# 1. Check that data_dir exists
# =============================================================================
cat("── 1. Data directory ───────────────────────────────────────────────────\n")

ok <- dir.exists(data_dir)
results[["data_dir"]] <- pass_fail(
  paste0("data_dir exists: ", data_dir),
  ok,
  paste0(
    "data_dir not found.  Make sure you unzipped Tuesday_AM_SSEM_part1.zip\n",
    "         and set data_dir at the top of this script to the unzipped path."
  )
)

# If data_dir doesn't exist there is no point checking individual files
if (!ok) {
  cat("\n  Cannot continue file checks — fix data_dir first.\n\n")
} else {

# =============================================================================
# 2. Check required data files
# =============================================================================
cat("\n── 2. Required data files ───────────────────────────────────────────────\n")

required_files <- list(
  # R source code
  list(rel = "R/functions.R",                      desc = "SSEM model code"),
  list(rel = "R/utils.R",                           desc = "helper utilities"),
  # Exercise 01 & 03 drivers
  list(rel = "US-NR1/US-NR1_HH.csv",               desc = "US-NR1 half-hourly drivers (Ex 01, 03)"),
  list(rel = "US-MMS/US-MMS_HR.csv",               desc = "US-MMS hourly drivers (Ex 01, 03)"),
  # Exercise 02 sub-daily observations
  list(rel = "US-NR1/US-NR1_DD.csv",               desc = "US-NR1 daily observations (Ex 02)"),
  list(rel = "US-MMS/US-MMS_DD.csv",               desc = "US-MMS daily observations (Ex 02)"),
  # Extension sites
  list(rel = "DE-Tha/DE-Tha_HH.csv",               desc = "DE-Tha half-hourly (extension)"),
  list(rel = "DE-Tha/DE-Tha_DD.csv",               desc = "DE-Tha daily (extension)"),
  list(rel = "DK-Sor/DK-Sor_HH.csv",               desc = "DK-Sor half-hourly (extension)"),
  list(rel = "DK-Sor/DK-Sor_DD.csv",               desc = "DK-Sor daily (extension)"),
  # CMIP6 — all four sites, three models each
  list(rel = "cmip6/CESM2_usnr1_monthly.csv",          desc = "CMIP6 CESM2 US-NR1"),
  list(rel = "cmip6/IPSL-CM6A-LR_usnr1_monthly.csv",   desc = "CMIP6 IPSL US-NR1"),
  list(rel = "cmip6/UKESM1-0-LL_usnr1_monthly.csv",    desc = "CMIP6 UKESM US-NR1"),
  list(rel = "cmip6/CESM2_usmms_monthly.csv",           desc = "CMIP6 CESM2 US-MMS"),
  list(rel = "cmip6/IPSL-CM6A-LR_usmms_monthly.csv",   desc = "CMIP6 IPSL US-MMS"),
  list(rel = "cmip6/UKESM1-0-LL_usmms_monthly.csv",    desc = "CMIP6 UKESM US-MMS"),
  list(rel = "cmip6/CESM2_detha_monthly.csv",           desc = "CMIP6 CESM2 DE-Tha"),
  list(rel = "cmip6/IPSL-CM6A-LR_detha_monthly.csv",   desc = "CMIP6 IPSL DE-Tha"),
  list(rel = "cmip6/UKESM1-0-LL_detha_monthly.csv",    desc = "CMIP6 UKESM DE-Tha"),
  list(rel = "cmip6/CESM2_dksor_monthly.csv",           desc = "CMIP6 CESM2 DK-Sor"),
  list(rel = "cmip6/IPSL-CM6A-LR_dksor_monthly.csv",   desc = "CMIP6 IPSL DK-Sor"),
  list(rel = "cmip6/UKESM1-0-LL_dksor_monthly.csv",    desc = "CMIP6 UKESM DK-Sor"),
  # FLUXCOM-X-BASE — all four sites
  list(rel = "fluxcom/US-NR1_fluxcom_monthly.csv",      desc = "FLUXCOM US-NR1 monthly"),
  list(rel = "fluxcom/US-MMS_fluxcom_monthly.csv",      desc = "FLUXCOM US-MMS monthly"),
  list(rel = "fluxcom/DE-Tha_fluxcom_monthly.csv",      desc = "FLUXCOM DE-Tha monthly"),
  list(rel = "fluxcom/DK-Sor_fluxcom_monthly.csv",      desc = "FLUXCOM DK-Sor monthly")
)

for (item in required_files) {
  path <- file.path(data_dir, item$rel)
  ok_f <- file.exists(path) && file.size(path) > 1000L   # > 1 kB means real data
  key  <- paste0("file_", gsub("[/ .]", "_", item$rel))
  results[[key]] <- pass_fail(
    sprintf("%-42s  %s", item$rel, item$desc),
    ok_f,
    if (!file.exists(path))
      paste0("File not found.  Re-download and re-unzip Tuesday_AM_SSEM_part1.zip")
    else
      paste0("File is empty or too small (", file.size(path), " bytes).  ",
             "Re-download the zip.")
  )
}

}   # end if data_dir exists


# =============================================================================
# 3. Check required R packages
# =============================================================================
cat("\n── 3. Required R packages ───────────────────────────────────────────────\n")

required_pkgs <- c("tidyverse", "lubridate", "rmarkdown", "compiler", "mvtnorm")

for (pkg in required_pkgs) {
  ok_p <- requireNamespace(pkg, quietly = TRUE)
  key  <- paste0("pkg_", pkg)
  results[[key]] <- pass_fail(
    sprintf("%-15s installed", pkg),
    ok_p,
    sprintf('Run:  install.packages("%s")', pkg)
  )
}


# =============================================================================
# 4. Source model code
# =============================================================================
cat("\n── 4. Model source code ────────────────────────────────────────────────\n")

functions_path <- file.path(code_dir, "functions.R")
utils_path     <- file.path(code_dir, "utils.R")

ok_fn <- tryCatch({
  if (!file.exists(functions_path)) stop("not found")
  source(functions_path)
  TRUE
}, error = function(e) {
  cat(sprintf("         Error sourcing functions.R: %s\n", conditionMessage(e)))
  FALSE
})
results[["source_functions"]] <- pass_fail(
  "source(functions.R) — SSEM model and particle filter",
  ok_fn,
  "Check that data_dir is set correctly and the R/ subfolder is present."
)

ok_ut <- tryCatch({
  if (!file.exists(utils_path)) stop("not found")
  source(utils_path)
  TRUE
}, error = function(e) {
  cat(sprintf("         Error sourcing utils.R: %s\n", conditionMessage(e)))
  FALSE
})
results[["source_utils"]] <- pass_fail(
  "source(utils.R) — helper functions",
  ok_ut,
  "Check that data_dir is set correctly and the R/ subfolder is present."
)


# =============================================================================
# 5. Smoke test: load 48 timesteps of US-NR1 drivers, run ensemble_forecast()
# =============================================================================
cat("\n── 5. SSEM smoke test (ne=5, 48 timesteps) ──────────────────────────────\n")

ok_smoke <- FALSE

if (ok_fn && ok_ut && dir.exists(data_dir)) {
  ok_smoke <- tryCatch({
    library(readr,    quietly = TRUE, warn.conflicts = FALSE)
    library(lubridate,quietly = TRUE, warn.conflicts = FALSE)

    hr_path <- file.path(data_dir, "US-NR1", "US-NR1_HH.csv")
    if (!file.exists(hr_path)) stop("US-NR1_HH.csv not found")

    # Load just enough rows for the smoke test — the file is large but we only
    # need the first 48 half-hourly rows (one day).
    nr1_head <- read_csv(hr_path, n_max = 100L, show_col_types = FALSE)
    nr1_head <- nr1_head |>
      dplyr::mutate(across(where(is.numeric), \(x) replace(x, x == -9999, NA))) |>
      dplyr::filter(!is.na(SW_IN_F), !is.na(TA_F)) |>
      head(48)

    if (nrow(nr1_head) < 48) stop("fewer than 48 usable rows after NA removal")

    # Assemble driver data frame for SSEM (exactly 2 columns required)
    drivers_test <- data.frame(
      PAR  = pmax(nr1_head$SW_IN_F * 2.1, 0),
      temp = nr1_head$TA_F
    )

    # Tiny ensemble: ne=5 members to keep it fast (~1 second)
    ne <- 5L
    set.seed(42L)

    # Initial conditions (one row per ensemble member)
    X_test <- matrix(c(3.0, 100.0, 100.0), nrow = ne, ncol = 3, byrow = TRUE)

    # Minimal parameter set (draw from the same distributions as the exercises)
    params_test <- data.frame(
      alpha      = rep(0.02,   ne),
      SLA        = rep(8.0,    ne),
      Rbasal     = rep(0.015,  ne),
      Q10        = rep(2.0,    ne),
      litterfall = rep(1.4e-5, ne),
      mortality  = rep(7.1e-7, ne),
      sigma.leaf = rep(0.01,   ne),
      sigma.stem = rep(0.10,   ne),
      sigma.soil = rep(0.10,   ne)
    )
    falloc <- rdirichlet.orig(ne, alpha = c(5, 3, 2))
    params_test$falloc.1 <- falloc[, 1]
    params_test$falloc.2 <- falloc[, 2]
    params_test$falloc.3 <- falloc[, 3]

    # Run the model
    out_test <- ensemble_forecast(X_test, params_test, drivers_test)

    # Verify dimensions: [48 timesteps × 5 members × 12 variables]
    expected_dim <- c(48L, 5L, 12L)
    if (!identical(dim(out_test), expected_dim)) {
      stop(sprintf("Wrong output dimensions: %s (expected %s)",
                   paste(dim(out_test), collapse = " × "),
                   paste(expected_dim,  collapse = " × ")))
    }

    cat(sprintf("         Output dimensions: %s  (timesteps × ensemble × variables)\n",
                paste(dim(out_test), collapse = " × ")))
    cat(sprintf("         GPP median at step 24 (midday): %.3f umol CO2 m-2 s-1\n",
                median(out_test[24L, , 5L], na.rm = TRUE)))

    TRUE

  }, error = function(e) {
    cat(sprintf("         Smoke test error: %s\n", conditionMessage(e)))
    FALSE
  })
}

results[["smoke_test"]] <- pass_fail(
  "SSEM smoke test — ensemble_forecast() with ne=5, 48 timesteps",
  ok_smoke,
  paste0(
    "Smoke test failed.  Check that functions.R sourced correctly (Step 4)\n",
    "         and that US-NR1_HH.csv exists and has data (Step 2)."
  )
)


# =============================================================================
# Final summary
# =============================================================================
cat("\n")
cat(strrep("=", 70), "\n")

n_pass <- sum(unlist(results))
n_fail <- length(results) - n_pass

if (n_fail == 0L) {
  cat("  READY TO START — all", n_pass, "checks passed.\n")
  cat("  Open exercises/01_run_model.Rmd in RStudio and start knitting!\n")
} else {
  cat(sprintf("  %d / %d checks passed.  Fix the FAIL items above before the session.\n",
              n_pass, length(results)))
  cat("  If you cannot resolve an issue, contact the instructors:\n")
  cat("    David Moore  <davidjpmoore@arizona.edu>\n")
}

cat(strrep("=", 70), "\n\n")
