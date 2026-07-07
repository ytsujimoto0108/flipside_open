#!/usr/bin/env Rscript
# Summarize characteristics of meta-analyses included in the paired primary analysis.

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

base_dir <- find_project_root()
meta_path <- file.path(base_dir, "data", "meta_analyses_extracted.csv")
studies_path <- file.path(base_dir, "data", "meta_analysis_studies.csv")
primary_path <- file.path(base_dir, "data", "results", "primary_analysis_results.csv")
summary_csv <- file.path(base_dir, "data", "meta_characteristics_summary.csv")
summary_md  <- file.path(base_dir, "data", "meta_characteristics_summary.md")
source(file.path(base_dir, "scripts", "cer_helpers.R"))

fmt_int   <- function(x) formatC(x, format = "d", big.mark = ",")
# Manuscript convention: below 10, keep one decimal place; 10 or above, round to a whole number.
fmt_sig <- function(x) {
  if (length(x) == 0 || is.na(x)) return("")
  if (x < 10) formatC(x, format = "f", digits = 1) else formatC(round(x), format = "d")
}
fmt_pct   <- function(n, denom) {
  if (length(n) == 0 || is.na(n) || length(denom) == 0 || is.na(denom) || denom == 0)
    return("")
  sprintf("%s (%s%%)", fmt_int(n), fmt_sig(n / denom * 100))
}

estimate_control_cer_by_meta <- function(path, keep_keys = NULL) {
  studies <- read.csv(path, stringsAsFactors = FALSE)
  for (col in c("events_1", "events_2", "total_1", "total_2")) {
    if (col %in% names(studies)) studies[[col]] <- as.numeric(studies[[col]])
  }
  if (!is.null(keep_keys)) {
    studies <- studies[paste(studies$rm5_file, studies$comparison_id) %in% keep_keys, , drop = FALSE]
  }

  keys <- unique(studies[, c("rm5_file", "comparison_id")])
  rows <- vector("list", nrow(keys))

  for (i in seq_len(nrow(keys))) {
    key_file <- keys$rm5_file[i]
    key_cmp <- keys$comparison_id[i]
    sub <- studies[studies$rm5_file == key_file & studies$comparison_id == key_cmp, ]
    est <- estimate_pooled_cer(sub$events_2, sub$total_2)

    rows[[i]] <- data.frame(
      rm5_file = key_file,
      comparison_id = key_cmp,
      control_event_rate = est$cer,
      control_event_rate_method = est$method,
      stringsAsFactors = FALSE
    )
  }

  do.call(rbind, rows)
}

load_meta <- function(path, studies_path, keep_keys) {
  df <- read.csv(path, stringsAsFactors = FALSE)
  num_cols <- c("total_participants", "total_events",
                "meta_events_1", "meta_total_1",
                "meta_events_2", "meta_total_2")
  for (col in num_cols) {
    if (col %in% names(df)) df[[col]] <- as.numeric(df[[col]])
  }
  flag_cols <- c("has_single_zero_study", "has_double_zero_study", "is_significant_05")
  for (col in flag_cols) {
    if (col %in% names(df)) df[[col]] <- toupper(as.character(df[[col]]))
  }
  df$outcome_class[is.na(df$outcome_class)] <- "unspecified"
  # Compute per-meta event rates
  df$intervention_event_rate <- df$meta_events_1 / ifelse(df$meta_total_1 > 0, df$meta_total_1, NA)
  cer_df <- estimate_control_cer_by_meta(studies_path, keep_keys = keep_keys)
  merge(df, cer_df, by = c("rm5_file", "comparison_id"), all.x = TRUE, sort = FALSE)
}

agg_block <- function(df, section_label, group_col = NULL) {
  safe_quantile <- function(x, prob) {
    x <- x[!is.na(x)]
    if (length(x) == 0) return(NA_real_)
    as.numeric(stats::quantile(x, probs = prob, names = FALSE, type = 7))
  }

  one_block <- function(sub, group_label) {
    data.frame(
      section = section_label,
      group = group_label,
      meta_analyses = nrow(sub),
      total_participants = sum(sub$total_participants, na.rm = TRUE),
      total_events = sum(sub$total_events, na.rm = TRUE),
      median_intervention_event_rate = median(sub$intervention_event_rate, na.rm = TRUE),
      q1_intervention_event_rate     = safe_quantile(sub$intervention_event_rate, 0.25),
      q3_intervention_event_rate     = safe_quantile(sub$intervention_event_rate, 0.75),
      median_control_event_rate      = median(sub$control_event_rate, na.rm = TRUE),
      q1_control_event_rate          = safe_quantile(sub$control_event_rate, 0.25),
      q3_control_event_rate          = safe_quantile(sub$control_event_rate, 0.75),
      significant_p_lt_0_05 = sum(sub$is_significant_05 == "YES", na.rm = TRUE),
      has_single_or_double_zero = sum(sub$has_single_zero_study == "YES" |
                                         sub$has_double_zero_study == "YES", na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
  if (!is.null(group_col)) {
    grp  <- split(df, df[[group_col]])
    rows <- lapply(names(grp), function(nm) one_block(grp[[nm]], nm))
    do.call(rbind, rows)
  } else {
    one_block(df, "")
  }
}

make_summary <- function(df) {
  overall    <- agg_block(df, "overall",          NULL)
  by_class   <- agg_block(df, "by_outcome_class", "outcome_class")
  by_measure <- agg_block(df, "by_effect_measure", "effect_measure")
  rbind(overall, by_class, by_measure)
}

filter_to_keep_keys <- function(df, keep_keys) {
  df[paste(df$rm5_file, df$comparison_id) %in% keep_keys, , drop = FALSE]
}

write_md_simple <- function(df, path) {
  fmt_iqr <- function(med, q1, q3)
    sprintf("%s%% (%s%%, %s%%)", fmt_sig(med * 100), fmt_sig(q1 * 100), fmt_sig(q3 * 100))

  # Build one data row from a one-row summary data.frame
  get_cells <- function(r) {
    if (nrow(r) == 0) return(rep("", 7))
    c(
      fmt_int(r$meta_analyses),
      fmt_int(r$total_participants),
      fmt_int(r$total_events),
      fmt_iqr(r$median_intervention_event_rate,
              r$q1_intervention_event_rate,
              r$q3_intervention_event_rate),
      fmt_iqr(r$median_control_event_rate,
              r$q1_control_event_rate,
              r$q3_control_event_rate),
      fmt_pct(r$significant_p_lt_0_05, r$meta_analyses),
      fmt_pct(r$has_single_or_double_zero, r$meta_analyses)
    )
  }

  # Extract rows for each group
  get_row <- function(section, group) df[df$section == section & df$group == group, ]
  r_all  <- df[df$section == "overall", ]
  r_mort <- get_row("by_outcome_class", "mortality")
  r_surv <- get_row("by_outcome_class", "survival")
  r_or   <- get_row("by_effect_measure", "OR")
  r_rr   <- get_row("by_effect_measure", "RR")

  n_data <- 7  # number of data columns
  md_row <- function(label, cells)
    paste("|", paste(c(label, cells), collapse = " | "), "|")
  blank_row <- function(label)
    paste("|", paste(c(label, rep("", n_data)), collapse = " | "), "|")

  col_headers <- c(
    "Group",
    "N of meta-analyses",
    "N of total participants",
    "N of total events",
    "Event rate in intervention group, median (IQR)",
    "Event rate in control group, median (IQR)",
    "p < 0.05 (count)",
    "Including single-/double-zero study"
  )
  header    <- paste("|", paste(col_headers, collapse = " | "), "|")
  separator <- paste("|", paste(c(":---", rep("---:", n_data)), collapse = " | "), "|")

  rows <- c(
    md_row("**Overall**",           get_cells(r_all)),
    blank_row("*By outcome class*"),
    md_row("\u2014 Mortality",      get_cells(r_mort)),
    md_row("\u2014 Survival",       get_cells(r_surv)),
    blank_row("*By effect measure*"),
    md_row("\u2014 OR",             get_cells(r_or)),
    md_row("\u2014 RR",             get_cells(r_rr))
  )

  md <- paste(c(header, separator, rows), collapse = "\n")
  writeLines(md, con = path)
}

main <- function() {
  primary <- read.csv(primary_path, stringsAsFactors = FALSE)
  keep_keys <- paste(primary$rm5_file, primary$comparison_id)

  df <- load_meta(meta_path, studies_path, keep_keys)
  df <- filter_to_keep_keys(df, keep_keys)
  summary <- make_summary(df)

  overall_n <- summary$meta_analyses[summary$section == "overall"]
  class_n <- sum(summary$meta_analyses[summary$section == "by_outcome_class"])
  measure_n <- sum(summary$meta_analyses[summary$section == "by_effect_measure"])
  if (class_n != overall_n || measure_n != overall_n) {
    stop(sprintf(
      "Group totals do not match overall N (%d): by_outcome_class=%d, by_effect_measure=%d",
      overall_n, class_n, measure_n
    ))
  }

  write.csv(summary, summary_csv, row.names = FALSE)
  write_md_simple(summary, summary_md)
  message("Wrote summary CSV: ", summary_csv)
  message("Wrote markdown table: ", summary_md)
}

main()
