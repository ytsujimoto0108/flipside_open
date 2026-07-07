#!/usr/bin/env Rscript
# export_table2_summary.R
# Exports Table 2 (primary analysis results stratified by original outcome
# class) as a tidy CSV, mirroring the Table 2 computed in main_analysis.R.

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

base_dir     <- find_project_root()
results_path <- file.path(base_dir, "data", "results", "primary_analysis_results.csv")
out_path     <- file.path(base_dir, "data", "results", "table2_summary.csv")

res <- read.csv(results_path, stringsAsFactors = FALSE)

class_order <- c("mortality", "survival")
rows <- lapply(class_order, function(cls) {
  sub <- res[res$outcome_class == cls, , drop = FALSE]
  n <- nrow(sub)
  data.frame(
    outcome_class      = cls,
    n                  = n,
    sig_changed_n      = sum(sub$sig_orig != sub$sig_flip, na.rm = TRUE),
    sig_up_n           = sum(sub$sig_change == "non-significant_to_significant", na.rm = TRUE),
    sig_down_n         = sum(sub$sig_change == "significant_to_non-significant", na.rm = TRUE),
    ci_narrowed_n      = sum(sub$ci_narrowed, na.rm = TRUE),
    grade_changed_n    = sum(sub$grade_imp_orig != sub$grade_imp_flip, na.rm = TRUE),
    grade_increase_n   = sum(sub$grade_imp_diff > 0, na.rm = TRUE),
    grade_decrease_n   = sum(sub$grade_imp_diff < 0, na.rm = TRUE),
    grade_diff_median  = median(sub$grade_imp_diff, na.rm = TRUE),
    grade_diff_q1      = quantile(sub$grade_imp_diff, 0.25, na.rm = TRUE, names = FALSE),
    grade_diff_q3      = quantile(sub$grade_imp_diff, 0.75, na.rm = TRUE, names = FALSE),
    rrr_median         = median(sub$rrr, na.rm = TRUE),
    rrr_q1             = quantile(sub$rrr, 0.25, na.rm = TRUE, names = FALSE),
    rrr_q3             = quantile(sub$rrr, 0.75, na.rm = TRUE, names = FALSE),
    stringsAsFactors   = FALSE
  )
})

write.csv(do.call(rbind, rows), out_path, row.names = FALSE)
message("Wrote: ", out_path)
