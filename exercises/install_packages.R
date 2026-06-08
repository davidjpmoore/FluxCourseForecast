# =============================================================================
# FluxCourseForecast — Package Installation Script
# Run this ONCE before the Tuesday AM session.
# It installs everything needed for all three exercises.
# Takes approximately 5-10 minutes on a fresh R installation.
# =============================================================================
#
# HOW TO RUN
#   Open RStudio, then either:
#     • Source this file: File → Open → install_packages.R → Source button
#     • Or paste this whole file into the Console and press Enter
#
# NOTE
#   This script uses plain install.packages() so it works on any laptop
#   regardless of your R setup.  No renv, no pak, no conda needed.
# =============================================================================

packages <- c(
  # Core data manipulation and visualisation (loads dplyr, ggplot2, readr,
  # tidyr, purrr, stringr, forcats, and lubridate in one go)
  "tidyverse",

  # Date and time arithmetic — also pulled in by tidyverse, but listed
  # explicitly because functions.R uses it at the top level
  "lubridate",

  # R Markdown — needed to knit the three exercise documents
  "rmarkdown",

  # Multivariate normal distributions — used by the SSEM particle filter
  # in R/functions.R (mvtnorm::rmvnorm)
  "mvtnorm",

  # MCMC diagnostics — used by R/utils.R (mat2mcmc.list) when inspecting
  # particle filter output
  "coda"
)

# Note: the `compiler` package is part of base R and is always available —
# it does not need to be installed.

# =============================================================================
# Install any missing packages
# =============================================================================
missing <- packages[!packages %in% installed.packages()[, "Package"]]

if (length(missing) > 0) {
  message("Installing ", length(missing), " missing package(s): ",
          paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  message("All packages already installed.")
}

# =============================================================================
# Verify all installed correctly
# =============================================================================
failed <- packages[!packages %in% installed.packages()[, "Package"]]

if (length(failed) > 0) {
  stop("The following packages failed to install: ",
       paste(failed, collapse = ", "),
       "\n\nTry installing them individually, e.g.:\n",
       "  install.packages(\"", failed[1], "\", repos = \"https://cloud.r-project.org\")")
} else {
  message("All packages verified. You are ready to start.")
  message("Next step: run test_student_setup.R to confirm your data files are in place.")
}
