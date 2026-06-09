#!/usr/bin/env Rscript
# =============================================================================
# run_full_record.R — FluxCourseForecast 2026
#
# Runs the Super Simple Ecosystem Model (SSEM) forward over the full
# observational record at two AmeriFlux sites:
#   US-NR1  Niwot Ridge, CO (ENF, subalpine), 1998–2023
#   US-MMS  Morgan Monroe State Forest, IN (DBF, temperate), 1999–2023
#
# The model runs with ne = 20 ensemble members — smaller than the student
# exercise (ne = 100) but sufficient for dashboard uncertainty ribbons.
# State (Bleaf, Bwood, BSOM) is carried forward from year to year, so the
# soil carbon pool accumulates continuously rather than resetting each January.
#
# Parameters are drawn once at the top and held fixed throughout.  This is
# an open-loop forecast (no particle filter / data assimilation).  The
# parameters match Exercise 01: ENF values for US-NR1, DBF values for US-MMS.
#
# This script is intended for INSTRUCTOR use only.  It should NOT be run by
# students during the exercises.  Typical run time: 20–40 minutes on a
# modern laptop.
#
# Run from the repo root:
#   Rscript exercises/run_full_record.R
#
# Output (gitignored — large generated files):
#   data/ssem_usnr1_fullrecord.rds
#   data/ssem_usmms_fullrecord.rds
#
# Each RDS is a named list:
#   $output        — array [total_timesteps × ne × 12], same layout as the
#                    student RDS files (12 SSEM variables defined in functions.R)
#   $years         — integer vector of calendar years that were actually run
#   $steps_per_day — integer, 48 for US-NR1 (HH) or 24 for US-MMS (HR)
#   $ne            — integer ensemble size (20)
#   $site          — character site ID
# =============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
})

Sys.setenv(RENV_CONFIG_SYNCHRONIZED_CHECK = "FALSE")

cat("=== FluxCourseForecast 2026 — Full-Record SSEM Runner ===\n\n")

# ─── Source SSEM code ─────────────────────────────────────────────────────────
# functions.R contains ensemble_forecast(), SSEM(), rdirichlet.orig(), and
# helper utilities.  It must be sourced before any SSEM calls.
source("R/functions.R")
source("R/utils.R")

# ─── Ensemble size ────────────────────────────────────────────────────────────
# ensemble_forecast() reads 'ne' from the calling environment (global scope).
# Set it here before any call to ensemble_forecast().
#
# ne = 20 is deliberately smaller than the student exercise (ne = 100).
# It is sufficient for computing 95% credible intervals for the dashboard
# but runs ~5× faster per year.  Increasing ne gives wider, more stable
# uncertainty bands at the cost of proportionally longer run time and larger
# RDS files.
ne <- 20L

# Fix the random seed for reproducible parameter draws.
# Using the same seed as Exercise 01 (2026) so that parameter distributions
# are conceptually aligned, even though the specific draws differ because ne
# here is 20, not 100.
set.seed(2026)


# =============================================================================
# Helper: concatenate a list of 3-D arrays along time dimension
# =============================================================================

#' Concatenate yearly SSEM output arrays along the time axis
#'
#' @param arr_list Named list of 3-D arrays [n_t × ne × 12], one per year.
#'   All arrays must share the same ne and variable dimensions.
#' @return A single 3-D array [total_timesteps × ne × 12] with years stacked
#'   in chronological order.
combine_arrays <- function(arr_list) {
  n_total <- sum(vapply(arr_list, function(a) dim(a)[1L], integer(1L)))
  n_ens   <- dim(arr_list[[1L]])[2L]
  n_var   <- dim(arr_list[[1L]])[3L]
  out     <- array(NA_real_, dim = c(n_total, n_ens, n_var))
  pos     <- 1L
  for (a in arr_list) {
    n          <- dim(a)[1L]
    out[pos:(pos + n - 1L), , ] <- a
    pos        <- pos + n
  }
  out
}


# =============================================================================
# Helper: build ENF parameter ensemble (US-NR1, subalpine conifers)
# =============================================================================

#' Draw ENF parameter ensemble for SSEM
#'
#' Parameters match Exercise 01 (Section "Parameters and initial conditions
#' US-NR1") with ne set by the global environment.  See the exercise for
#' detailed biological justification of each prior.
#'
#' @return A data.frame with ne rows and 12 parameter columns.
make_params_enf <- function() {
  params <- data.frame(
    # alpha: canopy light use efficiency (umol CO2 per umol photon absorbed)
    # Subalpine conifers at high elevation: 0.015–0.025 umol umol^-1
    alpha       = rnorm(ne, mean = 0.02,   sd = 0.003)  |> pmax(0),

    # SLA: specific leaf area (m^2 leaf kg^-1 leaf dry mass)
    # Conifer needles are thick and dense: 4–10 m^2 kg^-1 for Engelmann spruce
    SLA         = rnorm(ne, mean = 8.0,    sd = 1.2)    |> pmax(1),

    # Rbasal: basal heterotrophic respiration rate at 0 °C
    # Rh = Rbasal × BSOM × Q10^(temp / 10)
    Rbasal      = rnorm(ne, mean = 0.015,  sd = 0.003)  |> pmax(0),

    # Q10: temperature sensitivity of heterotrophic respiration (dimensionless)
    Q10         = rnorm(ne, mean = 2.0,    sd = 0.3)    |> pmax(1),

    # litterfall: fraction of leaf C transferred to BSOM per 30-min timestep.
    # Subalpine fir needles live ~4 years → annual turnover ~25%.
    # Per 30-min step: 0.25 / (365 × 48) ≈ 1.4 × 10^-5
    litterfall  = rnorm(ne, mean = 1.4e-5, sd = 1.5e-6) |> pmax(0),

    # mortality: fraction of wood C transferred to BSOM per 30-min timestep.
    # ~80-yr stand rotation → ~1.25% yr^-1.
    # Per 30-min step: 0.0125 / (365 × 48) ≈ 7.1 × 10^-7
    mortality   = rnorm(ne, mean = 7.1e-7, sd = 7e-8)   |> pmax(0),

    # Process noise on pool updates (Mg C ha^-1 per timestep).
    # Small noise keeps the ensemble from collapsing to a point solution.
    sigma.leaf  = rep(0.01, ne),
    sigma.stem  = rep(0.10, ne),
    sigma.soil  = rep(0.10, ne)
  )

  # Carbon allocation fractions (Dirichlet draw, must sum to 1 per row):
  #   falloc.1 → Ra   (autotrophic respiration): 50% expected
  #   falloc.2 → NPPw (wood growth):             30% expected
  #   falloc.3 → NPPl (leaf growth):             20% expected
  # Carbon use efficiency (CUE = NPP/GPP) ≈ 0.50 for ENF
  fa <- rdirichlet.orig(ne, alpha = c(5, 3, 2))
  params$falloc.1 <- fa[, 1]
  params$falloc.2 <- fa[, 2]
  params$falloc.3 <- fa[, 3]

  stopifnot(all(abs(rowSums(params[, c("falloc.1","falloc.2","falloc.3")]) - 1) < 1e-10))
  params
}


# =============================================================================
# Helper: build DBF parameter ensemble (US-MMS, deciduous broadleaf)
# =============================================================================

#' Draw DBF parameter ensemble for SSEM
#'
#' Parameters match Exercise 01 (Section "Parameters and initial conditions
#' US-MMS").  The key difference from ENF is the faster litterfall rate
#' (1-yr leaf longevity vs 4-yr for ENF) and higher leaf allocation fraction.
#'
#' @return A data.frame with ne rows and 12 parameter columns.
make_params_dbf <- function() {
  # Deciduous trees shed their entire canopy each autumn: ~100% annual
  # leaf turnover.  Per 30-min step, this is 1.0 / (365 × 48).  Note that
  # this rate is expressed per 30-min step because SSEM's internal timestep
  # constant (k in functions.R) is hardcoded to 1800 s.  US-MMS data is
  # hourly (3600 s), which is a known limitation documented in CLAUDE.md.
  lf_dbf <- 1.0 / (365L * 48L)  # per 30-min step

  params <- data.frame(
    alpha       = rnorm(ne, mean = 0.02,  sd = 0.003)  |> pmax(0),

    # DBF leaves are thinner than conifer needles: 12–25 m^2 kg^-1
    SLA         = rnorm(ne, mean = 15.0,  sd = 2.0)    |> pmax(1),

    Rbasal      = rnorm(ne, mean = 0.015, sd = 0.003)  |> pmax(0),
    Q10         = rnorm(ne, mean = 2.0,   sd = 0.3)    |> pmax(1),

    # Deciduous: 100% annual leaf turnover per 30-min step
    litterfall  = rnorm(ne, mean = lf_dbf, sd = lf_dbf * 0.1) |> pmax(0),

    # Woody mortality rate: same as ENF
    mortality   = rnorm(ne, mean = 7.1e-7, sd = 7e-8) |> pmax(0),

    sigma.leaf  = rep(0.01, ne),
    sigma.stem  = rep(0.10, ne),
    sigma.soil  = rep(0.10, ne)
  )

  # Carbon allocation fractions for DBF:
  #   falloc.1 → Ra   40%  (lower respiration cost than ENF)
  #   falloc.2 → NPPw 30%
  #   falloc.3 → NPPl 30%  (more carbon to leaves because canopy is rebuilt yearly)
  # CUE ≈ 0.60 for deciduous forests (Malhi 2012)
  fa <- rdirichlet.orig(ne, alpha = c(4, 3, 3))
  params$falloc.1 <- fa[, 1]
  params$falloc.2 <- fa[, 2]
  params$falloc.3 <- fa[, 3]

  stopifnot(all(abs(rowSums(params[, c("falloc.1","falloc.2","falloc.3")]) - 1) < 1e-10))
  params
}


# =============================================================================
# Helper: initial carbon pool conditions (same for both sites)
# =============================================================================

#' Create initial condition matrix for SSEM
#'
#' @param bleaf  Initial leaf carbon (Mg C ha^-1)
#' @param bwood  Initial wood carbon (Mg C ha^-1)
#' @param bsom   Initial soil organic carbon (Mg C ha^-1)
#' @return A matrix [ne × 3] of initial pool sizes.
make_X0 <- function(bleaf = 3.0, bwood = 100.0, bsom = 100.0) {
  X <- matrix(NA_real_, nrow = ne, ncol = 3)
  X[, 1] <- bleaf   # Bleaf: leaf carbon
  X[, 2] <- bwood   # Bwood: wood carbon
  X[, 3] <- bsom    # BSOM: soil organic matter
  X
}


# =============================================================================
# Main: run one site over its full record
# =============================================================================

#' Run SSEM over the full observational record for one site
#'
#' Loads the full sub-daily driver file, loops year by year, runs
#' ensemble_forecast() for each year, and concatenates outputs into one
#' 3-D array.  The ensemble state (carbon pool sizes) is carried forward
#' from the last timestep of year y to the first timestep of year y+1.
#'
#' @param site_id      Character site code, e.g. "US-NR1".
#' @param driver_file  Path to the sub-daily FLUXNET CSV (HH or HR product).
#' @param years        Integer vector of calendar years to process.
#' @param steps_per_day Integer, 48 for half-hourly or 24 for hourly drivers.
#' @param ts_col       Name of the timestamp column in the driver CSV.
#' @param ts_type      Either "iso8601" (DATETIME_START) or "yyyymmddhhmm"
#'                     (TIMESTAMP_START integer format used by US-MMS).
#' @param params       data.frame of SSEM parameter ensemble (ne rows).
#' @param X0           Matrix [ne × 3] of initial pool conditions.
#' @param out_path     File path for the output RDS.
#' @return Named list with elements $output, $years, $steps_per_day, $ne, $site.
run_site <- function(site_id, driver_file, years, steps_per_day,
                     ts_col, ts_type, params, X0, out_path) {

  cat(sprintf("\n--- %s ---\n", site_id))
  cat(sprintf("  Requested years:  %d–%d (%d years)\n",
              min(years), max(years), length(years)))
  cat(sprintf("  Steps per day:    %d (timestep = %d s)\n",
              steps_per_day, (24L * 60L / steps_per_day) * 60L))
  cat(sprintf("  Ensemble size:    ne = %d\n", ne))

  # ── Load entire driver file into memory (done once; ~30–60 s for large files)
  cat(sprintf("  Reading %s ...\n", basename(driver_file)))
  t_read <- proc.time()
  raw <- read_csv(driver_file, show_col_types = FALSE)

  # Replace the FLUXNET missing-value sentinel (-9999) with NA throughout.
  raw <- raw |>
    mutate(across(where(is.numeric), \(x) replace(x, x == -9999, NA)))

  # ── Parse the timestamp column to POSIXct ────────────────────────────────
  # US-NR1 uses DATETIME_START in ISO 8601 format.  readr auto-parses this
  # as POSIXct; we reference it directly without re-parsing.
  #
  # US-MMS uses TIMESTAMP_START as an integer in YYYYMMDDHHMM format.
  # We convert to character first so as.POSIXct() can apply the format string.
  if (ts_type == "iso8601") {
    raw <- raw |> mutate(datetime = .data[[ts_col]])
  } else {
    raw <- raw |>
      mutate(datetime = as.POSIXct(
        as.character(.data[[ts_col]]),
        format = "%Y%m%d%H%M", tz = "UTC"
      ))
  }

  # ── PAR conversion and temperature ──────────────────────────────────────
  # SSEM expects two driver columns: PAR (umol photon m^-2 s^-1) and temp (°C).
  # SW_IN_F is gap-filled incoming shortwave radiation in W m^-2.
  # PAR occupies 400–700 nm, roughly 45% of total shortwave.
  # 1 W m^-2 in the PAR waveband ≈ 4.6 umol photons.
  # Combined conversion: PAR ≈ SW_IN_F × 0.45 × 4.6 ≈ SW_IN_F × 2.1.
  # TA_F is already in °C; no unit conversion needed.
  raw <- raw |>
    mutate(
      PAR  = pmax(SW_IN_F * 2.1, 0),
      temp = TA_F
    )

  cat(sprintf("  Driver loaded: %d rows (%.1f s)\n",
              nrow(raw), (proc.time() - t_read)["elapsed"]))

  # ── Year-by-year forward simulation ──────────────────────────────────────
  # X holds the current ensemble state [ne × 3: Bleaf, Bwood, BSOM].
  # At year 1, X = X0 (the specified initial conditions).
  # After each year, X is updated to the last row of that year's SSEM output
  # so that carbon pools accumulate continuously across years.
  X          <- X0
  outputs    <- list()
  years_run  <- integer(0)
  t_sim_all  <- proc.time()

  for (yr in years) {
    # Subset driver data to this calendar year
    yr_data <- raw |>
      filter(year(datetime) == yr) |>
      select(PAR, temp) |>
      as.data.frame()

    # Skip years with very few rows (< 300 days × steps_per_day).
    # This guards against partial records at the start or end of the dataset.
    min_rows <- 300L * steps_per_day
    if (nrow(yr_data) < min_rows) {
      cat(sprintf("  Skipping %d — only %d rows (< %d required for 300+ days)\n",
                  yr, nrow(yr_data), min_rows))
      next
    }

    # Replace any remaining NA driver values with zero (PAR) or the annual
    # mean temperature (temp).  SSEM cannot handle NA inputs because the
    # exponential Beer's law term and the Q10 function are evaluated for
    # every ensemble member at every step.
    temp_mean <- mean(yr_data$temp, na.rm = TRUE)
    yr_data$PAR[is.na(yr_data$PAR)]   <- 0
    yr_data$temp[is.na(yr_data$temp)] <- temp_mean

    # Run ensemble_forecast() for this year.
    # ensemble_forecast() reads 'ne' from the global environment.
    # Output: array [n_timesteps × ne × 12].
    t_yr <- proc.time()
    cat(sprintf("  Running %s %d (%d timesteps) ...\n",
                site_id, yr, nrow(yr_data)))
    out_yr <- ensemble_forecast(X, params, yr_data)

    elapsed <- (proc.time() - t_yr)["elapsed"]
    cat(sprintf("    done in %.0f s  (dim: %d × %d × %d)\n",
                elapsed, dim(out_yr)[1], dim(out_yr)[2], dim(out_yr)[3]))

    # Store this year's output
    outputs[[as.character(yr)]] <- out_yr
    years_run <- c(years_run, yr)

    # Carry state forward: the last time-step's pool sizes become
    # the initial condition for the next year.
    X <- out_yr[nrow(out_yr), , 1:3]
  }

  total_elapsed <- (proc.time() - t_sim_all)["elapsed"]
  cat(sprintf("  Simulation complete: %d years in %.0f min %.0f s\n",
              length(years_run),
              total_elapsed %/% 60, total_elapsed %% 60))

  # ── Concatenate all years into one 3-D array ─────────────────────────────
  cat("  Concatenating annual arrays ...\n")
  combined <- combine_arrays(outputs)

  cat(sprintf("  Combined array dims: [%s]\n",
              paste(dim(combined), collapse = " × ")))

  # ── Save to RDS ───────────────────────────────────────────────────────────
  # The RDS is a named list so the dashboard builder has access to metadata
  # (year vector, steps_per_day) without any external look-up table.
  # xz compression is used because SSEM output arrays are highly compressible
  # (ensemble members are correlated), typically reducing file size by 80-90%.
  result <- list(
    output        = combined,        # [total_ts × ne × 12]
    years         = years_run,       # integer vector of years actually run
    steps_per_day = steps_per_day,   # 48 or 24
    ne            = ne,
    site          = site_id
  )

  cat(sprintf("  Saving to %s (xz compression — may take 1–2 min) ...\n", out_path))
  t_save <- proc.time()
  saveRDS(result, file = out_path, compress = "xz")
  cat(sprintf("  Saved: %.0f MB (%.0f s)\n",
              file.size(out_path) / 1e6,
              (proc.time() - t_save)["elapsed"]))

  invisible(result)
}


# =============================================================================
# Parameter and initial condition setup
# =============================================================================

cat("Drawing parameter ensembles (ne =", ne, ") ...\n")

# ENF parameters for US-NR1 (Niwot Ridge, subalpine)
params_enf <- make_params_enf()
cat("  ENF params drawn\n")

# DBF parameters for US-MMS (Morgan Monroe, deciduous)
params_dbf <- make_params_dbf()
cat("  DBF params drawn\n")

# Initial pool sizes: same prior for both sites.
# These values represent a mature closed-canopy forest in approximate
# steady state.  The model will spin up through the early years.
X0 <- make_X0(bleaf = 3.0, bwood = 100.0, bsom = 100.0)


# =============================================================================
# Run US-NR1 (ENF, 1998–2023)
# =============================================================================

# US-NR1 is a subalpine evergreen needleleaf forest at Niwot Ridge, CO.
# The half-hourly product (HH suffix) has 48 rows per day.
# DATETIME_START is already in ISO 8601 format and parsed as POSIXct by readr.
cat("\n=== US-NR1 Niwot Ridge (ENF, 1998–2023) ===\n")
t_nr1 <- proc.time()

nr1_result <- run_site(
  site_id       = "US-NR1",
  driver_file   = file.path("data", "US-NR1", "US-NR1_HH.csv"),
  years         = 1998L:2023L,
  steps_per_day = 48L,
  ts_col        = "DATETIME_START",
  ts_type       = "iso8601",
  params        = params_enf,
  X0            = X0,
  out_path      = file.path("data", "ssem_usnr1_fullrecord.rds")
)

cat(sprintf("\nUS-NR1 full-record summary:\n"))
cat(sprintf("  Years run:   %s–%s (%d years)\n",
            min(nr1_result$years), max(nr1_result$years),
            length(nr1_result$years)))
cat(sprintf("  Array dims:  [%s] (timesteps × ensemble × variables)\n",
            paste(dim(nr1_result$output), collapse = " × ")))
cat(sprintf("  Run time:    %.0f min %.0f s\n",
            (proc.time() - t_nr1)["elapsed"] %/% 60,
            (proc.time() - t_nr1)["elapsed"] %% 60))


# =============================================================================
# Run US-MMS (DBF, 1999–2023)
# =============================================================================

# US-MMS is a temperate deciduous broadleaf forest at Morgan Monroe, IN.
# The hourly product (HR suffix) has 24 rows per day.
# TIMESTAMP_START is an integer in YYYYMMDDHHMM format.
#
# NOTE: SSEM's internal timestep constant (k in functions.R) is hardcoded
# to 1800 s (30 min).  Since US-MMS is hourly (3600 s), the pool state
# transitions (Bleaf, Bwood, BSOM changes per step) are computed with a
# 1800-s timestep instead of the actual 3600-s step.  Flux rates (GPP, NEP,
# Rh in umol m^-2 s^-1) are not affected by this — they are instantaneous
# rates.  The dashboard applies the correct step duration (3600 s) when
# converting fluxes to gC m^-2 d^-1.  This known limitation is documented
# in CLAUDE.md and is pending correction upstream (mdietze/FluxCourseForecast).
cat("\n=== US-MMS Morgan Monroe (DBF, 1999–2023) ===\n")
t_mms <- proc.time()

mms_result <- run_site(
  site_id       = "US-MMS",
  driver_file   = file.path("data", "US-MMS", "US-MMS_HR.csv"),
  years         = 1999L:2023L,
  steps_per_day = 24L,
  ts_col        = "TIMESTAMP_START",
  ts_type       = "yyyymmddhhmm",
  params        = params_dbf,
  X0            = X0,
  out_path      = file.path("data", "ssem_usmms_fullrecord.rds")
)

cat(sprintf("\nUS-MMS full-record summary:\n"))
cat(sprintf("  Years run:   %s–%s (%d years)\n",
            min(mms_result$years), max(mms_result$years),
            length(mms_result$years)))
cat(sprintf("  Array dims:  [%s] (timesteps × ensemble × variables)\n",
            paste(dim(mms_result$output), collapse = " × ")))
cat(sprintf("  Run time:    %.0f min %.0f s\n",
            (proc.time() - t_mms)["elapsed"] %/% 60,
            (proc.time() - t_mms)["elapsed"] %% 60))


# =============================================================================
# Final summary
# =============================================================================

cat("\n=== Summary ===\n")
cat(sprintf("  data/ssem_usnr1_fullrecord.rds  %.0f MB  [%s]\n",
            file.size("data/ssem_usnr1_fullrecord.rds") / 1e6,
            paste(dim(nr1_result$output), collapse = " × ")))
cat(sprintf("  data/ssem_usmms_fullrecord.rds  %.0f MB  [%s]\n",
            file.size("data/ssem_usmms_fullrecord.rds") / 1e6,
            paste(dim(mms_result$output), collapse = " × ")))
cat("\nDone.\n")
