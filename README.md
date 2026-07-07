# flipside_open

Source code for the meta-epidemiological study on flipping dichotomous outcomes
in Cochrane meta-analyses, referenced from the manuscript's Data availability
statement. Raw Cochrane RevMan data are not redistributed here; they are
available from the corresponding author upon reasonable request.

Every script below implements one step described in the manuscript's Methods
section (Screening / Data extraction / Data analysis). Section names in
parentheses refer to that section.

## Pipeline

```text
data/rm5/*.rm5
  |
  +-- scripts/screen_outcomes.py        -> screening_candidates_v2.csv, adjudication template
  |     (manual adjudication)           -> screening_adjudication_v2.csv
  +-- scripts/finalize_screening.py     -> screening_matches_v2.csv, screening_audit_v2.csv
  +-- scripts/review_level_exclusions.py -> review_exclusion_breakdown.csv
  +-- scripts/extract_meta_data.py      -> meta_analyses_extracted.csv, meta_analysis_studies.csv
        |
        +-- scripts/main_analysis.R (sources cer_helpers.R)
        |     -> primary_analysis_results.csv, primary_analysis_summary.md
        +-- scripts/analyze_meta_characteristics.R -> meta_characteristics_summary.csv/.md (Table 1)
        +-- scripts/subgroup_analysis_rrr.R        -> subgroup_rrr_summary.csv (Figure 4)
        +-- scripts/export_table2_summary.R        -> table2_summary.csv (Table 2)
        +-- scripts/additional_analysis_or.R       -> or_analysis_results.csv
              +-- scripts/fig2_rr_or_scatter_panels.R  (Figure 2: RR/OR scatter)
              +-- scripts/fig3_rrr_ror_hist_panels.R   (Figure 3: RRR/ROR histograms)
scripts/fig_bland_altman_logrr.R (Supplementary Figure S1)
```

## Script descriptions

### Screening

The Methods section describes identifying eligible meta-analyses by filtering
outcome names for death/survival-domain keywords, excluding composite
outcomes automatically, and sending outcome names with an ambiguous
connector ("and," "or," "and/or," "/") to manual review by one reviewer (YT).

- **`scripts/screen_outcomes.py`** — Reads each `.rm5` file, keeps only the
  most recent version of each Cochrane review (by DOI publication number, or
  by title/modification date when no DOI is available), and for every
  dichotomous outcome using OR or RR checks whether the outcome name contains
  a death/survival-domain keyword ("death," "deaths," "died," "dead,"
  "mortality," "fatality," "fatalities," "alive," or "survival"). It then
  applies the automatic composite-outcome rule (explicit markers such as
  "composite," "morbidity," "serious adverse event," or a keyword joined
  directly to another outcome component by "and/or," "or," "and," or "/,"
  while still accepting complementary pairs like "death/alive" and repeated
  timepoints like "death at 30 days and 1 year"). Outcomes the rule cannot
  classify are written to a blank adjudication template for manual review.
  Output: `screening_candidates_v2.csv` (automatic decision per outcome) and
  `screening_adjudication_template_v2.csv` (rows requiring a manual
  `include`/`exclude` decision, filled in by hand as
  `screening_adjudication_v2.csv`).
- **`scripts/finalize_screening.py`** — Combines the automatic candidates
  with the completed manual adjudications into the final include/exclude
  decision for each outcome, and writes a full audit trail. Output:
  `screening_matches_v2.csv` (outcomes carried forward to data extraction)
  and `screening_audit_v2.csv` (every candidate with its automatic decision,
  manual decision if any, and final decision/reason).
- **`scripts/review_level_exclusions.py`** — Re-walks every Cochrane review
  that was *not* included and records the furthest screening stage each of
  its outcomes reached (no dichotomous outcome / not OR or RR or not
  estimable / no death-survival keyword / composite outcome / 2x2 table not
  extractable / fewer than two studies / excluded on manual review). Output:
  `review_exclusion_breakdown.csv`, the counts reported in the Figure 1 flow
  diagram.

### Data extraction

The Methods section describes extracting, for each eligible meta-analysis,
the review's bibliographic data, the outcome name and class (mortality or
survival), the per-study 2x2 event/participant counts, and the statistical
model used.

- **`scripts/extract_meta_data.py`** — Parses the `.rm5` XML for every
  outcome kept in `screening_matches_v2.csv` and extracts the review's
  bibliographic metadata (ID, DOI, title, publication issue/year), the
  outcome name and pooling method/model, the meta-analysis-level event and
  participant totals, and whether the meta-analysis includes a single-zero
  or double-zero study. Output: `meta_analyses_extracted.csv`
  (one row per meta-analysis) and `meta_analysis_studies.csv` (one row per
  study within each meta-analysis, with the study-level 2x2 counts used by
  the primary analysis).

### Data analysis — characteristics table (Table 1)

- **`scripts/analyze_meta_characteristics.R`** — Tabulates the
  characteristics of the meta-analyses included in the paired primary
  analysis (total participants, total events, intervention and control
  event rates, statistical significance, and the presence of single-zero or
  double-zero studies), stratified by original effect measure (OR or RR)
  and by outcome class (mortality or survival), as described in the Methods.
  Control event rates are estimated with the same GLMM/aggregate-fallback
  method as the primary analysis (`cer_helpers.R`). Output:
  `meta_characteristics_summary.csv` / `.md` (Table 1).

### Data analysis — primary analysis

The Methods section's primary analysis runs, for each included
meta-analysis, an original and a flipped random-effects Mantel-Haenszel RR
(double-zero studies omitted, single-zero studies given a 0.5 continuity
correction on all four cells), re-expresses the flipped pooled RR as its
reciprocal (RRf), and compares statistical significance, 95% CI width, and
GRADE imprecision (absolute risk difference vs. the 13/32/62-per-1000
thresholds, using a control event rate from a random-effects binomial-normal
GLMM with aggregate-rate fallback). It also defines the ratio of risk ratios
(RRR) and plots the original vs. flipped estimates and a Bland-Altman
comparison.

- **`scripts/cer_helpers.R`** — Estimates each meta-analysis's control event
  rate: a random-effects binomial-normal GLMM with a logit link fitted to
  the study-specific control-group counts, falling back to the aggregate
  control event rate (total control events / total control participants) if
  the GLMM fails to converge, times out, or the data are degenerate. Sourced
  by `main_analysis.R` and `analyze_meta_characteristics.R`.
- **`scripts/main_analysis.R`** — Runs the original and flipped
  random-effects Mantel-Haenszel RR for every meta-analysis, applies the
  continuity correction and double-zero omission, computes the reciprocal
  flipped RR (RRf), the ratio of risk ratios (RRR), statistical significance
  and CI-ratio changes, and GRADE imprecision before and after flipping.
  Output: `primary_analysis_results.csv` (the per-meta-analysis results
  table that every downstream R script reads) and
  `primary_analysis_summary.md`, plus draft versions of the scatter,
  histogram, and Bland-Altman plots later superseded by the dedicated figure
  scripts below.
- **`scripts/export_table2_summary.R`** — Reads
  `primary_analysis_results.csv` and summarizes the primary-analysis results
  (significance changes, CI narrowing, GRADE imprecision changes, RRR)
  stratified by original outcome class (mortality vs. survival). Output:
  `table2_summary.csv` (Table 2).

### Data analysis — post-hoc odds ratio analysis

The Methods section describes repeating the primary analysis using ORs
instead of RRs, to test whether ORs are less sensitive to flipping.

- **`scripts/additional_analysis_or.R`** — Mirrors `main_analysis.R`'s
  zero-handling and Mantel-Haenszel pooling exactly, but pools odds ratios
  instead of risk ratios, producing the original and reciprocal-flipped OR
  (ORf) and the ratio of odds ratios (ROR). GRADE imprecision and CER are not
  computed here because they are RR-scale (absolute-risk) concepts. Output:
  `or_analysis_results.csv`.

### Data analysis — subgroup analysis

The Methods section's subgroup analysis compares the distribution of RRR by
total sample size (<1000 vs. ≥1000), baseline control event rate (<5% vs.
≥5%), and presence vs. absence of single-zero or double-zero studies, using
the median and IQR of RRR per subgroup.

- **`scripts/subgroup_analysis_rrr.R`** — Joins the primary-analysis results
  to per-meta-analysis subgroup labels (built from the study-level 2x2 data)
  and summarizes the direction-aligned RRR (see below) by subgroup level.
  Output: `subgroup_rrr_summary.csv` and the forest-style plot for Figure 4.

### Figures

- **`scripts/fig2_rr_or_scatter_panels.R`** — Figure 2: two-panel scatter
  plot of the original vs. reciprocal-flipped pooled RR (panel a) and OR
  (panel b) on the log scale, colored by whether the meta-analysis includes
  a single-zero or double-zero study, with the identity line.
- **`scripts/fig3_rrr_ror_hist_panels.R`** — Figure 3: two-panel histogram
  of the direction-aligned RRR (panel a) and ROR (panel b) distributions on
  a shared log-x-axis range.
- **`scripts/fig_bland_altman_logrr.R`** — Supplementary Figure S1:
  Bland-Altman plot of the direction-aligned log(RRo) vs. log(RRf), with the
  mean difference (bias) and 95% limits of agreement.

Note on "direction-aligned" quantities: the subgroup, Figure 3, and
Supplementary Figure S1 scripts use RRR'/ROR' (both the original and
flipped estimate inverted together whenever the original estimate exceeded
1), so that values above/below 1 consistently mean flipping moved the
estimate toward/away from the null across all meta-analyses. Table 2 and
Figure 2 use the unprimed RRR/ROR, which does not have this property (see
Discussion in the manuscript).

## Environment

R scripts are run under `renv`; the main R packages used are `meta`,
`metafor`, `dplyr`, `ggplot2`, `scales`, and `cowplot`. Python scripts use
only the standard library (`csv`, `re`, `xml.etree.ElementTree`, `pathlib`).

## Tests

```bash
python3 -m unittest discover -s tests -v
```

`tests/test_screen_outcomes.py` and `tests/test_finalize_screening.py` cover
the outcome-name classification rules and the automatic/manual decision
merge logic used in screening.
