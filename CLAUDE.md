# CLAUDE.md — [PROJECT NAME]

<!-- 
  INSTRUCTIONS FOR FILLING IN THIS TEMPLATE:
  - Replace all text in [SQUARE BRACKETS] with project-specific content
  - Remove all instruction comments (like this one) before committing
  - Do not delete any section headings — if a section is not applicable,
    write "Not applicable to this project" rather than deleting it
-->

## Lab Principles Source

<!-- Record the commit hash of EcosystemEcologyLab/lab-principles that was
     used to initialise this project. This makes the version of standards
     traceable for any published result. -->

- Repository: EcosystemEcologyLab/lab-principles
- Commit: [PASTE COMMIT HASH HERE — run: git ls-remote https://github.com/EcosystemEcologyLab/lab-principles HEAD]
- Copied: [DATE]
- SCIENCE_PRINCIPLES.md [VERSION e.g. v1.0]
- [SCIENCE_PRINCIPLES_PIPELINES.md v1.0 — include if applicable]
- [SCIENCE_PRINCIPLES_TEXT_ANALYSIS.md v1.0 — include if applicable]

---

## Project Context

<!-- 2–4 sentences describing what this project is, what it produces, and
     who it is for. Be specific enough that Claude Code can orient itself
     without needing additional context. -->

[DESCRIBE THE PROJECT HERE]

**PI:** [Name, institution]  
**Collaborators:** [Names and institutions if applicable]  
**Funding:** [Funding source if applicable]  
**Repository:** https://github.com/EcosystemEcologyLab/[REPO-NAME]  

---

## Hard Rules — Read These First

<!-- List the project-specific constraints that Claude Code must never
     violate. These extend the hard rules in SCIENCE_PRINCIPLES.md.
     Common examples are given below — keep what applies, add what is
     missing, remove what is not relevant. -->

### 1. Data sources
<!-- Which datasets are permitted? Which are explicitly forbidden?
     Be specific about product names, versions, and access methods. -->

[DESCRIBE PERMITTED AND FORBIDDEN DATA SOURCES]

### 2. Credentials and secrets
All credentials must be read from environment variables. Never hard-code
any credential, API key, password, or token. See `.env.example` for the
full list of required environment variables.

### 3. Data files
The following directories are gitignored and must never be committed:
[LIST GITIGNORED DATA DIRECTORIES e.g. data/raw/, data/processed/]

The following directories are git-tracked:
[LIST TRACKED DIRECTORIES e.g. data/snapshots/, data/overrides/]

### 4. [ADD PROJECT-SPECIFIC HARD RULES AS NEEDED]

---

## Environment Variables

<!-- List all environment variables the project uses. Copy from .env.example. -->

| Variable | Purpose | Default |
|---|---|---|
| [VARIABLE_NAME] | [Purpose] | [Default or "required"] |

---

## Pipeline Execution Order

<!-- If the project has numbered scripts, list them here with a one-line
     description of each. If not applicable, remove this section. -->

```
[01_script.R]   → [What it does]
[02_script.R]   → [What it does]
```

---

## Coding Conventions

### Language and style
- Primary language: [R / Python / other]
- [Add style guide reference e.g. tidyverse style guide URL]
- [Add pipe preference e.g. use base R pipe |> not %>%]

### Package preferences
- [List preferred packages for data manipulation, plotting, etc.]
- Do not introduce new package dependencies without discussion

### Functions
- Every function must have documentation (roxygen2 for R, docstrings for Python)
- Every function must have at least one test

---

## QC and Quality Standards

<!-- Describe the quality control approach for this project. If using
     FLUXNET QC flags, use the template below. Otherwise adapt. -->

[DESCRIBE QC APPROACH AND THRESHOLDS]

---

## Confidence and Quality Vocabulary

<!-- State whether this project uses the shared HIGH/MEDIUM/LOW/UNKNOWN
     vocabulary from SCIENCE_PRINCIPLES.md, or a project-specific system.
     If using a project-specific system, define it here. -->

[ADOPT OR DEFINE CONFIDENCE VOCABULARY]

---

## Output Metadata

<!-- Every output must carry provenance metadata per SCIENCE_PRINCIPLES_PIPELINES.md.
     Describe the format used in this project (companion JSON, CSV header, etc.)
     and where session info is saved. -->

[DESCRIBE OUTPUT METADATA FORMAT]

---

## Exclusion Logging

<!-- Describe where and how exclusions are logged in this project,
     per SCIENCE_PRINCIPLES_PIPELINES.md conventions. -->

[DESCRIBE EXCLUSION LOG LOCATION AND FORMAT]

---

## Known Pending Items

<!-- List any known limitations, stopgap functions, or pending upstream
     fixes that affect this project. Update this list as issues are resolved. -->

| Item | Tracked in |
|---|---|
| [Description] | [GitHub issue URL] |

---

## Data Use and Citation

<!-- List any data use agreements, required citations, or attribution
     requirements that apply to data used in this project. -->

[LIST REQUIRED CITATIONS AND DATA USE OBLIGATIONS]
