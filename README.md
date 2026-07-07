# flipside_open

Source code for the meta-epidemiological study on flipping dichotomous outcomes
in Cochrane meta-analyses, referenced from the manuscript's Data availability
statement. Raw Cochrane RevMan data are not redistributed here; they are
available from the corresponding author upon reasonable request.

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
        +-- scripts/additional_analysis_outcome_class.R
        +-- scripts/export_table2_summary.R        -> table2_summary.csv (Table 2)
        +-- scripts/additional_analysis_or.R       -> or_analysis_results.csv
              +-- scripts/fig2_rr_or_scatter_panels.R  (Figure 2: RR/OR scatter)
              +-- scripts/fig3_rrr_ror_hist_panels.R   (Figure 3: RRR/ROR histograms)
scripts/fig_bland_altman_logrr.R (Supplementary Figure S1)
```

R scripts are run under `renv`; the main R packages used are `meta`,
`metafor`, `dplyr`, `ggplot2`, `scales`, and `cowplot`. Python scripts use
only the standard library (`csv`, `re`, `xml.etree.ElementTree`, `pathlib`).

## Tests

```bash
python3 -m unittest discover -s tests -v
```
