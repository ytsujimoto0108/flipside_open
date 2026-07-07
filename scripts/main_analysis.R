#!/usr/bin/env Rscript
# main_analysis.R
# Covers section 3.6 of the research protocol.
#   3.6.1 Primary analysis  – implemented below
#   3.6.2 Subgroup analysis – implemented in subgroup_analysis_rrr.R

suppressPackageStartupMessages({
  library(meta)      # metabin(), MH random-effects
  library(ggplot2)
  library(dplyr)
  library(scales)
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


# ── Supplementary Figure S1: Bland-Altman plot on log scale ───────────────────
today_str <- format(Sys.Date(), "%Y-%m-%d")

plot_df <- res %>%
  mutate(
    log_rr_orig     = log(rr_orig),
    log_rr_flip_re  = log(rr_flip_re),
    mean_log_rr     = (log_rr_orig + log_rr_flip_re) / 2,
    diff_log_rrr    = log_rr_flip_re - log_rr_orig # equals log(RRR)
  ) %>%
  filter(is.finite(mean_log_rr), is.finite(diff_log_rrr))

bias <- mean(plot_df$diff_log_rrr, na.rm = TRUE)
sd_diff <- sd(plot_df$diff_log_rrr, na.rm = TRUE)
loa_lo <- bias - 1.96 * sd_diff
loa_hi <- bias + 1.96 * sd_diff

fig_ba <- ggplot(plot_df, aes(x = mean_log_rr, y = diff_log_rrr)) +
  geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.6, linetype = "dashed") +
  geom_hline(yintercept = bias, colour = "firebrick", linewidth = 0.7) +
  geom_hline(yintercept = loa_lo, colour = "#2166ac", linewidth = 0.7, linetype = "dotted") +
  geom_hline(yintercept = loa_hi, colour = "#2166ac", linewidth = 0.7, linetype = "dotted") +
  geom_point(alpha = 0.25, size = 1.2, colour = "#2c7bb6") +
  labs(
    x = "Mean of log(RRo) and log(RRf)",
    y = "log(RRR)",
    title = paste0("Bland-Altman plot for pooled RR (", today_str, ")"),
    subtitle = sprintf("Bias = %.3f; LoA = [%.3f, %.3f]", bias, loa_lo, loa_hi),
    caption = "RRR = RRf / RRo; RRo = original pooled RR; RRf = reciprocal of flipped pooled RR"
  ) +
  theme_bw(base_size = 12) +
  theme(plot.title = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5, colour = "grey40"),
        plot.caption = element_text(colour = "grey35"))

ba_path <- file.path(out_dir, paste0("fig_bland_altman_logrr_", format(Sys.Date(), "%Y%m%d"), ".svg"))
ggsave(ba_path, fig_ba, width = 7, height = 5)
message("  Wrote: ", ba_path)


# ── Figure 2: Scatter plot of log(RRf) vs log(RRo) ────────────────────────────
ax_lim <- range(c(plot_df$log_rr_orig, plot_df$log_rr_flip_re), na.rm = TRUE)
ax_lim <- c(floor(ax_lim[1]), ceiling(ax_lim[2]))

fig_scatter <- ggplot(plot_df, aes(x = log_rr_orig, y = log_rr_flip_re)) +
  geom_abline(slope = 1, intercept = 0, colour = "firebrick", linewidth = 0.7,
              linetype = "dashed") +
  geom_point(alpha = 0.25, size = 1.2, colour = "#2c7bb6") +
  coord_fixed(xlim = ax_lim, ylim = ax_lim) +
  labs(
    x = "log(RRo)",
    y = "log(RRf)",
    title = paste0("log(RRf) vs log(RRo) (", today_str, ")"),
    subtitle = "Dashed line = identity (y = x); points above the line indicate RRf > RRo",
    caption = "RRo = original pooled RR; RRf = reciprocal of flipped pooled RR"
  ) +
  theme_bw(base_size = 12) +
  theme(plot.title = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5, colour = "grey40"),
        plot.caption = element_text(colour = "grey35"))

scatter_path <- file.path(out_dir, paste0("fig_scatter_logrr_vs_logrro_", format(Sys.Date(), "%Y%m%d"), ".svg"))
ggsave(scatter_path, fig_scatter, width = 6, height = 6)
message("  Wrote: ", scatter_path)


# ── Figure 3: Histogram of RRR (ratio of risk ratios) ────────────────────────
rrr_df <- res %>%
  filter(is.finite(rrr), rrr > 0)

fig_hist <- ggplot(rrr_df, aes(x = rrr)) +
  geom_vline(xintercept = 1, colour = "firebrick", linewidth = 0.7,
             linetype = "dashed") +
  geom_histogram(fill = "#2c7bb6", colour = "white",
                 alpha = 0.8) +
  scale_x_log10(
    breaks = scales::breaks_log(n = 10),
    labels = scales::label_number(accuracy = 0.1, trim = TRUE)
  ) +
  labs(
    x     = "Log(RRR)",
    y     = "Count",
    title = paste0("Distribution of ratio of risk ratios (RRR) (", today_str, ")"),
    subtitle = "Dashed line at 1 = no difference between orientations",
    caption = "RRR = RRf / RRo; RRo = original pooled RR; RRf = reciprocal of flipped pooled RR"
  ) +
  theme_bw(base_size = 12) +
  theme(plot.title = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5, colour = "grey40"),
        plot.caption = element_text(colour = "grey35"))

hist_path <- file.path(out_dir, paste0("fig_hist_rrr_", format(Sys.Date(), "%Y%m%d"), ".svg"))
ggsave(hist_path, fig_hist, width = 7, height = 5)
message("  Wrote: ", hist_path)


# ── Summary statistics (printed) ──────────────────────────────────────────────
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

summary_md <- file.path(out_dir, "primary_analysis_summary.md")
grade_increase <- sum(res$grade_imp_diff > 0, na.rm = TRUE)
grade_decrease <- sum(res$grade_imp_diff < 0, na.rm = TRUE)
grade_same <- sum(res$grade_imp_diff == 0, na.rm = TRUE)

class_order <- c("mortality", "survival")
class_labels <- c(mortality = "Mortality", survival = "Survival")
table2_rows <- lapply(class_order, function(cls) {
  sub <- res[res$outcome_class == cls, , drop = FALSE]
  c(
    N = nrow(sub),
    sig_changed = fmt_n_pct(sum(sub$sig_orig != sub$sig_flip, na.rm = TRUE), nrow(sub)),
    sig_up = fmt_n_pct(sum(sub$sig_change == "non-significant_to_significant", na.rm = TRUE), nrow(sub)),
    sig_down = fmt_n_pct(sum(sub$sig_change == "significant_to_non-significant", na.rm = TRUE), nrow(sub)),
    ci_narrowed = fmt_n_pct(sum(sub$ci_narrowed, na.rm = TRUE), nrow(sub)),
    grade_changed = fmt_n_pct(sum(sub$grade_imp_orig != sub$grade_imp_flip, na.rm = TRUE), nrow(sub)),
    grade_increase = fmt_n_pct(sum(sub$grade_imp_diff > 0, na.rm = TRUE), nrow(sub)),
    grade_decrease = fmt_n_pct(sum(sub$grade_imp_diff < 0, na.rm = TRUE), nrow(sub)),
    grade_diff = sprintf("%.0f (%.0f to %.0f)",
      median(sub$grade_imp_diff, na.rm = TRUE),
      quantile(sub$grade_imp_diff, 0.25, na.rm = TRUE),
      quantile(sub$grade_imp_diff, 0.75, na.rm = TRUE)),
    rrr = sprintf("%.2f (%.2f to %.2f)",
      median(sub$rrr, na.rm = TRUE),
      quantile(sub$rrr, 0.25, na.rm = TRUE),
      quantile(sub$rrr, 0.75, na.rm = TRUE))
  )
})
names(table2_rows) <- class_order

summary_lines <- c(
  "# Primary analysis summary",
  "",
  sprintf("- Estimable meta-analyses: %d", nrow(res)),
  sprintf("- Median RRR: %.2f [IQR %.2f to %.2f]",
          median(rrr_df$rrr, na.rm = TRUE),
          quantile(rrr_df$rrr, 0.25, na.rm = TRUE),
          quantile(rrr_df$rrr, 0.75, na.rm = TRUE)),
  sprintf("- Statistical significance changed between original and flipped-only analyses: %s",
          fmt_n_pct(sig_changed, nrow(res))),
  sprintf("- Non-significant to significant: %s",
          fmt_n_pct(sig_up, nrow(res))),
  sprintf("- Significant to non-significant: %s",
          fmt_n_pct(sig_down, nrow(res))),
  sprintf("- 95%% CI narrowed after flipping: %s",
          fmt_n_pct(ci_narrowed_n, nrow(res))),
  sprintf("- GRADE imprecision changed between original and flipped-only analyses: %s",
          fmt_n_pct(changed_grade, nrow(res))),
  sprintf("- GRADE imprecision increased after flipping: %s",
          fmt_n_pct(grade_increase, nrow(res))),
  sprintf("- GRADE imprecision decreased after flipping: %s",
          fmt_n_pct(grade_decrease, nrow(res))),
  sprintf("- GRADE imprecision unchanged: %s",
          fmt_n_pct(grade_same, nrow(res))),
  sprintf("- Median GRADE imprecision difference (flip - original): %.2f [IQR %.2f to %.2f]",
          median(res$grade_imp_diff, na.rm = TRUE),
          quantile(res$grade_imp_diff, 0.25, na.rm = TRUE),
          quantile(res$grade_imp_diff, 0.75, na.rm = TRUE)),
  "",
  "## Table 2",
  "",
  "Table 2. Primary analysis results stratified by original outcome orientation.",
  "",
  sprintf("| Original measure | %s | %s |",
          class_labels["mortality"], class_labels["survival"]),
  "| :------------------------------- | ------------------: | ------------------: |",
  sprintf("| N | %s | %s |", table2_rows$mortality["N"], table2_rows$survival["N"]),
  sprintf("| Statistical significance changed | %s | %s |", table2_rows$mortality["sig_changed"], table2_rows$survival["sig_changed"]),
  sprintf("| Non-significant to significant | %s | %s |", table2_rows$mortality["sig_up"], table2_rows$survival["sig_up"]),
  sprintf("| Significant to non-significant | %s | %s |", table2_rows$mortality["sig_down"], table2_rows$survival["sig_down"]),
  sprintf("| 95%% CI narrowed after flipping | %s | %s |", table2_rows$mortality["ci_narrowed"], table2_rows$survival["ci_narrowed"]),
  sprintf("| GRADE imprecision changed | %s | %s |", table2_rows$mortality["grade_changed"], table2_rows$survival["grade_changed"]),
  sprintf("| GRADE improved after flipping | %s | %s |", table2_rows$mortality["grade_increase"], table2_rows$survival["grade_increase"]),
  sprintf("| GRADE worsened after flipping | %s | %s |", table2_rows$mortality["grade_decrease"], table2_rows$survival["grade_decrease"]),
  sprintf("| Median GRADE diff (IQR) | %s | %s |", table2_rows$mortality["grade_diff"], table2_rows$survival["grade_diff"]),
  sprintf("| Median RRR (IQR) | %s | %s |", table2_rows$mortality["rrr"], table2_rows$survival["rrr"]),
  "",
  "## Figures",
  "",
  sprintf("![Bland-Altman plot for pooled RR](%s)", basename(ba_path)),
  "",
  sprintf("![Histogram of RRR](%s)", basename(hist_path))
)
writeLines(summary_lines, summary_md)
message("  Wrote: ", summary_md)

message("\n── 3.6.1 complete. Run scripts/subgroup_analysis_rrr.R for 3.6.2. ──")
