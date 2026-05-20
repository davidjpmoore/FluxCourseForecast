# =============================================================================
# generate_review_figures.R  —  INSTRUCTOR USE ONLY
#
# Runs SSEM at DE-Tha (2000), DK-Sor (2000), and US-MMS (2005) and saves the
# full set of review figures to exercises/review_figures/.
#
# Run from the repository root:
#   Rscript exercises/generate_review_figures.R
#
# PNGs generated (16 total):
#   01_DE-Tha_drivers.png / 01_DE-Tha_forecast_12panel.png
#   01_DK-Sor_drivers.png / 01_DK-Sor_forecast_12panel.png
#   01_US-MMS_drivers.png / 01_US-MMS_forecast_12panel.png
#   02_DE-Tha_subdaily_july_nee.png / 02_DE-Tha_annual_daily_cycle.png
#   02_DK-Sor_subdaily_july_nee.png / 02_DK-Sor_annual_daily_cycle.png
#   02_US-MMS_subdaily_july_nee.png / 02_US-MMS_annual_daily_cycle.png
#   02_allsites_cost_functions_table.png
#   02_cmip6_CESM2_gpp_rh.png
#   02_cmip6_IPSL-CM6A-LR_gpp_rh.png
#   02_cmip6_UKESM1-0-LL_gpp_rh.png
#
# RDS cache (re-used on subsequent runs to skip the 2-4 min model runs):
#   exercises/review_figures/ssem_output_DE-Tha.rds
#   exercises/review_figures/ssem_output_DK-Sor.rds
#   exercises/review_figures/ssem_output_US-MMS.rds
# =============================================================================

# ── Working directory guard ───────────────────────────────────────────────────
if (!file.exists("R/functions.R")) {
  if (file.exists("../R/functions.R")) setwd("..")
  else stop("Cannot locate R/functions.R — run this script from the repository root.")
}

# ── Output directory ──────────────────────────────────────────────────────────
out_dir <- "exercises/review_figures"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# ── Libraries and model code ──────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(gridExtra)
})
source("R/functions.R")
source("R/utils.R")

# ── Shared output dimensions ──────────────────────────────────────────────────
# All PNGs: 1200 × 800 px at 150 dpi = 8.0 × 5.33 inches.
PX_W <- 1200L;  PX_H <- 800L;  DPI <- 150L
IN_W <- PX_W / DPI;  IN_H <- PX_H / DPI

# Helper: print file size and flag anything suspiciously small.
report_saved <- function(path) {
  sz <- file.size(path)
  flag <- if (sz < 50000L) "  *** POSSIBLE BLANK — under 50 KB ***" else ""
  message(sprintf("  saved  %-62s %6.0f KB%s",
                  basename(path), sz / 1024, flag))
}

# ── Global model settings ─────────────────────────────────────────────────────
ne <- 100L        # ensemble size (must be in global env for ensemble_forecast())
set.seed(2026L)   # fixed seed for full reproducibility

# ── Unit conversion constants ─────────────────────────────────────────────────
MC               <- 12e-6        # gC per μmol CO₂
SECS_PER_MIN     <- 60L
UMOL_S_TO_GC_DAY <- MC * 86400   # μmol m⁻² s⁻¹ → gC m⁻² day⁻¹
KGC_S_TO_GC_DAY  <- 1000 * 86400 # kg C m⁻² s⁻¹ → gC m⁻² day⁻¹

# Per-step conversion: μmol m⁻² s⁻¹ × step_mins × 60 × MC → gC m⁻² per step.
# Rate × step_seconds × g/μmol = gC accumulated in that step.
umol_s_to_gC_step <- function(step_mins) MC * step_mins * SECS_PER_MIN

# ── Site configuration ────────────────────────────────────────────────────────
# Each entry defines everything site-specific: file path, timestamp format,
# temporal resolution, the year the model will be run, and vegetation type
# (used to select the appropriate parameter set below).
site_configs <- list(

  "DE-Tha" = list(
    file      = "data/DE-Tha/DE-Tha_HH.csv",
    ts_col    = "DATETIME_START",    # ISO 8601 with trailing Z
    step_mins = 30L,
    run_year  = 2000L,               # leap year: 366 × 48 = 17,568 steps
    veg_type  = "ENF",
    veg_label = "Norway spruce (ENF)"
  ),

  "DK-Sor" = list(
    file      = "data/DK-Sor/DK-Sor_HH.csv",
    ts_col    = "DATETIME_START",
    step_mins = 30L,
    run_year  = 2000L,
    veg_type  = "DBF",
    veg_label = "European beech (DBF)"
  ),

  "US-MMS" = list(
    file      = "data/US-MMS/US-MMS_HR.csv",
    ts_col    = "TIMESTAMP_START",   # integer YYYYMMDDHHMM
    step_mins = 60L,
    run_year  = 2005L,               # non-leap year: 365 × 24 = 8,760 steps
    veg_type  = "DBF",
    veg_label = "mixed deciduous (DBF)"
  )
)

# ── Parameter factory ─────────────────────────────────────────────────────────
# Litterfall and mortality are expressed as ANNUAL TURNOVER FRACTIONS, then
# divided by steps_per_year to give per-timestep fractions.
# This makes the physical annual rate identical regardless of site timestep
# length (30 min at DE-Tha/DK-Sor vs 60 min at US-MMS).
#
# ENF (evergreen needle-leaf, Norway spruce):
#   ~4-year needle longevity → 25% of Bleaf turns over per year.
#   Source: Schulze et al. (1994); litterfall = 0.25 yr⁻¹.
#
# DBF (deciduous broadleaf, beech / mixed deciduous):
#   ~1-year leaf longevity → 100% of Bleaf turns over per year.
#   Higher leaf allocation fraction (30% vs 20%) reflects the need to rebuild
#   the full canopy from scratch each spring.
#   Source: Körner (2003); annual CUE for deciduous ≈ 0.55–0.60.
make_params <- function(veg_type, step_mins, ne) {
  # steps_per_year uses 365 days as a stable reference (no leap-year ambiguity
  # in the parameter denominator; the actual run length may differ by ≤48 steps)
  steps_per_yr <- 365L * (1440L / step_mins)

  if (veg_type == "ENF") {
    lf_annual    <- 0.25   # yr⁻¹  (~4-yr needle lifespan)
    falloc_alpha <- c(5, 3, 2)   # Ra 50% | NPPwood 30% | NPPleaf 20%
  } else {
    # DBF: 1-year leaf longevity → 4× higher litterfall rate than ENF spruce
    lf_annual    <- 1.0    # yr⁻¹  (~1-yr leaf lifespan)
    falloc_alpha <- c(4, 3, 3)   # Ra 40% | NPPwood 30% | NPPleaf 30%
  }

  # Mortality: ~80-yr harvest rotation for managed European forest → ~1.25% yr⁻¹
  mort_annual <- 0.0125

  params <- data.frame(
    alpha      = rnorm(ne, 0.02,   0.003)                       |> pmax(0),
    SLA        = rnorm(ne, 8.0,    1.2)                         |> pmax(1),
    Rbasal     = rnorm(ne, 0.015,  0.003)                       |> pmax(0),
    Q10        = rnorm(ne, 2.0,    0.3)                         |> pmax(1),
    litterfall = rnorm(ne, lf_annual    / steps_per_yr,
                           lf_annual * 0.10 / steps_per_yr)    |> pmax(0),
    mortality  = rnorm(ne, mort_annual  / steps_per_yr,
                           mort_annual * 0.10 / steps_per_yr)  |> pmax(0),
    sigma.leaf = rep(0.01, ne),
    sigma.stem = rep(0.10, ne),
    sigma.soil = rep(0.10, ne)
  )

  falloc <- rdirichlet.orig(ne, alpha = falloc_alpha)
  params$falloc.1 <- falloc[, 1]
  params$falloc.2 <- falloc[, 2]
  params$falloc.3 <- falloc[, 3]
  params
}

# ── Per-site output accumulators (populated during Phase 1) ──────────────────
ssem_subdaily_list   <- list()   # [n_steps × ensemble stats] per site
ssem_daily_list      <- list()   # [n_days  × ensemble stats] per site
fluxnet_subdaily_list <- list()  # FLUXNET sub-daily for run year, per site
fluxnet_daily_list   <- list()   # FLUXNET daily aggregated, per site


# =============================================================================
# PHASE 1 — per-site: load drivers + NEE, run SSEM, save driver and forecast
#            figures, build small aggregated tibbles for later phases.
# =============================================================================
# Memory strategy: each iteration loads one large CSV (with col_select keeping
# only 5 columns), builds the needed data structures, then discards the raw
# data before the next iteration. Peak usage ≈ one CSV at a time.

for (site_label in names(site_configs)) {
  cfg <- site_configs[[site_label]]
  message("\n", strrep("=", 60))
  message("SITE: ", site_label, "  |  run year: ", cfg$run_year,
          "  |  ", cfg$veg_label)
  message(strrep("=", 60))

  # ── Load raw data: five columns only ────────────────────────────────────────
  # col_select prevents loading 200+ columns we don't need (DE-Tha HH is 695 MB).
  col_sel <- c(cfg$ts_col, "SW_IN_F", "TA_F", "NEE_VUT_REF", "NEE_VUT_REF_QC")
  message("Loading: ", basename(cfg$file))
  raw <- read_csv(cfg$file, show_col_types = FALSE, col_select = all_of(col_sel))

  # FLUXNET fill value -9999 means missing — replace with NA throughout.
  raw <- raw |> mutate(across(where(is.numeric), \(x) replace(x, x == -9999, NA)))

  # ── Parse timestamps ─────────────────────────────────────────────────────────
  # DE-Tha / DK-Sor: ISO 8601 with trailing Z (e.g. "1996-01-01T00:00:00Z")
  # US-MMS: integer YYYYMMDDHHMM (e.g. 200501010000)
  if (cfg$ts_col == "DATETIME_START") {
    raw <- raw |>
      mutate(datetime = suppressWarnings(ymd_hms(DATETIME_START, quiet = TRUE))) |>
      filter(!is.na(datetime))
  } else {
    raw <- raw |>
      mutate(datetime = as.POSIXct(as.character(TIMESTAMP_START),
                                   format = "%Y%m%d%H%M", tz = "UTC")) |>
      filter(!is.na(datetime))
  }

  # ── Filter to the representative run year ────────────────────────────────────
  raw <- raw |> filter(year(datetime) == cfg$run_year)
  message(sprintf("Rows after year filter (%d): %s",
                  cfg$run_year, format(nrow(raw), big.mark = ",")))

  # ── Compute PAR; fill gaps in met drivers ────────────────────────────────────
  # SW_IN_F is gap-filled (the _F suffix) so NAs are rare in practice;
  # treat any remaining NA as dark (PAR = 0) rather than dropping the row,
  # so the SSEM timestep sequence stays aligned with the FLUXNET timestamps.
  # TA_F is also gap-filled; forward/back-fill any residual NAs.
  raw <- raw |>
    mutate(PAR  = pmax(SW_IN_F * 2.1, 0),  # W m⁻² → μmol photon m⁻² s⁻¹
           temp = TA_F) |>
    mutate(PAR  = replace_na(PAR, 0)) |>
    tidyr::fill(temp, .direction = "downup")

  # Drop any rows still missing PAR or temp (should be zero after fills above).
  n_before <- nrow(raw)
  raw <- raw |> filter(!is.na(PAR), !is.na(temp))
  if (nrow(raw) < n_before)
    message(sprintf("  Dropped %d rows with NA PAR or temp.", n_before - nrow(raw)))

  # ── Trim to an integer number of complete days ───────────────────────────────
  # SSEM day_idx = rep(1:n_days, each = steps_per_day) requires exact divisibility.
  steps_per_day <- 1440L / cfg$step_mins
  n_complete    <- (nrow(raw) %/% steps_per_day) * steps_per_day
  raw           <- raw[seq_len(n_complete), ]
  n_days        <- n_complete / steps_per_day
  message(sprintf("Complete days: %d  |  timesteps: %s  |  steps/day: %d",
                  n_days, format(n_complete, big.mark = ","), steps_per_day))

  # Preserve the aligned datetime vector — used later to join SSEM ↔ FLUXNET.
  ssem_datetime <- raw$datetime

  # ── FIGURE 01 — driver plot ──────────────────────────────────────────────────
  fname_drv <- sprintf("01_%s_drivers.png", site_label)
  message("Figure: ", fname_drv)

  p_drv <- raw |>
    select(datetime, PAR, temp) |>
    pivot_longer(c(PAR, temp), names_to = "var", values_to = "val") |>
    mutate(label = if_else(var == "PAR",
                           "PAR (μmol photon m⁻² s⁻¹)",
                           "Air temperature (°C)")) |>
    ggplot(aes(x = datetime, y = val)) +
      geom_line(linewidth = 0.1, alpha = 0.35, colour = "grey20") +
      facet_wrap(~ label, ncol = 1, scales = "free_y") +
      labs(
        title    = sprintf("Meteorological drivers — %s %d", site_label, cfg$run_year),
        subtitle = sprintf("SW_IN_F (W m⁻²) × 2.1 = PAR  |  %d-min timestep",
                           cfg$step_mins),
        x = NULL, y = NULL
      ) +
      theme_classic(base_size = 13) +
      theme(strip.background = element_blank(),
            strip.text       = element_text(face = "bold"),
            plot.margin      = margin(10, 18, 10, 18))

  ggsave(file.path(out_dir, fname_drv), plot = p_drv,
         width = IN_W, height = IN_H, dpi = DPI, units = "in")
  report_saved(file.path(out_dir, fname_drv))

  # ── SSEM: parameters and initial conditions ──────────────────────────────────
  # Initial pool sizes (Mg C ha⁻¹): uniform across ensemble members;
  # prior uncertainty is expressed entirely through the parameter distributions.
  X      <- matrix(c(3.0, 100.0, 100.0), nrow = ne, ncol = 3, byrow = FALSE)
  params <- make_params(cfg$veg_type, cfg$step_mins, ne)
  inputs <- raw |> select(PAR, temp) |> as.data.frame()

  # ── SSEM: run or load from RDS cache ────────────────────────────────────────
  rds_path <- file.path(out_dir, sprintf("ssem_output_%s.rds", site_label))
  if (file.exists(rds_path)) {
    message("Loading cached SSEM output: ", basename(rds_path))
    output <- readRDS(rds_path)
  } else {
    message("Running SSEM for ", site_label, " (2-4 min) ...")
    output <- ensemble_forecast(X, params, inputs)
    saveRDS(output, rds_path)
    message("Saved: ", basename(rds_path))
  }
  message(sprintf("SSEM output: %s", paste(dim(output), collapse = " x ")))

  # ── FIGURE 01 — 12-panel forecast (base R graphics) ─────────────────────────
  fname_fc <- sprintf("01_%s_forecast_12panel.png", site_label)
  message("Figure: ", fname_fc)

  png(file.path(out_dir, fname_fc), width = PX_W, height = PX_H, res = DPI)
  par(mfrow = c(4, 3), mar = c(3, 4.5, 3, 1), oma = c(0, 0, 3, 0))
  plot_forecast(output)
  title(sprintf("SSEM ensemble output — %s %d  (%s)",
                site_label, cfg$run_year, cfg$veg_label),
        outer = TRUE, cex.main = 1.1)
  invisible(dev.off())
  report_saved(file.path(out_dir, fname_fc))

  # ── Build ssem_subdaily and ssem_daily for this site ────────────────────────
  # Variable 6 = NEP (positive = C sink); negate to get NEE (positive = source).
  # Variable 5 = GPP (positive).
  ssem_nee_mat <- -output[,, 6]   # [n_steps x 100]

  sd_ci <- apply(ssem_nee_mat, 1, quantile, c(0.025, 0.5, 0.975), na.rm = TRUE)
  ssem_subdaily_list[[site_label]] <- tibble(
    datetime = ssem_datetime,
    date     = as.Date(ssem_datetime),
    site     = site_label,
    nee_med  = sd_ci["50%",   ],
    nee_lo   = sd_ci["2.5%",  ],
    nee_hi   = sd_ci["97.5%", ]
  )

  # Daily aggregation: sum per-step contributions within each calendar day.
  step_conv  <- umol_s_to_gC_step(cfg$step_mins)
  day_idx    <- rep(seq_len(n_days), each = steps_per_day)
  ssem_dates <- seq.Date(as.Date(sprintf("%d-01-01", cfg$run_year)),
                         by = "day", length.out = n_days)

  daily_nee_ens <- apply(ssem_nee_mat,  2, \(e) tapply(e, day_idx, sum) * step_conv)
  daily_gpp_ens <- apply(output[,, 5], 2, \(e) tapply(e, day_idx, sum) * step_conv)

  nee_ci <- apply(daily_nee_ens, 1, quantile, c(0.025, 0.5, 0.975), na.rm = TRUE)
  gpp_ci <- apply(daily_gpp_ens, 1, quantile, c(0.025, 0.5, 0.975), na.rm = TRUE)

  ssem_daily_list[[site_label]] <- tibble(
    date    = ssem_dates, site = site_label,
    nee_med = nee_ci["50%",   ], nee_lo = nee_ci["2.5%",  ], nee_hi = nee_ci["97.5%", ],
    gpp_med = gpp_ci["50%",   ], gpp_lo = gpp_ci["2.5%",  ], gpp_hi = gpp_ci["97.5%", ]
  )

  # ── Build fluxnet_subdaily and fluxnet_daily for this site ──────────────────
  # Use only the trimmed rows (complete days, same slice as SSEM).
  fluxnet_subdaily_list[[site_label]] <- tibble(
    datetime = raw$datetime,
    date     = as.Date(raw$datetime),
    site     = site_label,
    nee_raw  = raw$NEE_VUT_REF,
    nee_qc   = raw$NEE_VUT_REF_QC
  )

  # Aggregate to daily totals with the 75%-coverage threshold from Exercise 02.
  fluxnet_daily_list[[site_label]] <- fluxnet_subdaily_list[[site_label]] |>
    group_by(date, site) |>
    summarise(
      n_steps_ok  = sum(!is.na(nee_raw)),
      nee_gCm2d   = if_else(
        n_steps_ok >= 0.75 * steps_per_day,
        sum(nee_raw * step_conv, na.rm = TRUE),
        NA_real_
      ),
      nee_qc_mean = mean(nee_qc, na.rm = TRUE),
      .groups     = "drop"
    )

  message(sprintf("SSEM sub-daily: %d rows | SSEM daily: %d rows | Annual GPP median: %.0f gC m⁻² yr⁻¹",
                  nrow(ssem_subdaily_list[[site_label]]),
                  nrow(ssem_daily_list[[site_label]]),
                  sum(ssem_daily_list[[site_label]]$gpp_med, na.rm = TRUE)))

  # Discard large objects before next iteration.
  rm(raw, output, ssem_nee_mat, sd_ci, daily_nee_ens, daily_gpp_ens, nee_ci, gpp_ci)
  invisible(gc(verbose = FALSE))
}


# =============================================================================
# PHASE 2 — per-site validation figures
# =============================================================================

for (site_label in names(site_configs)) {
  cfg  <- site_configs[[site_label]]
  ssem_sd <- ssem_subdaily_list[[site_label]]
  ssem_dd <- ssem_daily_list[[site_label]]
  flux_sd <- fluxnet_subdaily_list[[site_label]]
  flux_dd <- fluxnet_daily_list[[site_label]]

  # ── FIGURE 02 — sub-daily July NEE ──────────────────────────────────────────
  fname <- sprintf("02_%s_subdaily_july_nee.png", site_label)
  message("\n=== Figure: ", fname, " ===")

  ssem_july <- ssem_sd |> filter(month(datetime) == 7L)
  flux_july <- flux_sd |> filter(month(datetime) == 7L)

  p_july <- ggplot(mapping = aes(x = datetime)) +
    geom_ribbon(
      data = ssem_july, aes(ymin = nee_lo, ymax = nee_hi),
      fill = "steelblue", alpha = 0.30
    ) +
    geom_line(
      data = ssem_july, aes(y = nee_med),
      colour = "steelblue3", linewidth = 0.5
    ) +
    geom_point(
      data = flux_july, aes(y = nee_raw),
      colour = "grey20", alpha = 0.30, size = 0.4
    ) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50",
               linewidth = 0.35) +
    labs(
      title    = sprintf("Sub-daily NEE — July %d — %s (%s)",
                         cfg$run_year, site_label, cfg$veg_label),
      subtitle = sprintf(
        "Blue ribbon: SSEM 95%% CI  |  Blue line: SSEM median  |  Grey: FLUXNET NEE_VUT_REF  |  %d-min timestep",
        cfg$step_mins),
      x = NULL,
      y = expression(NEE ~ (mu * mol ~ CO[2] ~ m^{-2} ~ s^{-1}))
    ) +
    theme_classic(base_size = 12) +
    theme(plot.margin = margin(10, 18, 10, 18))

  ggsave(file.path(out_dir, fname), plot = p_july,
         width = IN_W, height = IN_H, dpi = DPI, units = "in")
  report_saved(file.path(out_dir, fname))

  # ── FIGURE 02 — annual daily NEE cycle ──────────────────────────────────────
  fname <- sprintf("02_%s_annual_daily_cycle.png", site_label)
  message("=== Figure: ", fname, " ===")

  ssem_doy <- ssem_dd |> mutate(doy = yday(date))
  flux_doy <- flux_dd |> mutate(doy = yday(date))

  p_annual <- ggplot(mapping = aes(x = doy)) +
    geom_ribbon(
      data = ssem_doy, aes(ymin = nee_lo, ymax = nee_hi),
      fill = "steelblue", alpha = 0.30
    ) +
    geom_line(
      data = ssem_doy, aes(y = nee_med),
      colour = "steelblue3", linewidth = 0.5
    ) +
    geom_point(
      data = flux_doy, aes(y = nee_gCm2d),
      colour = "grey20", alpha = 0.40, size = 0.6
    ) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50",
               linewidth = 0.35) +
    scale_x_continuous(
      breaks = c(1, 60, 121, 182, 244, 305, 355),
      labels = c("Jan", "Mar", "May", "Jul", "Sep", "Nov", "Dec")
    ) +
    labs(
      title    = sprintf("Annual daily NEE cycle — %s %d (%s)",
                         site_label, cfg$run_year, cfg$veg_label),
      subtitle = "Blue ribbon: SSEM 95% CI  |  Blue line: SSEM median  |  Grey: FLUXNET daily NEE",
      x        = "Day of year",
      y        = expression(NEE ~ (gC ~ m^{-2} ~ day^{-1}))
    ) +
    theme_classic(base_size = 12) +
    theme(plot.margin = margin(10, 18, 10, 18))

  ggsave(file.path(out_dir, fname), plot = p_annual,
         width = IN_W, height = IN_H, dpi = DPI, units = "in")
  report_saved(file.path(out_dir, fname))
}


# =============================================================================
# PHASE 3 — cost function table (all sites)
# =============================================================================
message("\n=== Figure: 02_allsites_cost_functions_table.png ===")

compute_metrics <- function(model_vec, obs_vec) {
  valid <- !is.na(model_vec) & !is.na(obs_vec)
  n     <- sum(valid)
  if (n < 2L) return(list(n = 0L, rmse = NA_real_, bias = NA_real_, r = NA_real_))
  res <- model_vec[valid] - obs_vec[valid]
  list(n    = n,
       rmse = sqrt(mean(res^2)),
       bias = mean(res),
       r    = cor(model_vec[valid], obs_vec[valid]))
}

metrics_rows <- list()
for (site_label in names(site_configs)) {
  cfg <- site_configs[[site_label]]

  # Sub-daily: join on datetime, keep only QC 0-1 (measured or high-quality fill)
  sd_eval <- fluxnet_subdaily_list[[site_label]] |>
    filter(!is.na(nee_qc), nee_qc <= 1L) |>
    inner_join(ssem_subdaily_list[[site_label]] |> select(datetime, nee_med),
               by = "datetime")
  sd_m <- compute_metrics(sd_eval$nee_med, sd_eval$nee_raw)

  # Daily: keep days with QC mean ≤ 1.0 (consistent with Exercise 02)
  dd_eval <- fluxnet_daily_list[[site_label]] |>
    filter(!is.na(nee_gCm2d), nee_qc_mean <= 1.0) |>
    inner_join(ssem_daily_list[[site_label]] |> select(date, nee_med),
               by = "date")
  dd_m <- compute_metrics(dd_eval$nee_med, dd_eval$nee_gCm2d)

  run_yr <- site_configs[[site_label]]$run_year
  metrics_rows <- c(metrics_rows, list(
    tibble(Site = site_label, Year = run_yr, Timescale = "Sub-daily",
           Units = "umol/m2/s",
           N = sd_m$n, RMSE = round(sd_m$rmse, 3),
           Bias = round(sd_m$bias, 3), r = round(sd_m$r, 3)),
    tibble(Site = site_label, Year = run_yr, Timescale = "Daily",
           Units = "gC/m2/d",
           N = dd_m$n, RMSE = round(dd_m$rmse, 3),
           Bias = round(dd_m$bias, 3), r = round(dd_m$r, 3))
  ))
}

metrics_tbl <- bind_rows(metrics_rows)

tbl_grob <- tableGrob(
  metrics_tbl, rows = NULL,
  theme = ttheme_default(base_size = 11, padding = unit(c(8, 5), "pt"))
)
title_grob <- grid::textGrob(
  "Cost function metrics: SSEM ensemble median vs FLUXNET NEE_VUT_REF",
  gp = grid::gpar(fontsize = 13, fontface = "bold"), just = "centre"
)
note_grob <- grid::textGrob(
  paste("DE-Tha year 2000 (ENF)  |  DK-Sor year 2000 (DBF)  |  US-MMS year 2005 (DBF)",
        "  |  Sub-daily QC ≤ 1  |  Daily QC mean ≤ 1.0"),
  gp = grid::gpar(fontsize = 9), just = "centre"
)

out_path <- file.path(out_dir, "02_allsites_cost_functions_table.png")
png(out_path, width = PX_W, height = PX_H, res = DPI)
gridExtra::grid.arrange(title_grob, note_grob, tbl_grob,
                        ncol = 1, heights = c(0.10, 0.06, 0.84))
invisible(dev.off())
report_saved(out_path)


# =============================================================================
# PHASE 4 — CMIP6 monthly comparison (US-MMS, all three models)
# =============================================================================

# Load CMIP6 and FLUXNET daily files for the CMIP6 overlap period.
cesm2_raw  <- read_csv("data/cmip6/CESM2_usmms_monthly.csv",        show_col_types = FALSE)
ipsl_raw   <- read_csv("data/cmip6/IPSL-CM6A-LR_usmms_monthly.csv", show_col_types = FALSE)
ukesm_raw  <- read_csv("data/cmip6/UKESM1-0-LL_usmms_monthly.csv",  show_col_types = FALSE)
usmms_raw  <- read_csv("data/US-MMS/US-MMS_DD.csv",                 show_col_types = FALSE)

harmonise_cmip6 <- function(df, model_label) {
  df |>
    mutate(
      model      = model_label,
      gpp_gCm2d  = gpp_kgC_m2_s * KGC_S_TO_GC_DAY,
      rh_gCm2d   = rh_kgC_m2_s  * KGC_S_TO_GC_DAY,
      ra_gCm2d   = ra_kgC_m2_s  * KGC_S_TO_GC_DAY,
      days_in_mo = days_in_month(as.Date(paste(year, month, "01", sep = "-")))
    ) |>
    select(model, year, month, days_in_mo, scenario,
           gpp_gCm2d, rh_gCm2d, ra_gCm2d, lai_m2_m2)
}

cmip6_all <- bind_rows(
  harmonise_cmip6(cesm2_raw,  "CESM2"),
  harmonise_cmip6(ipsl_raw,   "IPSL-CM6A-LR"),
  harmonise_cmip6(ukesm_raw,  "UKESM1-0-LL")
)

# FLUXNET US-MMS monthly means over the CMIP6 historical overlap (1999-2014).
usmms_monthly <- usmms_raw |>
  mutate(date = as.Date(DATE)) |>
  filter(year(date) >= 1999, year(date) <= 2014) |>
  mutate(across(where(is.numeric), \(x) replace(x, x == -9999, NA))) |>
  mutate(
    gpp_gCm2d  = GPP_NT_VUT_REF  * UMOL_S_TO_GC_DAY,
    reco_gCm2d = RECO_NT_VUT_REF * UMOL_S_TO_GC_DAY
  ) |>
  group_by(year = year(date), month = month(date)) |>
  summarise(
    gpp_gCm2d  = mean(gpp_gCm2d,  na.rm = TRUE),
    reco_gCm2d = mean(reco_gCm2d, na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(date = as.Date(paste(year, month, "01", sep = "-")))

model_colours <- c(
  "FLUXNET US-MMS" = "grey20",
  "CESM2"          = "#E07B39",
  "IPSL-CM6A-LR"   = "#5B8DB8",
  "UKESM1-0-LL"    = "#6BAE75"
)

for (chosen_model in c("CESM2", "IPSL-CM6A-LR", "UKESM1-0-LL")) {
  fname <- sprintf("02_cmip6_%s_gpp_rh.png", chosen_model)
  message("\n=== Figure: ", fname, " ===")

  cmip6_chosen <- cmip6_all |>
    filter(model == chosen_model) |>
    mutate(date = as.Date(paste(year, month, "01", sep = "-")))

  cmip6_long <- cmip6_chosen |>
    select(date, GPP = gpp_gCm2d, Rh = rh_gCm2d) |>
    pivot_longer(c(GPP, Rh), names_to = "variable", values_to = "value") |>
    mutate(source = chosen_model)

  flux_long <- usmms_monthly |>
    select(date, GPP = gpp_gCm2d, Rh = reco_gCm2d) |>
    pivot_longer(c(GPP, Rh), names_to = "variable", values_to = "value") |>
    mutate(source = "FLUXNET US-MMS")

  p_cmip6 <- bind_rows(cmip6_long, flux_long) |>
    ggplot(aes(x = date, y = value, colour = source)) +
      geom_line(linewidth = 0.4, alpha = 0.7) +
      geom_smooth(method = "loess", span = 0.15, se = FALSE,
                  linewidth = 1.0, na.rm = TRUE) +
      facet_wrap(
        ~ variable, ncol = 1, scales = "free_y",
        labeller = as_labeller(c(
          GPP = "GPP (gC m⁻² day⁻¹)",
          Rh  = "Rh / RECO (gC m⁻² day⁻¹) — note: RECO > Rh"
        ))
      ) +
      scale_colour_manual(
        values = model_colours[c("FLUXNET US-MMS", chosen_model)]
      ) +
      scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
      labs(
        title    = paste("Monthly GPP and Rh —", chosen_model, "vs FLUXNET US-MMS"),
        subtitle = "1999–2014  |  gC m⁻² day⁻¹  |  Thick lines: LOESS trend",
        x = NULL, y = NULL, colour = NULL
      ) +
      theme_classic(base_size = 12) +
      theme(
        legend.position  = "bottom",
        strip.background = element_blank(),
        strip.text       = element_text(face = "bold"),
        plot.margin      = margin(10, 18, 10, 18)
      )

  ggsave(file.path(out_dir, fname), plot = p_cmip6,
         width = IN_W, height = IN_H, dpi = DPI, units = "in")
  report_saved(file.path(out_dir, fname))
}


# =============================================================================
# SUMMARY REPORT
# =============================================================================
message("\n", strrep("=", 70))
message("SUMMARY")
message(strrep("=", 70))

pngs     <- sort(list.files(out_dir, pattern = "\\.png$", full.names = TRUE))
sizes_kb <- file.size(pngs) / 1024

cat(sprintf("\n%d PNGs written to  %s/\n\n", length(pngs), out_dir))
cat(sprintf("  %-62s  %8s\n", "File", "Size KB"))
cat(strrep("-", 74), "\n")
for (i in seq_along(pngs)) {
  flag <- if (sizes_kb[i] < 50) "  *** UNDER 50 KB ***" else ""
  cat(sprintf("  %-62s  %8.0f%s\n", basename(pngs[i]), sizes_kb[i], flag))
}
cat(strrep("-", 74), "\n")
cat(sprintf("  %-62s  %8.0f\n\n", "TOTAL", sum(sizes_kb)))

n_suspect <- sum(sizes_kb < 50)
if (n_suspect == 0L) {
  message("All PNGs above 50 KB — no blank renders detected.")
} else {
  warning(n_suspect, " PNG(s) are under 50 KB and may be blank or failed.")
}
