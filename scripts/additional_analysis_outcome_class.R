#!/usr/bin/env Rscript
# Additional analysis: compare primary-analysis results by original outcome class.

suppressPackageStartupMessages({
  library(dplyr)
})

find_project_root <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE)
    cand <- dirname(dirname(script_path))
    if (dir.exists(file.path(cand, "data")) && dir.exists(file.path(cand, "scripts"))) {
      return(cand)
    }
  }

  wd <- normalizePath(getwd(), mustWork = FALSE)
  candidates <- c(wd, dirname(wd), dirname(dirname(wd)))
  for (cand in unique(candidates)) {
    if (dir.exists(file.path(cand, "data")) && dir.exists(file.path(cand, "scripts"))) {
      return(cand)
    }
  }
  stop("Project root not found. Run from repository root or scripts directory.")
}

fmt_pct <- function(n, denom) {
  if (!is.finite(denom) || denom <= 0) return("")
  sprintf("%d (%.2f%%)", n, 100 * n / denom)
}

fmt_num <- function(x, digits = 2) {
  if (length(x) == 0 || is.na(x)) return("")
  formatC(x, format = "f", digits = digits)
}

base_dir <- find_project_root()
primary_path <- file.path(base_dir, "data", "results", "primary_analysis_results.csv")
out_dir <- file.path(base_dir, "data", "results")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

primary <- read.csv(primary_path, stringsAsFactors = FALSE)

dat <- primary %>%
  filter(outcome_class %in% c("mortality", "survival"))

summary_df <- dat %>%
  group_by(outcome_class) %>%
  summarise(
    n_meta = n(),
    n_reviews = n_distinct(rm5_file),
    sig_changed_n = sum(sig_orig != sig_flip, na.rm = TRUE),
    sig_ns_to_sig_n = sum(sig_change == "non-significant_to_significant", na.rm = TRUE),
    sig_sig_to_ns_n = sum(sig_change == "significant_to_non-significant", na.rm = TRUE),
    grade_changed_n = sum(grade_imp_orig != grade_imp_flip, na.rm = TRUE),
    grade_increased_n = sum(grade_imp_diff > 0, na.rm = TRUE),
    grade_decreased_n = sum(grade_imp_diff < 0, na.rm = TRUE),
    median_grade_diff = median(grade_imp_diff, na.rm = TRUE),
    q1_grade_diff = quantile(grade_imp_diff, 0.25, na.rm = TRUE),
    q3_grade_diff = quantile(grade_imp_diff, 0.75, na.rm = TRUE),
    median_rrr = median(rrr, na.rm = TRUE),
    q1_rrr = quantile(rrr, 0.25, na.rm = TRUE),
    q3_rrr = quantile(rrr, 0.75, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(outcome_class = ifelse(outcome_class == "mortality", "Mortality", "Survival"))

csv_path <- file.path(out_dir, "additional_analysis_outcome_class.csv")
write.csv(summary_df, csv_path, row.names = FALSE)

md_lines <- c(
  "| Outcome orientation | Meta-analyses | Cochrane reviews | Statistical significance changed | Non-significant to significant | Significant to non-significant | GRADE imprecision changed | GRADE increased after flipping | GRADE decreased after flipping | Median GRADE diff (IQR) | Median RRR (IQR) |",
  "| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
)

for (i in seq_len(nrow(summary_df))) {
  r <- summary_df[i, ]
  md_lines <- c(
    md_lines,
    paste(
      "|",
      paste(
        c(
          r$outcome_class,
          r$n_meta,
          r$n_reviews,
          fmt_pct(r$sig_changed_n, r$n_meta),
          fmt_pct(r$sig_ns_to_sig_n, r$n_meta),
          fmt_pct(r$sig_sig_to_ns_n, r$n_meta),
          fmt_pct(r$grade_changed_n, r$n_meta),
          fmt_pct(r$grade_increased_n, r$n_meta),
          fmt_pct(r$grade_decreased_n, r$n_meta),
          sprintf("%s (%s to %s)", fmt_num(r$median_grade_diff), fmt_num(r$q1_grade_diff), fmt_num(r$q3_grade_diff)),
          sprintf("%s (%s to %s)", fmt_num(r$median_rrr), fmt_num(r$q1_rrr), fmt_num(r$q3_rrr))
        ),
        collapse = " | "
      ),
      "|"
    )
  )
}

md_path <- file.path(out_dir, "additional_analysis_outcome_class.md")
writeLines(md_lines, md_path)

message("Wrote: ", csv_path)
message("Wrote: ", md_path)
