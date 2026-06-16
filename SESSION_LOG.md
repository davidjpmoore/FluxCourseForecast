# SESSION_LOG — FluxCourseForecast

---

## 2026-06-16 — HR workaround added to download_site.R

**Problem:** `FluxCourseSiteExplorer.Rmd` failed for AmeriFlux sites (e.g.
US-MMS) when triggered from a fresh download, because `flux_extract()` in
the fluxnet package v0.3.2 silently skips files whose names contain `_HR_`,
leaving no sub-daily CSV for `prepare_site.R` to read.

**Edits made (two files only, no others touched):**

`data/download_site.R` — added an HR workaround block immediately after the
`flux_extract()` / fallback-extraction section (before §8 "Discover extracted
files"). The block lists the ZIP contents with `zip::zip_list()`, finds any
`_HR_`-named files that `flux_extract()` skipped, extracts them directly with
`zip::unzip()` into `unzip_dir`, and copies them to `out_dir` as
`{site_id}_HR.csv` (FLUXMET sub-daily) and `{site_id}_ERA5_HR.csv`.

`data/prepare_site.R` — **no change required.** Lines 99–115 already check for
both `{site_id}_HH.csv` and `{site_id}_HR.csv` in sequence. The path the
workaround writes (`data/{site_id}/{site_id}_HR.csv`) matches the path
`prepare_site.R` checks (`file.path(data_dir, site_id, paste0(site_id, "_HR.csv"))`)
exactly.

**End-to-end test:** `prepare_site.R` run for US-MMS 2008 (ne=10).
Result: 37/38 checks [PASS]. The one [FAIL] (`params has no NAs`) is a
pre-existing `rbeta` sampling issue that occurs when `ne` is very small
(ne=10 triggers degenerate beta parameters) and is unrelated to the HR fix.
The HR file was found correctly at `data/US-MMS/US-MMS_HR.csv`, all flux,
date, inputs, nep, X, X.orig, and params objects were created successfully.

---

## 2026-06-16 — CMIP6 and FLUXCOM data documentation

Task: read `data/cmip6/` and `data/fluxcom/` CSV files and produce a prose
summary of both data sources suitable for a methods section or student guide.
Files examined: all 12 CMIP6 CSVs and 4 FLUXCOM CSVs under
`exercises/student_data/Tuesday_AM_SSEM_part1/`; the Python extraction scripts
recovered from git history (`extract_cmip6.py`, `extract_cmip6_allsites.py`);
`build_dashboard.R`; and the readme under the dashboard package.
No source files were modified.

---

### Methods summary: CMIP6 and FLUXCOM data sources

#### CMIP6 Earth System Models

Monthly output from three CMIP6 Earth system models (ESMs) was extracted from
the Pangeo Google Cloud CMIP6 archive for the four course sites: US-NR1 (Niwot
Ridge, Colorado; 40.0329°N, 105.5464°W), US-MMS (Morgan Monroe State Forest,
Indiana; 39.3232°N, 86.4131°W), DE-Tha (Tharandt, Germany; 50.9636°N,
13.5669°E), and DK-Sor (Sorø, Denmark; 55.4859°N, 11.6446°E). The three
models are CESM2 (Community Earth System Model version 2, developed at the
National Center for Atmospheric Research), IPSL-CM6A-LR (Institut
Pierre-Simon Laplace Coupled Model 6A, low-resolution configuration), and
UKESM1-0-LL (United Kingdom Earth System Model version 1, low-resolution
configuration, developed jointly by the UK Met Office Hadley Centre and the
Natural Environment Research Council). These three were chosen because they
are well-established, widely cited ESMs with distinct land surface
formulations — CLM5 in CESM2, ORCHIDEE in IPSL-CM6A-LR, and JULES in
UKESM1-0-LL — and because all three have the necessary monthly land variable
output (the CMIP6 "Lmon" table) archived on Pangeo with no credentials required.

For each model, the historical experiment covers January 1980 through December
2014, consistent with the CMIP6 convention that historical runs terminate at
the close of 2014. For the 2015–2021 period, IPSL-CM6A-LR uses the SSP2-4.5
scenario (experiment_id ssp245), the intermediate shared socioeconomic pathway
representing moderate mitigation of greenhouse gas emissions. CESM2 uses
SSP3-7.0 (ssp370) rather than SSP2-4.5 because SSP2-4.5 Lmon output for
CESM2 was not present in the Pangeo catalog at the time of extraction; ssp370
represents a higher-emission trajectory, so students should be aware that
near-term CESM2 projections diverge from the scenario used by IPSL. UKESM1-0-LL
has no future scenario in the Pangeo catalog for the Lmon table, so all
UKESM1-0-LL output corresponds to the historical experiment only, ending
December 2014.

Ensemble member selection was also determined by catalog availability rather
than any systematic ensemble design. IPSL-CM6A-LR uses r1i1p1f1 for both the
historical and ssp245 runs, providing a single continuous simulation chain
from one initial condition, physics package, and forcing specification. CESM2
uses r1i1p1f1 for the historical period but r4i1p1f1 for the ssp370 period,
because r4i1p1f1 is the only ssp370 member with Lmon output in the Pangeo
catalog; this means the CESM2 record crosses ensemble members at January 2015
and is not a single continuous simulation. UKESM1-0-LL uses r1i1p1f2 for the
historical run; the UKESM project applies forcing label f2 to its standard
production runs, so all UKESM member IDs end in p1f2 rather than p1f1.

The date ranges in the extracted CSVs therefore differ by model. CESM2 and
IPSL-CM6A-LR each span January 1980 through December 2021, with a scenario
change at January 2015. UKESM1-0-LL spans January 1980 through December 2014
only. This difference is a data-availability limitation of the Pangeo catalog,
not a property of the UKESM model itself.

Each grid cell was identified by selecting the nearest-neighbor point in the
model output to the tower coordinates listed above. Longitudes stored on a
0°–360° scale (as in CESM2) were first converted to the −180°–180° convention
before selection. The native horizontal resolution of the models is approximately
1° for CESM2, 2.5° longitude × 1.25° latitude for IPSL-CM6A-LR, and 1.25°
longitude × ~0.83° latitude for UKESM1-0-LL, so a single extracted grid cell
represents a spatial footprint of roughly 5,000–80,000 km² depending on the
model and site latitude, compared to the sub-km² footprint of an eddy covariance
tower.

The CSV files contain twelve variables extracted from the Lmon and Amon tables:
gross primary production (gpp_kgC_m2_s, kg C m⁻² s⁻¹), net primary production
(npp_kgC_m2_s, kg C m⁻² s⁻¹), heterotrophic respiration (rh_kgC_m2_s,
kg C m⁻² s⁻¹), autotrophic respiration (ra_kgC_m2_s, kg C m⁻² s⁻¹), net
biome production (nbp_kgC_m2_s, kg C m⁻² s⁻¹), leaf area index (lai_m2_m2,
m² m⁻²), surface downwelling shortwave radiation (sw_down_sfc_W_m2, W m⁻²),
surface upwelling shortwave radiation (sw_up_sfc_W_m2, W m⁻²), surface
downwelling longwave radiation (lw_down_atm_W_m2, W m⁻²), surface upwelling
longwave radiation (lw_up_sfc_W_m2, W m⁻²), surface upward latent heat flux
(latent_heat_W_m2, W m⁻²), and surface upward sensible heat flux
(sensible_heat_W_m2, W m⁻²). For CESM2 in the ssp370 period (2015–2021),
npp, rh, ra, and nbp are absent from the Pangeo catalog for the r4i1p1f1
member, so those columns contain missing values for all months after December
2014 in the CESM2 files; gpp, lai, and the energy variables are present for
the full record. Net ecosystem exchange (NEE) was not available as a direct
model output in the catalog; in the dashboard it is therefore derived as
Ra + Rh − GPP, which equals −NEP. This approximation omits land-use change
fluxes and lateral carbon transport that contribute to the model's native
NBP variable, and should be interpreted as an approximation of ecosystem NEE
rather than a full carbon budget quantity.

#### FLUXCOM-X-BASE

FLUXCOM-X-BASE monthly carbon flux and evapotranspiration estimates were
obtained from the ICOS Carbon Portal (Nelson et al. 2024, Biogeosciences;
data DOI: https://doi.org/10.18160/5NZG-JMJE) under a Creative Commons
CC-BY 4.0 licence. The FLUXCOM-X-BASE product applies machine learning
algorithms trained on eddy covariance measurements from global flux tower
networks to upscale tower-measured carbon and water fluxes onto a continuous
0.5° global grid. Data were extracted for the four course sites as single
0.5° grid cells, covering January 2001 through December 2021 at monthly
temporal resolution.

Each extracted CSV contains four variables expressed as mean daily rates for
the calendar month: gross primary production (GPP_gC_m2_d, gC m⁻² d⁻¹),
net ecosystem exchange (NEE_gC_m2_d, gC m⁻² d⁻¹; negative values indicate
carbon uptake by the ecosystem), total ecosystem respiration (TER_gC_m2_d,
gC m⁻² d⁻¹; defined as GPP − NEE in the FLUXCOM-X-BASE framework), and
evapotranspiration (ET_mm_d, mm d⁻¹). Monthly totals can be obtained by
multiplying each daily rate by the number of days in the corresponding month.

At the latitudes of the four sites the 0.5° grid cell represents a spatial
footprint of roughly 2,000–3,000 km², a scale intermediate between the
sub-km² footprint of a single eddy covariance tower and the ~5,000–80,000 km²
represented by a CMIP6 grid cell. This intermediate scale makes FLUXCOM-X-BASE
a useful bridge reference for the course exercise. Because the product is
directly trained on flux tower observations, its estimates are observationally
constrained in a way that free-running Earth system models are not. When the
tower-calibrated SSEM and FLUXCOM-X-BASE agree while both disagree with CMIP6,
there is stronger grounds to infer a systematic large-scale model bias than a
direct tower-versus-CMIP6 comparison could provide alone. Conversely, when the
tower model and FLUXCOM-X-BASE disagree, the discrepancy is more likely
attributable to local heterogeneity, land-cover variation, or disturbance
history that a 0.5° product cannot resolve. FLUXCOM-X-BASE therefore provides
students with a way to ask whether a model-data mismatch is a site-scale
peculiarity or a pattern that holds at regional scales.
