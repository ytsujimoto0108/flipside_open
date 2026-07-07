#!/usr/bin/env Rscript
# main_analysis.R
# Covers section 3.6 of the research protocol.
#   3.6.1 Primary analysis  – implemented below
#   3.6.2 Subgroup analysis – implemented in subgroup_analysis_rrr.R

suppressPackageStartupMessages({
  library(meta)      # metabin(), MH random-effects
  library(dplyr)
})

# Resolve project root robustly for both `Rscript` and interactive source().
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

# ── Paths ──────────────────────────────────────────────────────────────────────
base_dir     <- find_project_root()
studies_path <- file.path(base_dir, "data", "meta_analysis_studies.csv")
meta_path    <- file.path(base_dir, "data", "meta_analyses_extracted.csv")
out_dir      <- file.path(base_dir, "data", "results")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
source(file.path(base_dir, "scripts", "cer_helpers.R"))

# GRADE absolute-risk thresholds (events per 1000)
GRADE_THRESHOLDS <- c(13, 32, 62) / 1000   # convert to proportions

# ── Helper: MH random-effects RR for one meta-analysis ─────────────────────────
#   Returns list(rr, lo, hi, k) or NULL if fewer than 2 estimable studies remain.
run_mh_rr <- function(e1, e2, n1, n2) {
  # Double-zero studies are omitted (protocol §3.6.1)
  keep <- !(e1 == 0 & e2 == 0)
  e1 <- e1[keep]; e2 <- e2[keep]; n1 <- n1[keep]; n2 <- n2[keep]

  # Single-zero correction: add 0.5 to all four cells
  single_zero <- (e1 == 0) | (e2 == 0)
  e1[single_zero] <- e1[single_zero] + 0.5
  e2[single_zero] <- e2[single_zero] + 0.5
  n1[single_zero] <- n1[single_zero] + 0.5
  n2[single_zero] <- n2[single_zero] + 0.5

  if (sum(keep) < 2) return(NULL)

  fit <- tryCatch(
    metabin(
      event.e   = e1, n.e = n1,
      event.c   = e2, n.c = n2,
      sm        = "RR",
      method    = "MH",
      method.tau = "DL",
      random    = TRUE,
      fixed     = FALSE,
      warn      = FALSE,
      warn.deprecated = FALSE
    ),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)

  list(
    rr = exp(fit$TE.random),
    lo = exp(fit$lower.random),
    hi = exp(fit$upper.random),
    k  = fit$k
  )
}

# ── Helper: GRADE imprecision ──────────────────────────────────────────────────
#   Returns the number of GRADE thresholds crossed by the 95% CI of ARD.
grade_imprecision <- function(rr_lo, rr_hi, cer) {
  # Absolute risk difference from RR and baseline control event rate (CER)
  ard_lo <- (rr_lo - 1) * cer
  ard_hi <- (rr_hi - 1) * cer
  ard_range <- range(ard_lo, ard_hi)
  # Count thresholds (in proportion scale) crossed by the CI
  sum(GRADE_THRESHOLDS > ard_range[1] & GRADE_THRESHOLDS < ard_range[2])
}

is_significant_rr <- function(lo, hi) {
  if (any(!is.finite(c(lo, hi)))) return(NA)
  (hi < 1) || (lo > 1)
}

ci_ratio <- function(lo, hi) {
  if (any(!is.finite(c(lo, hi))) || lo <= 0 || hi <= 0) return(NA_real_)
  hi / lo
}

fmt_n_pct <- function(n, denom) {
  if (!is.finite(denom) || denom <= 0) return(sprintf("%d", n))
  sprintf("%d/%d (%.2f%%)", n, denom, 100 * n / denom)
}


# ══════════════════════════════════════════════════════════════════════════════
# 3.6.1  Primary Analysis
# ══════════════════════════════════════════════════════════════════════════════
message("── 3.6.1 Primary analysis ──")

studies <- read.csv(studies_path, stringsAsFactors = FALSE)
meta    <- read.csv(meta_path,    stringsAsFactors = FALSE)

# Coerce to numeric
for (col in c("events_1", "events_2", "total_1", "total_2")) {
  studies[[col]] <- as.numeric(studies[[col]])
}

# Unique key: rm5_file + comparison_id
meta_keys <- unique(studies[, c("rm5_file", "comparison_id")])

results <- vector("list", nrow(meta_keys))

for (i in seq_len(nrow(meta_keys))) {
  if (i %% 250 == 0) {
    message(sprintf("  Processed %d / %d meta-analyses", i, nrow(meta_keys)))
  }

  key_file <- meta_keys$rm5_file[i]
  key_cmp  <- meta_keys$comparison_id[i]

  sub <- studies[studies$rm5_file == key_file &
                 studies$comparison_id == key_cmp, ]

  e1 <- sub$events_1; e2 <- sub$events_2
  n1 <- sub$total_1;  n2 <- sub$total_2

  # ── Original analysis ──────────────────────────────────────────────────────
  orig <- run_mh_rr(e1, e2, n1, n2)

  # ── Flipped analysis ───────────────────────────────────────────────────────
  # Swap events and non-events: new_events = total − original_events
  flip <- run_mh_rr(n1 - e1, n2 - e2, n1, n2)

  # Re-express flipped RR in the original orientation: RR_re = 1 / RR_flip
  if (!is.null(flip)) {
    flip_re <- list(
      rr = 1 / flip$rr,
      lo = 1 / flip$hi,   # CI bounds invert with reciprocal
      hi = 1 / flip$lo,
      k  = flip$k
    )
  } else {
    flip_re <- NULL
  }

  if (is.null(orig) || is.null(flip_re)) {
    results[[i]] <- NULL
    next
  }

  # ── CER from study-level control-group data ────────────────────────────────
  meta_row <- meta[meta$rm5_file == key_file &
                   meta$comparison_id == key_cmp, ]
  cer_orig_est <- estimate_pooled_cer(e2, n2)
  cer_flip_est <- estimate_pooled_cer(n2 - e2, n2)
  cer_orig <- cer_orig_est$cer
  cer_flip <- cer_flip_est$cer

  # ── GRADE imprecision ──────────────────────────────────────────────────────
  ard_orig    <- if (!is.na(cer_orig)) (orig$rr - 1) * cer_orig else NA_real_
  ard_lo_orig <- if (!is.na(cer_orig)) (orig$lo - 1) * cer_orig else NA_real_
  ard_hi_orig <- if (!is.na(cer_orig)) (orig$hi - 1) * cer_orig else NA_real_
  ard_flip    <- if (!is.na(cer_flip)) (flip$rr - 1) * cer_flip else NA_real_
  ard_lo_flip <- if (!is.na(cer_flip)) (flip$lo - 1) * cer_flip else NA_real_
  ard_hi_flip <- if (!is.na(cer_flip)) (flip$hi - 1) * cer_flip else NA_real_

  # GRADE imprecision counts for:
  # 4) original RR orientation
  # 5) flipped-only RR (no reciprocal re-expression)
  imp_orig     <- if (!is.na(cer_orig)) grade_imprecision(orig$lo, orig$hi, cer_orig) else NA_integer_
  imp_flip_raw <- if (!is.na(cer_flip)) grade_imprecision(flip$lo, flip$hi, cer_flip) else NA_integer_
  imp_diff     <- if (!is.na(imp_orig) && !is.na(imp_flip_raw)) imp_flip_raw - imp_orig else NA_integer_
  sig_orig     <- is_significant_rr(orig$lo, orig$hi)
  sig_flip_raw <- is_significant_rr(flip$lo, flip$hi)
  ci_ratio_orig <- ci_ratio(orig$lo, orig$hi)
  ci_ratio_flip <- ci_ratio(flip$lo, flip$hi)
  ci_narrowed <- if (is.na(ci_ratio_orig) || is.na(ci_ratio_flip)) {
    NA
  } else {
    ci_ratio_flip < ci_ratio_orig
  }

  sig_change <- if (is.na(sig_orig) || is.na(sig_flip_raw)) {
    NA_character_
  } else if (identical(sig_orig, sig_flip_raw)) {
    "unchanged"
  } else if (!sig_orig && sig_flip_raw) {
    "non-significant_to_significant"
  } else {
    "significant_to_non-significant"
  }

  # RRo and RRf re-expressed so that the original estimate (RRo') is always
  # <=1: both are inverted together when RRo > 1, so RRR' = RRf'/RRo' > 1
  # consistently means flipping moved the estimate toward the null, and < 1
  # consistently means it moved away from the null, regardless of whether
  # the original estimate indicated benefit or harm. RRR itself (not primed)
  # does not have this property, because its direction reverses depending on
  # whether RRo is above or below 1 (see Discussion).
  invert <- orig$rr > 1
  rr_orig_aligned    <- if (invert) 1 / orig$rr    else orig$rr
  rr_flip_re_aligned <- if (invert) 1 / flip_re$rr else flip_re$rr

  results[[i]] <- data.frame(
    rm5_file          = key_file,
    comparison_id     = key_cmp,
    k_orig            = orig$k,
    k_flip            = flip_re$k,
    outcome_class     = if (nrow(meta_row) > 0) meta_row$outcome_class[1] else NA_character_,
    rr_orig           = orig$rr,
    lo_orig           = orig$lo,
    hi_orig           = orig$hi,
    rr_flip           = flip$rr,
    lo_flip           = flip$lo,
    hi_flip           = flip$hi,
    rr_flip_re        = flip_re$rr,
    lo_flip_re        = flip_re$lo,
    hi_flip_re        = flip_re$hi,
    rrr               = flip_re$rr / orig$rr,   # ratio of risk ratios
    rr_orig_aligned   = rr_orig_aligned,        # RRo'
    rr_flip_re_aligned = rr_flip_re_aligned,    # RRf'
    rrr_aligned       = rr_flip_re_aligned / rr_orig_aligned,  # RRR'
    cer               = cer_orig,               # Backward-compatible alias
    cer_orig          = cer_orig,
    cer_flip          = cer_flip,
    cer_orig_method   = cer_orig_est$method,
    cer_flip_method   = cer_flip_est$method,
    ard_orig          = ard_orig,
    ard_lo_orig       = ard_lo_orig,
    ard_hi_orig       = ard_hi_orig,
    ard_flip          = ard_flip,
    ard_lo_flip       = ard_lo_flip,
    ard_hi_flip       = ard_hi_flip,
    sig_orig          = sig_orig,
    sig_flip          = sig_flip_raw,
    sig_change        = sig_change,
    ci_ratio_orig     = ci_ratio_orig,
    ci_ratio_flip     = ci_ratio_flip,
    ci_narrowed       = ci_narrowed,
    grade_imp_orig    = imp_orig,
    grade_imp_flip    = imp_flip_raw,
    grade_imp_diff    = imp_diff,
    stringsAsFactors  = FALSE
  )
}

res <- bind_rows(results)
message(sprintf("  Estimable pairs: %d / %d meta-analyses", nrow(res), nrow(meta_keys)))

# ── Save results ──────────────────────────────────────────────────────────────
results_csv <- file.path(out_dir, "primary_analysis_results.csv")
write.csv(res, results_csv, row.names = FALSE)
message("  Wrote: ", results_csv)


# ── Summary statistics (printed) ──────────────────────────────────────────────
# Figures 2, 3, and Supplementary Figure S1 are produced by the dedicated
# fig2_rr_or_scatter_panels.R / fig3_rrr_ror_hist_panels.R /
# fig_bland_altman_logrr.R scripts, which read primary_analysis_results.csv.
# Table 2 is produced by export_table2_summary.R from the same file.
rrr_df <- res %>%
  filter(is.finite(rrr), rrr > 0)

message("\n── Summary ──")
message(sprintf("  Median RRR: %.2f  [IQR: %.2f, %.2f]",
  median(rrr_df$rrr, na.rm = TRUE),
  quantile(rrr_df$rrr, 0.25, na.rm = TRUE),
  quantile(rrr_df$rrr, 0.75, na.rm = TRUE)))

changed_grade <- sum(res$grade_imp_orig != res$grade_imp_flip, na.rm = TRUE)
if (!all(is.na(res$grade_imp_orig))) {
  message(sprintf("  GRADE imprecision changed: %d / %d meta-analyses (%.1f%%)",
    changed_grade, nrow(res), changed_grade / nrow(res) * 100))
  message(sprintf("  Median diff (flip - original): %.2f  [IQR: %.2f, %.2f]",
    median(res$grade_imp_diff, na.rm = TRUE),
    quantile(res$grade_imp_diff, 0.25, na.rm = TRUE),
    quantile(res$grade_imp_diff, 0.75, na.rm = TRUE)))
}

sig_changed <- sum(res$sig_orig != res$sig_flip, na.rm = TRUE)
sig_up <- sum(res$sig_change == "non-significant_to_significant", na.rm = TRUE)
sig_down <- sum(res$sig_change == "significant_to_non-significant", na.rm = TRUE)
ci_narrowed_n <- sum(res$ci_narrowed, na.rm = TRUE)
message(sprintf("  Statistical significance changed: %d / %d meta-analyses (%.1f%%)",
  sig_changed, nrow(res), sig_changed / nrow(res) * 100))
message(sprintf("    Non-significant -> significant: %s", fmt_n_pct(sig_up, nrow(res))))
message(sprintf("    Significant -> non-significant: %s", fmt_n_pct(sig_down, nrow(res))))
message(sprintf("    95%% CI narrowed after flipping: %s", fmt_n_pct(ci_narrowed_n, nrow(res))))

message("\n── 3.6.1 complete. Run scripts/subgroup_analysis_rrr.R for 3.6.2, ",
        "scripts/export_table2_summary.R for Table 2, and the fig*.R scripts ",
        "for Figures 2/3 and Supplementary Figure S1. ──")
