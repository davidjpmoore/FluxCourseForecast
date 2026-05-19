# CLAUDE.md — FluxCourseForecast

## Lab Principles Source

- Repository: EcosystemEcologyLab/lab-principles
- Commit: 11259a0826621be031b6f482cc3780780f2f1dde
- Copied: 2026-05-19
- SCIENCE_PRINCIPLES.md v1.0

---

## Project Context

FluxCourseForecast is a teaching repository for the Fluxcourse 2026 course
(June 7–18, Bloomington, Indiana). It provides annotated R Markdown exercises
that walk students through running a simple process-based carbon cycle model
(SSEM, Super Simple Ecosystem Model), comparing its output to eddy covariance
observations, remote sensing products, FLUXCOM upscaled fluxes, and CMIP6 Earth
system model output. The primary learning objectives are model validation logic,
cost function design, and the conceptual differences between simple open-system
models and full land surface models.

**PI:** David J.P. Moore, University of Arizona
**Collaborators:** Mike Dietze, Boston University (upstream SSEM code and particle filter)
**Funding:** Not applicable
**Repository:** https://github.com/davidjpmoore/FluxCourseForecast
**Upstream:** https://github.com/mdietze/FluxCourseForecast

---

## Hard Rules — Read These First

### 1. Data sources

Permitted sources:
- US-MMS (Morgan Monroe State Forest) FLUXNET data via the EcosystemEcologyLab
  fluxnet R package (https://github.com/EcosystemEcologyLab/fluxnet-package)
- FLUXCOM-X-BASE monthly data from the ICOS Carbon Portal
  (https://doi.org/10.18160/5NZG-JMJE)
- MODIS LAI for US-MMS via the AmeriFlux MODIS tool
  (https://ameriflux.lbl.gov/sites/siteinfo/US-MMS#related.modis)
- CMIP6 output (CESM2, IPSL-CM6A-LR, UKESM1-0-LL) extracted from the Pangeo
  Google Cloud CMIP6 catalog; pre-extracted CSVs are stored in data/cmip6/
- SSEM model output generated live by running R/functions.R

Forbidden:
- Do not download or commit raw FLUXNET zip files — use the fluxnet package only
- Do not access CMIP6 data from ESGF directly in scripts students will run;
  use the pre-extracted CSVs in data/cmip6/ only

### 2. Credentials and secrets

All credentials must be read from environment variables. Never hard-code any
credential, API key, password, or token. The fluxnet package handles
authentication internally; do not expose tokens in scripts.

### 3. Data files

The following directories are gitignored and must never be committed:
- data/raw/
- data/cmip6/raw/

The following directories are git-tracked:
- data/cmip6/      (pre-extracted CSVs only, small files)
- data/examples/   (small example datasets used in exercises)

### 4. Teaching code standards

This is a teaching repository. Code must be heavily annotated in plain language
that a graduate student encountering the topic for the first time can follow.
Every non-obvious line should have a comment explaining what it does and why.
Do not optimise for brevity — optimise for clarity.

### 5. Unit conventions

SSEM outputs carbon fluxes in umol m-2 s-1 and pool sizes in Mg ha-1.
FLUXNET variables use umol m-2 s-1 for fluxes and standard SI for met drivers.
FLUXCOM and CMIP6 outputs use kg m-2 s-1 for carbon fluxes and W m-2 for
energy fluxes. Unit harmonization code must be explicit, annotated, and
centralised in a single conversion script — never inline and unremarked.

---

## Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| FLUXNET_TOKEN | Authentication for fluxnet shuttle | required |

---

## Pipeline Execution Order

This repository does not have a numbered pipeline. The primary deliverable is
a set of R Markdown documents that are run sequentially by students. Order:

```
R/functions.R               → SSEM model and particle filter (source this first)
exercises/01_run_model.Rmd  → Run SSEM, explore output
exercises/02_validation.Rmd → Load observations, harmonize units, compute cost functions
data/cmip6/                 → Pre-extracted CSVs, read directly in 02_validation.Rmd
```

---

## Coding Conventions

### Language and style
- Primary language: R
- Style: tidyverse style guide (https://style.tidyverse.org)
- Use base R pipe |> not %>%
- Use tidyverse for data manipulation and ggplot2 for all figures
- Python is used only for the one-time CMIP6 extraction script; it is not
  part of the student-facing materials

### Package preferences
- fluxnet (EcosystemEcologyLab) for FLUXNET data access
- tidyverse, lubridate, ncdf4, tidync for data handling
- ggplot2 for all visualisation
- Do not introduce new package dependencies without discussion

### Functions
- Every function must have a roxygen2 header
- Teaching helper functions live in R/helpers.R, not inline in Rmd files

---

## QC and Quality Standards

FLUXNET data: use NEE_VUT_REF and GPP_NT_VUT_REF as primary variables.
Retain only records with NEE_VUT_REF_QC >= 0.5 for half-hourly comparisons.
For daily and annual aggregations, document the gap-filling assumptions explicitly
in the R Markdown narrative.

CMIP6 data: pre-extracted and provided as-is. Flag any fill values (typically
1e20) as NA on load.

---

## Confidence and Quality Vocabulary

This project uses the shared HIGH / MEDIUM / LOW / UNKNOWN vocabulary from
SCIENCE_PRINCIPLES.md where applicable. In the teaching context, confidence
levels on model-data comparisons should be discussed qualitatively with students
rather than programmatically assigned.

---

## Output Metadata

Each exercise Rmd, when knitted, produces an HTML file. At the top of each Rmd,
record the date, the R session info, and the git commit hash of the repository.
Use the following block at the start of every Rmd:

```r
cat("Date:", format(Sys.time(), "%Y-%m-%d %H:%M"), "\n")
cat("Commit:", system("git rev-parse --short HEAD", intern = TRUE), "\n")
sessionInfo()
```

---

## Exclusion Logging

Not applicable to this project. Exclusions from FLUXNET data are handled by
QC flags documented in the R Markdown narrative, not in a separate log file.

---

## Known Pending Items

| Item | Tracked in |
|---|---|
| CMIP6 extraction script not yet written | to be completed before course |
| 02_validation.Rmd not yet drafted | in progress |
| Upstream merge with mdietze/FluxCourseForecast pending | coordinate with Mike Dietze |

---

## Data Use and Citation

FLUXNET / AmeriFlux US-MMS data are shared under CC-BY-4.0. Cite the site
team and the AmeriFlux network per the data download agreement. Citation
information is returned by flux_listall() in the fluxnet package.

FLUXCOM-X-BASE: cite Nelson et al. (2024), Biogeosciences, and the ICOS
Carbon Portal DOI (https://doi.org/10.18160/5NZG-JMJE).

CMIP6 data: cite the modelling groups for each model used (CESM2, IPSL-CM6A-LR,
UKESM1-0-LL) per the CMIP6 data use guidelines
(https://pcmdi.llnl.gov/CMIP6/TermsOfUse).

SSEM model code: cite Mike Dietze and the mdietze/FluxCourseForecast repository.
