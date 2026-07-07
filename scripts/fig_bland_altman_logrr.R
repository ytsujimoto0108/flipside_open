#!/usr/bin/env Rscript
# fig_bland_altman_logrr.R
# Supplementary Figure S1: Bland-Altman plot comparing log(RRo') and log(RRf').
# RRo'/RRf' are the direction-aligned RRo/RRf (see main_analysis.R): both are
# inverted together whenever RRo < 1, so the y-axis (log RRR') is positive
# when flipping moved the estimate away from the null and negative when it
# moved toward the null, regardless of whether RRo indicated benefit or harm.
# The unprimed RRo/RRf used in Figure 2 do not have this property.

suppressPackageStartupMessages({
  library(ggplot2)
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

base_dir <- find_project_root()
out_dir  <- file.path(base_dir, "data", "results")
res <- read.csv(file.path(out_dir, "primary_analysis_results.csv"), stringsAsFactors = FALSE)

plot_df <- res %>%
  mutate(
    log_rr_orig    = log(rr_orig_aligned),
    log_rr_flip_re = log(rr_flip_re_aligned),
    mean_log_rr    = (log_rr_orig + log_rr_flip_re) / 2,
    diff_log_rrr   = log_rr_flip_re - log_rr_orig
  ) %>%
  filter(is.finite(mean_log_rr), is.finite(diff_log_rrr))

bias    <- mean(plot_df$diff_log_rrr, na.rm = TRUE)
sd_diff <- sd(plot_df$diff_log_rrr, na.rm = TRUE)
loa_lo  <- bias - 1.96 * sd_diff
loa_hi  <- bias + 1.96 * sd_diff

fig_ba <- ggplot(plot_df, aes(x = mean_log_rr, y = diff_log_rrr)) +
  geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.6, linetype = "dashed") +
  geom_hline(yintercept = bias, colour = "firebrick", linewidth = 0.7) +
  geom_hline(yintercept = loa_lo, colour = "#2166ac", linewidth = 0.7, linetype = "dotted") +
  geom_hline(yintercept = loa_hi, colour = "#2166ac", linewidth = 0.7, linetype = "dotted") +
  geom_point(alpha = 0.25, size = 1.2, colour = "#2c7bb6") +
  labs(
    x = "Mean of log(RRo') and log(RRf')",
    y = "log(RRR')"
  ) +
  theme_bw(base_size = 12)

ba_path <- file.path(out_dir, paste0("fig_bland_altman_logrr_", format(Sys.Date(), "%Y%m%d"), ".svg"))
ggsave(ba_path, fig_ba, width = 7, height = 5)
message("  Wrote: ", ba_path)
message(sprintf("  Bias = %.3f; LoA = [%.3f, %.3f]", bias, loa_lo, loa_hi))
