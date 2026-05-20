# =============================================================================
# generate_review_figures.R
# Instructor review script — NOT for student distribution.
#
# Generates every figure from exercises/01_run_model.Rmd and
# exercises/02_validation.Rmd as named PNGs in exercises/review_figures/.
#
# Run from the repository root:
#   Rscript exercises/generate_review_figures.R
#
# Outputs (all 1200 × 800 px, 150 dpi):
#   01_detha_drivers.png
#   01_detha_forecast_12panel.png
#   02_subdaily_july_nee_allsites.png
#   02_annual_daily_cycle_allsites.png
#   02_cost_functions_table.png
#   02_cmip6_CESM2_gpp_rh.png
#   02_cmip6_IPSL-CM6A-LR_gpp_rh.png
#   02_cmip6_UKESM1-0-LL_gpp_rh.png
# =============================================================================

# ── Working directory guard ───────────────────────────────────────────────────
# Detect the repo root regardless of where the script is invoked from.
if (!file.exists("R/functions.R")) {
  # If called as  Rscript exercises/generate_review_figures.R  the working
  # directory is already the repo root. If invoked from inside exercises/,
  # step up one level.
  if (file.exists("../R/functions.R")) {
    setwd("..")
  } else {
    stop("Cannot locate R/functions.R. Run this script from the repository root.")
  }
}

# ── Output directory ──────────────────────────────────────────────────────────
out_dir <- "exercises/review_figures"
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# ── Libraries ─────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(tidyverse)
  library(lubridate)
  library(gridExtra)   # tableGrob for cost-function table PNG
})

# ── Model code ────────────────────────────────────────────────────────────────
source("R/functions.R")
source("R/utils.R")

# ── Shared PNG dimensions ─────────────────────────────────────────────────────
# 1200 × 800 px at 150 dpi = 8.0 × 5.33 inches.
PX_W  <- 1200L
PX_H  <- 800L
DPI   <- 150L
IN_W  <- PX_W / DPI        # 8.0 in
IN_H  <- PX_H / DPI        # 5.33 in

# Helper: report each saved file
report_saved <- function(path) {
  sz <- file.size(path)
  flag <- if (sz < 50000L) "  *** POSSIBLE BLANK — under 50 KB ***" else ""
  message(sprintf("  saved  %-55s  %s KB%s",
                  basename(path), format(round(sz / 1024), big.mark = ","), flag))
}

message("\n=== EXERCISE 01 — data prep ===")

# =============================================================================
# EXERCISE 01 — LOAD DRIVERS
# =============================================================================

# col_select avoids loading 695 MB into memory; we only need these three columns.
drivers_raw <- read_csv("data/DE-Tha/DE-Tha_HH.csv", show_col_types = FALSE,
                        col_select = c(DATETIME_START, SW_IN_F, TA_F)) |>
  mutate(across(where(is.numeric), \(x) replace(x, x == -9999, NA)))

drivers <- drivers_raw |>
  mutate(datetime = ymd_hms(DATETIME_START)) |>
  filter(year(datetime) == 2000) |>
  select(datetime, SW_IN_F, TA_F) |>
  mutate(
    PAR  = pmax(SW_IN_F * 2.1, 0),
    temp = TA_F
  )

message("DE-Tha 2000 driver rows: ", nrow(drivers), " (expect 17,568)")

# =============================================================================
# FIGURE 01a — driver plot (ggplot2)
# =============================================================================
message("\n=== Figure: 01_detha_drivers.png ===")

p_drivers <- drivers |>
  select(datetime, PAR, temp) |>
  pivot_longer(c(PAR, temp), names_to = "variable", values_to = "value") |>
  mutate(label = case_when(
    variable == "PAR"  ~ "PAR (μmol photon m⁻² s⁻¹)",
    variable == "temp" ~ "Air temperature (°C)"
  )) |>
  ggplot(aes(x = datetime, y = value)) +
    geom_line(linewidth = 0.1, alpha = 0.35, colour = "grey20") +
    facet_wrap(~ label, ncol = 1, scales = "free_y") +
    labs(
      title    = "Meteorological drivers — DE-Tha 2000",
      subtitle = "Half-hourly; PAR converted from SW_IN_F (W m⁻²) × 2.1",
      x        = NULL,
      y        = NULL
    ) +
    theme_classic(base_size = 13) +
    theme(strip.background = element_blank(),
          strip.text        = element_text(face = "bold"),
          plot.margin       = margin(10, 15, 10, 15))

out_path <- file.path(out_dir, "01_detha_drivers.png")
ggsave(out_path, plot = p_drivers,
       width = IN_W, height = IN_H, dpi = DPI, units = "in")
report_saved(out_path)

# =============================================================================
# EXERCISE 01 — PARAMETERS AND INITIAL CONDITIONS
# (Mirrors the `parameters` chunk in 01_run_model.Rmd exactly)
# =============================================================================
message("\n=== Exercise 01 — model setup ===")

ne <- 100L
set.seed(2026)

X <- matrix(c(3.0, 100.0, 100.0), nrow = ne, ncol = 3, byrow = FALSE)

params <- data.frame(
  alpha      = rnorm(ne, 0.02,  0.003)  |> pmax(0),
  SLA        = rnorm(ne, 8.0,   1.2)    |> pmax(1),
  Rbasal     = rnorm(ne, 0.015, 0.003)  |> pmax(0),
  Q10        = rnorm(ne, 2.0,   0.3)    |> pmax(1),
  litterfall = rnorm(ne, 1.4e-5, 1.5e-6)|> pmax(0),
  mortality  = rnorm(ne, 7.1e-7, 7e-8)  |> pmax(0),
  sigma.leaf = rep(0.01, ne),
  sigma.stem = rep(0.10, ne),
  sigma.soil = rep(0.10, ne)
)
falloc <- rdirichlet.orig(ne, alpha = c(5, 3, 2))
params$falloc.1 <- falloc[, 1]
params$falloc.2 <- falloc[, 2]
params$falloc.3 <- falloc[, 3]

inputs <- drivers |> select(PAR, temp) |> as.data.frame()

# =============================================================================
# EXERCISE 01 — RUN MODEL (load RDS if available, else run fresh)
# =============================================================================
rds_path <- "data/ssem_detha_2000.rds"
if (file.exists(rds_path)) {
  message("Loading SSEM output from ", rds_path)
  output <- readRDS(rds_path)
} else {
  message("RDS not found — running SSEM now (2–4 min) …")
  output <- ensemble_forecast(X, params, inputs)
  saveRDS(output, rds_path)
  message("Saved SSEM output → ", rds_path)
}
message("SSEM output dims: ", paste(dim(output), collapse = " × "))

# =============================================================================
# FIGURE 01b — 12-panel forecast (base R)
# =============================================================================
message("\n=== Figure: 01_detha_forecast_12panel.png ===")

out_path <- file.path(out_dir, "01_detha_forecast_12panel.png")
png(out_path, width = PX_W, height = PX_H, res = DPI)
par(mfrow = c(4, 3), mar = c(3, 4.5, 3, 1), oma = c(0, 0, 2, 0))
plot_forecast(output)
title("SSEM ensemble output — DE-Tha 2000", outer = TRUE, cex.main = 1.2)
invisible(dev.off())
report_saved(out_path)

message("\n=== EXERCISE 02 — data prep ===")

# =============================================================================
# EXERCISE 02 — CONSTANTS AND SITE METADATA
# =============================================================================
site_timestep <- list("DE-Tha" = 30L, "DK-Sor" = 30L, "US-MMS" = 60L)

MC           <- 12e-6
SECS_PER_MIN <- 60L
UMOL_S_TO_GC_DAY <- MC * 86400
KGC_S_TO_GC_DAY  <- 1000 * 86400

umol_s_to_gC_step <- function(site) MC * site_timestep[[site]] * SECS_PER_MIN

# =============================================================================
# EXERCISE 02 — LOAD RAW FLUXNET DATA
# =============================================================================
replace_fluxnet_na <- function(df) {
  df |> mutate(across(where(is.numeric), \(x) replace(x, x == -9999, NA)))
}

message("Loading FLUXNET sub-daily files (col_select to reduce memory) …")
detha_hh_raw <- read_csv("data/DE-Tha/DE-Tha_HH.csv", show_col_types = FALSE,
                          col_select = c(DATETIME_START, NEE_VUT_REF,
                                         NEE_VUT_REF_QC)) |>
  replace_fluxnet_na()
dksor_hh_raw <- read_csv("data/DK-Sor/DK-Sor_HH.csv", show_col_types = FALSE,
                          col_select = c(DATETIME_START, NEE_VUT_REF,
                                         NEE_VUT_REF_QC)) |>
  replace_fluxnet_na()
usmms_hr_raw <- read_csv("data/US-MMS/US-MMS_HR.csv",  show_col_types = FALSE,
                          col_select = c(TIMESTAMP_START, NEE_VUT_REF,
                                         NEE_VUT_REF_QC)) |>
  replace_fluxnet_na()

# Daily file for CMIP6 comparison (uses GPP_NT_VUT_REF and RECO_NT_VUT_REF)
usmms_raw <- read_csv("data/US-MMS/US-MMS_DD.csv", show_col_types = FALSE)

# CMIP6 monthly files
cesm2_raw  <- read_csv("data/cmip6/CESM2_usmms_monthly.csv",        show_col_types = FALSE)
ipsl_raw   <- read_csv("data/cmip6/IPSL-CM6A-LR_usmms_monthly.csv", show_col_types = FALSE)
ukesm_raw  <- read_csv("data/cmip6/UKESM1-0-LL_usmms_monthly.csv",  show_col_types = FALSE)

# =============================================================================
# EXERCISE 02 — HARMONIZE (mirrors the `harmonize` chunk exactly)
# =============================================================================
message("Harmonizing units …")

# ── SSEM sub-daily and daily representations ──────────────────────────────────
n_steps        <- dim(output)[1]
ssem_step_mins <- site_timestep[["DE-Tha"]]

ssem_datetime <- seq(
  from       = as.POSIXct("2000-01-01 00:00:00", tz = "UTC"),
  by         = paste(ssem_step_mins, "mins"),
  length.out = n_steps
)

ssem_nee_raw <- -output[,, 6]   # NEP → NEE sign flip

ssem_sd_ci <- apply(ssem_nee_raw, 1, quantile, c(0.025, 0.5, 0.975), na.rm = TRUE)
ssem_subdaily <- tibble(
  datetime = ssem_datetime,
  date     = as.Date(ssem_datetime),
  site     = "DE-Tha",
  nee_med  = ssem_sd_ci["50%",  ],
  nee_lo   = ssem_sd_ci["2.5%", ],
  nee_hi   = ssem_sd_ci["97.5%",]
)

step_conv  <- umol_s_to_gC_step("DE-Tha")
n_days     <- n_steps / 48L
day_idx    <- rep(seq_len(n_days), each = 48L)
ssem_dates <- seq.Date(as.Date("2000-01-01"), by = "day", length.out = n_days)

daily_nee_ens <- apply(ssem_nee_raw, 2, function(ens) tapply(ens, day_idx, sum) * step_conv)
daily_gpp_ens <- apply(output[,, 5],  2, function(ens) tapply(ens, day_idx, sum) * step_conv)

nee_ci <- apply(daily_nee_ens, 1, quantile, c(0.025, 0.5, 0.975), na.rm = TRUE)
gpp_ci <- apply(daily_gpp_ens, 1, quantile, c(0.025, 0.5, 0.975), na.rm = TRUE)

ssem_daily <- tibble(
  date    = ssem_dates, site = "DE-Tha",
  nee_med = nee_ci["50%",  ], nee_lo = nee_ci["2.5%", ], nee_hi = nee_ci["97.5%",],
  gpp_med = gpp_ci["50%",  ], gpp_lo = gpp_ci["2.5%", ], gpp_hi = gpp_ci["97.5%",]
)

# ── FLUXNET sub-daily harmonization ───────────────────────────────────────────
harmonise_subdaily <- function(df, site_label) {
  if ("DATETIME_START" %in% names(df)) {
    dt <- as.POSIXct(df$DATETIME_START, tz = "UTC")
  } else {
    dt <- as.POSIXct(as.character(df$TIMESTAMP_START),
                     format = "%Y%m%d%H%M", tz = "UTC")
  }
  tibble(datetime = dt, date = as.Date(dt), site = site_label,
         nee_raw = df$NEE_VUT_REF, nee_qc = df$NEE_VUT_REF_QC)
}

detha_subdaily <- harmonise_subdaily(detha_hh_raw, "DE-Tha")
dksor_subdaily <- harmonise_subdaily(dksor_hh_raw, "DK-Sor")
usmms_subdaily <- harmonise_subdaily(usmms_hr_raw, "US-MMS")
fluxnet_subdaily <- bind_rows(detha_subdaily, dksor_subdaily, usmms_subdaily)

# ── FLUXNET daily aggregation ─────────────────────────────────────────────────
aggregate_to_daily <- function(df, site_label) {
  n_expected <- 1440L / site_timestep[[site_label]]
  step_gC    <- umol_s_to_gC_step(site_label)
  df |>
    filter(site == site_label) |>
    group_by(date, site) |>
    summarise(
      n_steps_ok  = sum(!is.na(nee_raw)),
      nee_gCm2d   = if_else(n_steps_ok >= 0.75 * n_expected,
                            sum(nee_raw * step_gC, na.rm = TRUE), NA_real_),
      nee_qc_mean = mean(nee_qc, na.rm = TRUE),
      .groups = "drop"
    )
}

fluxnet_daily <- bind_rows(
  aggregate_to_daily(fluxnet_subdaily, "DE-Tha"),
  aggregate_to_daily(fluxnet_subdaily, "DK-Sor"),
  aggregate_to_daily(fluxnet_subdaily, "US-MMS")
)

# ── Most recent complete year per site ────────────────────────────────────────
most_recent_complete_year <- function(site_label) {
  fluxnet_daily |>
    filter(site == site_label) |>
    mutate(yr = year(date)) |>
    group_by(yr) |>
    summarise(n_ok = sum(!is.na(nee_gCm2d)), .groups = "drop") |>
    filter(n_ok >= 330) |>
    pull(yr) |>
    max()
}

obs_year <- list(
  "DE-Tha" = 2000L,
  "DK-Sor" = most_recent_complete_year("DK-Sor"),
  "US-MMS" = most_recent_complete_year("US-MMS")
)
message("Observation years: DE-Tha=", obs_year[["DE-Tha"]],
        "  DK-Sor=", obs_year[["DK-Sor"]],
        "  US-MMS=", obs_year[["US-MMS"]])

# ── CMIP6 harmonization ───────────────────────────────────────────────────────
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

cesm2     <- harmonise_cmip6(cesm2_raw,  "CESM2")
ipsl      <- harmonise_cmip6(ipsl_raw,   "IPSL-CM6A-LR")
ukesm     <- harmonise_cmip6(ukesm_raw,  "UKESM1-0-LL")
cmip6_all <- bind_rows(cesm2, ipsl, ukesm)

# FLUXNET US-MMS monthly means for CMIP6 comparison
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

message("Harmonization complete.")

# =============================================================================
# FIGURE 02a — sub-daily July NEE, all sites (ggplot2)
# =============================================================================
message("\n=== Figure: 02_subdaily_july_nee_allsites.png ===")

ssem_july <- ssem_subdaily |> filter(month(datetime) == 7L)

fluxnet_july <- fluxnet_subdaily |>
  mutate(yr = year(datetime)) |>
  filter(
    (site == "DE-Tha" & yr == obs_year[["DE-Tha"]]) |
    (site == "DK-Sor" & yr == obs_year[["DK-Sor"]]) |
    (site == "US-MMS" & yr == obs_year[["US-MMS"]])
  ) |>
  filter(month(datetime) == 7L)

july_labels <- c(
  "DE-Tha" = sprintf("DE-Tha — Norway spruce (DE) — July %d + SSEM",
                     obs_year[["DE-Tha"]]),
  "DK-Sor" = sprintf("DK-Sor — European beech (DK) — July %d",
                     obs_year[["DK-Sor"]]),
  "US-MMS" = sprintf("US-MMS — mixed deciduous (IN) — July %d  [hourly]",
                     obs_year[["US-MMS"]])
)

p_subdaily <- ggplot(mapping = aes(x = datetime)) +
  geom_ribbon(data = ssem_july, aes(ymin = nee_lo, ymax = nee_hi),
              fill = "steelblue", alpha = 0.30) +
  geom_line(data = ssem_july, aes(y = nee_med),
            colour = "steelblue3", linewidth = 0.5) +
  geom_point(data = fluxnet_july, mapping = aes(y = nee_raw),
             colour = "grey20", alpha = 0.30, size = 0.3) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50",
             linewidth = 0.35) +
  facet_wrap(~ factor(site, levels = names(july_labels), labels = july_labels),
             ncol = 1, scales = "free_x") +
  labs(
    title    = "Sub-daily NEE — July comparison across three temperate forest sites",
    subtitle = paste("Units: μmol CO₂ m⁻² s⁻¹  |  + = source  |",
                     "SSEM shown for DE-Tha 2000 only"),
    x        = NULL,
    y        = expression(NEE ~ (μmol ~ CO[2] ~ m^{-2} ~ s^{-1}))
  ) +
  theme_classic(base_size = 12) +
  theme(strip.background = element_blank(),
        strip.text        = element_text(face = "bold", size = 9),
        panel.spacing     = unit(1.2, "lines"),
        plot.margin       = margin(10, 15, 10, 15))

out_path <- file.path(out_dir, "02_subdaily_july_nee_allsites.png")
ggsave(out_path, plot = p_subdaily,
       width = IN_W, height = IN_H * 1.3, dpi = DPI, units = "in")
report_saved(out_path)

# =============================================================================
# FIGURE 02b — annual daily cycle, all sites (ggplot2)
# =============================================================================
message("\n=== Figure: 02_annual_daily_cycle_allsites.png ===")

annual_fluxnet <- fluxnet_daily |>
  mutate(yr = year(date)) |>
  filter(
    (site == "DE-Tha" & yr == obs_year[["DE-Tha"]]) |
    (site == "DK-Sor" & yr == obs_year[["DK-Sor"]]) |
    (site == "US-MMS" & yr == obs_year[["US-MMS"]])
  ) |>
  mutate(doy = yday(date))

ssem_doy <- ssem_daily |> mutate(doy = yday(date))

annual_labels <- c(
  "DE-Tha" = sprintf("DE-Tha — Norway spruce (DE) — %d", obs_year[["DE-Tha"]]),
  "DK-Sor" = sprintf("DK-Sor — European beech (DK) — %d", obs_year[["DK-Sor"]]),
  "US-MMS" = sprintf("US-MMS — mixed deciduous (IN) — %d", obs_year[["US-MMS"]])
)

p_annual <- ggplot(mapping = aes(x = doy)) +
  geom_ribbon(data = ssem_doy, aes(ymin = nee_lo, ymax = nee_hi),
              fill = "steelblue", alpha = 0.30) +
  geom_line(data = ssem_doy, aes(y = nee_med),
            colour = "steelblue3", linewidth = 0.5) +
  geom_point(data = annual_fluxnet, mapping = aes(y = nee_gCm2d),
             colour = "grey20", alpha = 0.40, size = 0.6) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50",
             linewidth = 0.35) +
  facet_wrap(~ factor(site, levels = names(annual_labels), labels = annual_labels),
             ncol = 1, scales = "free_y") +
  scale_x_continuous(
    breaks = c(1, 60, 121, 182, 244, 305, 366),
    labels = c("Jan", "Mar", "May", "Jul", "Sep", "Nov", "Dec")
  ) +
  labs(
    title    = "Annual cycle of daily NEE — most recent complete year per site",
    subtitle = paste("Units: gC m⁻² day⁻¹  |  + = source  |",
                     "SSEM shown for DE-Tha 2000 only"),
    x        = "Day of year",
    y        = expression(NEE ~ (gC ~ m^{-2} ~ day^{-1}))
  ) +
  theme_classic(base_size = 12) +
  theme(strip.background = element_blank(),
        strip.text        = element_text(face = "bold", size = 9),
        panel.spacing     = unit(1.2, "lines"),
        plot.margin       = margin(10, 15, 10, 15))

out_path <- file.path(out_dir, "02_annual_daily_cycle_allsites.png")
ggsave(out_path, plot = p_annual,
       width = IN_W, height = IN_H * 1.3, dpi = DPI, units = "in")
report_saved(out_path)

# =============================================================================
# FIGURE 02c — cost function metrics (gridExtra table PNG)
# =============================================================================
message("\n=== Figure: 02_cost_functions_table.png ===")

compute_metrics <- function(model_vec, obs_vec) {
  valid <- !is.na(model_vec) & !is.na(obs_vec)
  n     <- sum(valid)
  if (n < 2L) return(list(n=0L, rmse=NA_real_, bias=NA_real_, r=NA_real_))
  res <- model_vec[valid] - obs_vec[valid]
  list(n = n, rmse = sqrt(mean(res^2)), bias = mean(res),
       r = cor(model_vec[valid], obs_vec[valid]))
}

detha_sd_eval <- detha_subdaily |>
  filter(year(datetime) == 2000L, nee_qc <= 1L) |>
  inner_join(ssem_subdaily |> select(datetime, nee_med), by = "datetime")

detha_dd_eval <- fluxnet_daily |>
  filter(site == "DE-Tha", year(date) == 2000L,
         !is.na(nee_gCm2d), nee_qc_mean <= 1.0) |>
  inner_join(ssem_daily |> select(date, nee_med), by = "date")

sd_de <- compute_metrics(detha_sd_eval$nee_med, detha_sd_eval$nee_raw)
dd_de <- compute_metrics(detha_dd_eval$nee_med, detha_dd_eval$nee_gCm2d)
na_m  <- list(n=NA_integer_, rmse=NA_real_, bias=NA_real_, r=NA_real_)

metrics_tbl <- tibble(
  Site        = rep(c("DE-Tha", "DK-Sor", "US-MMS"), each = 2L),
  Timescale   = rep(c("Sub-daily", "Daily"), times = 3L),
  Units       = rep(c("umol/m2/s", "gC/m2/d"), times = 3L),
  N           = c(sd_de$n,    dd_de$n,    na_m$n,  na_m$n,  na_m$n,  na_m$n),
  RMSE        = round(c(sd_de$rmse, dd_de$rmse, na_m$rmse, na_m$rmse,
                        na_m$rmse, na_m$rmse), 3),
  Bias        = round(c(sd_de$bias, dd_de$bias, na_m$bias, na_m$bias,
                        na_m$bias, na_m$bias), 3),
  Correlation = round(c(sd_de$r,    dd_de$r,    na_m$r,   na_m$r,
                        na_m$r,    na_m$r), 3)
)

tbl_grob <- tableGrob(metrics_tbl, rows = NULL,
                      theme = ttheme_default(base_size = 12, padding = unit(c(8, 6), "pt")))

# Add a title above the table using grid.arrange
title_grob <- grid::textGrob(
  "Cost function metrics: SSEM ensemble median vs FLUXNET NEE\nSSEM run at DE-Tha 2000 only; NA = no SSEM at that site",
  gp = grid::gpar(fontsize = 13, fontface = "bold"), just = "centre"
)

out_path <- file.path(out_dir, "02_cost_functions_table.png")
png(out_path, width = PX_W, height = PX_H, res = DPI)
gridExtra::grid.arrange(title_grob, tbl_grob,
                        ncol = 1, heights = c(0.18, 0.82))
invisible(dev.off())
report_saved(out_path)

# =============================================================================
# FIGURES 02d-f — CMIP6 comparisons, one PNG per model (ggplot2)
# =============================================================================
cmip6_models <- c("CESM2", "IPSL-CM6A-LR", "UKESM1-0-LL")

model_colours <- c(
  "FLUXNET US-MMS" = "grey20",
  "CESM2"          = "#E07B39",
  "IPSL-CM6A-LR"   = "#5B8DB8",
  "UKESM1-0-LL"    = "#6BAE75"
)

for (chosen_model in cmip6_models) {

  fname <- paste0("02_cmip6_", chosen_model, "_gpp_rh.png")
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
      facet_wrap(~ variable, ncol = 1, scales = "free_y",
                 labeller = as_labeller(c(
                   GPP = "GPP (gC m⁻² day⁻¹)",
                   Rh  = "Rh / RECO (gC m⁻² day⁻¹) — see note on scale mismatch"
                 ))) +
      scale_colour_manual(values = model_colours[c("FLUXNET US-MMS", chosen_model)]) +
      scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
      labs(
        title    = paste("Monthly GPP and Rh —", chosen_model, "vs FLUXNET US-MMS"),
        subtitle = "1999–2014 | gC m⁻² day⁻¹ | Thick lines: LOESS trend",
        x        = NULL,
        y        = NULL,
        colour   = NULL
      ) +
      theme_classic(base_size = 12) +
      theme(
        legend.position  = "bottom",
        strip.background = element_blank(),
        strip.text       = element_text(face = "bold"),
        plot.margin      = margin(10, 15, 10, 15)
      )

  out_path <- file.path(out_dir, fname)
  ggsave(out_path, plot = p_cmip6,
         width = IN_W, height = IN_H, dpi = DPI, units = "in")
  report_saved(out_path)
}

# =============================================================================
# SUMMARY REPORT
# =============================================================================
message("\n=== Summary ===")
pngs <- list.files(out_dir, pattern = "\\.png$", full.names = TRUE)
sizes_kb <- file.size(pngs) / 1024

cat(sprintf("\n%d PNGs in %s/\n\n", length(pngs), out_dir))
cat(sprintf("  %-55s  %8s\n", "File", "Size KB"))
cat(strrep("-", 68), "\n")
for (i in seq_along(pngs)) {
  flag <- if (sizes_kb[i] < 50) "  *** UNDER 50 KB — CHECK FOR BLANK ***" else ""
  cat(sprintf("  %-55s  %8.0f%s\n", basename(pngs[i]), sizes_kb[i], flag))
}
cat(strrep("-", 68), "\n")
cat(sprintf("  %-55s  %8.0f\n\n", "TOTAL", sum(sizes_kb)))

n_suspect <- sum(sizes_kb < 50)
if (n_suspect == 0L) {
  message("All PNGs above 50 KB — no blank renders detected.")
} else {
  warning(n_suspect, " PNG(s) are under 50 KB and may be blank or failed.")
}
