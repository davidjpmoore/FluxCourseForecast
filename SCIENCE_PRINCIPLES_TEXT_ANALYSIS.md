# SCIENCE_PRINCIPLES_TEXT_ANALYSIS.md — Text and Document Analysis Projects

**Version:** 1.0
**Repository:** EcosystemEcologyLab/lab-principles
**Applies to:** EcosystemEcologyLab text extraction and document analysis projects
**Extends:** SCIENCE_PRINCIPLES.md — read that file first

When copying this file into a project repository, record the source commit hash
in the project's CLAUDE.md alongside the hash for SCIENCE_PRINCIPLES.md.

---

## Scope

These rules apply to any project whose primary purpose is extracting,
classifying, or analysing information from text documents — including policy
documents, scientific literature, grey literature, and other unstructured
sources. Examples include UN policy document analysis, systematic literature
reviews, and evidence synthesis pipelines.

---

## Confidence vocabulary

All text analysis projects in this lab use a shared confidence vocabulary.
This vocabulary applies to any classification, extraction, or rating produced
by the pipeline.

| Level | Meaning |
|-------|---------|
| `HIGH` | Direct evidence present in the source text; all required fields confirmed; no ambiguity |
| `MEDIUM` | Evidence present but partial, indirect, or ambiguous; human review recommended before use in primary results |
| `LOW` | Weak or indirect evidence only; flag but do not use in primary results without human review |
| `UNKNOWN` | Extraction failed, source text missing, or quality insufficient to assign any rating |

Rules:
- Every classification output must carry one of these four values — no other
  quality vocabulary is permitted in pipeline outputs
- `UNKNOWN` is never the same as `LOW` — do not conflate insufficient evidence
  with weak evidence
- `MEDIUM` and `LOW` results must be visibly flagged in any summary or
  figure that includes them
- The threshold between `HIGH` and `MEDIUM` is a scientific judgment set by
  the scientist in the project CLAUDE.md — Claude does not set this threshold

---

## Evidence handling

### Verbatim extraction
- Text extracted from source documents must be reproduced verbatim —
  never paraphrased, summarised, cleaned, or normalised
- Verbatim text must be stored alongside the classification it supports,
  not discarded after classification
- The scientist reviews source text, not Claude's interpretation of it

### Evidence traceability
Every extracted piece of evidence must carry:
- Source document identifier (DOI, URL, or internal document ID)
- Page number or section reference where available
- The verbatim text passage that supports the classification
- The confidence level assigned and the rule applied

### No inference from context
- A classification must be supported by explicit text in the source document
- Do not infer from surrounding context, document title, or author affiliation
- If a required field cannot be found in explicit text, the result is UNKNOWN —
  not an inference from related text

---

## Document processing conventions

- Every source document must be logged in a document registry before processing
  begins — processing an unregistered document is an error
- Failed document loads (corrupt files, access errors, encoding issues) go to
  the unknown log with the reason — they are never silently skipped
- Documents processed multiple times (e.g. during development) must produce
  identical outputs — extraction is deterministic given the same source and rules

---

## Output conventions

In addition to the output metadata required by SCIENCE_PRINCIPLES.md, text
analysis outputs must include:
- `source_document_id` — identifier of the source document for every row
- `verbatim_evidence` — the exact text passage supporting the classification
- `confidence` — one of HIGH / MEDIUM / LOW / UNKNOWN
- `confidence_rule` — the named rule or criterion that determined the
  confidence level
- `reviewer` — `"pipeline"` for automated classifications; the reviewer's
  name for human-reviewed records

---

## Human review workflow

- Results rated MEDIUM or LOW must not appear in primary paper results without
  explicit human sign-off
- Human review decisions must be stored in `data/overrides/` following the
  same override file convention as SCIENCE_PRINCIPLES_PIPELINES.md
- After human review, the confidence level may be upgraded or downgraded —
  both directions are valid and both must be logged
- Claude must never upgrade a confidence level without explicit human instruction
