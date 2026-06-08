# Setup Instructions — Fluxcourse 2026 Tuesday AM Session
## Super Simple Ecosystem Model (SSEM) exercises

These instructions take about 15 minutes. Complete them before the session starts.

---

### What you need

| Item | Where to get it |
|---|---|
| Exercise files (Rmds) | GitHub: `https://github.com/davidjpmoore/FluxCourseForecast` |
| Data files | Google Drive zip shared by instructors |

---

### Step 1 — Get the exercise files from GitHub

Clone the repository or download it as a ZIP.

**Option A — clone (recommended if you have git):**
```
git clone https://github.com/davidjpmoore/FluxCourseForecast.git
```

**Option B — download ZIP:**
Go to the repository page, click **Code → Download ZIP**, and unzip it anywhere convenient (e.g. `~/Desktop/FluxCourseForecast`).

The exercises you will use are in the `exercises/` folder:
- `01_run_model.Rmd`
- `02_validation.Rmd`
- `03_handoff.Rmd`

---

### Step 2 — Download and unzip the data

1. Download `Tuesday_AM_SSEM_part1.zip` from the Google Drive folder shared by the instructors.
2. Unzip it. You will get a folder called `Tuesday_AM_SSEM_part1/` containing subfolders `US-NR1/`, `US-MMS/`, `cmip6/`, `fluxcom/`, and `R/`.
3. Note the full path to this folder — you will need it in the next step.

---

### Step 3 — Set `data_dir` in each exercise Rmd

Each exercise file has a line near the top of the first code chunk that looks like:

```r
data_dir <- "../data"   # default for codespace
```

**Change this line** to the path of the `Tuesday_AM_SSEM_part1` folder you unzipped.

Examples:
```r
# Mac
data_dir <- "/Users/YourName/Downloads/Tuesday_AM_SSEM_part1"

# Windows
data_dir <- "C:/Users/YourName/Downloads/Tuesday_AM_SSEM_part1"
```

You need to do this in all three Rmd files before knitting.

---

### Step 4 — Install required R packages

1. Open `install_packages.R` (in the `exercises/` folder, also included in the data zip).
2. In RStudio, click **Source** (top-right of the editor pane).
3. Watch the console. It should end with:
   ```
   All packages verified. You are ready to start.
   ```

If any package fails to install, try running `install.packages("packagename")` manually, or contact the instructors.

---

### Step 5 — Run the setup check

1. Open `test_student_setup.R` (in the `exercises/` folder, also in the zip).
2. At the top, check that `data_dir` points to your unzipped data folder (same path as Step 3).
3. Click **Source**.
4. Every line should say `[PASS]`. The final line should say:
   ```
   READY TO START — all 27 checks passed.
   ```

If any check says `[FAIL]`, the message below it explains what is missing and how to fix it.

---

### If something is not working

Contact the instructors before the session:

- **David Moore** — davidjpmoore@arizona.edu

Please include the output from `test_student_setup.R` (copy-paste from the RStudio console) so we can diagnose the problem quickly.
