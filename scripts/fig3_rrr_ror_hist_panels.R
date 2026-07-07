#!/usr/bin/env Rscript
# fig3_rrr_ror_hist_panels.R
# Figure 3: (a) histogram of the direction-aligned ratio of risk ratios
# (RRR') and (b) histogram of the direction-aligned ratio of odds ratios
# (ROR'), on a shared log-x-axis range so the relative width of the two
# distributions is directly comparable. RRR'/ROR' invert RRo/ORo and RRf/ORf
# together whenever the original estimate was below 1, so values below 1
# consistently mean flipping moved the estimate toward the null, regardless
# of whether the original estimate indicated benefit or harm; the unprimed
# RRR/ROR used in Table 2 and Figure 2 do not have this property (see
# Methods and Discussion).
# Supersedes fig_hist_rrr.R as the source of the manuscript's Figure 3, which
# is now a two-panel figure.

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(scales)
  library(cowplot)
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

rr_res <- read.csv(file.path(out_dir, "primary_analysis_results.csv"), stringsAsFactors = FALSE)
or_res <- read.csv(file.path(out_dir, "or_analysis_results.csv"), stringsAsFactors = FALSE)

rrr_df <- rr_res %>% filter(is.finite(rrr_aligned), rrr_aligned > 0)
ror_df <- or_res %>% filter(is.finite(ror_aligned), ror_aligned > 0)

# Shared log-x-axis range across both panels, so the width of the ROR'
# distribution can be visually compared against the RRR' distribution rather
# than each panel auto-scaling to its own (very different) range. Padded by
# 10% in log space so the outermost data points are not clipped by binning.
raw_range <- range(c(rrr_df$rrr_aligned, ror_df$ror_aligned), na.rm = TRUE)
shared_range <- raw_range * c(1 / 1.1, 1.1)
shared_breaks <- scales::breaks_log(n = 8)(raw_range)

fmt2sig <- function(x) {
  vapply(x, function(v) {
    if (!is.finite(v) || v <= 0) return(NA_character_)
    d <- max(0L, as.integer(1L - floor(log10(v))))
    formatC(v, format = "f", digits = d)
  }, character(1))
}

make_hist <- function(df, value_col, x_lab) {
  ggplot(df, aes(x = .data[[value_col]])) +
    geom_vline(xintercept = 1, colour = "firebrick", linewidth = 0.7, linetype = "dashed") +
    geom_histogram(fill = "#2c7bb6", colour = "white", alpha = 0.8, bins = 30) +
    scale_x_log10(
      limits = shared_range,
      breaks = shared_breaks,
      labels = fmt2sig
    ) +
    labs(x = x_lab, y = "Count") +
    theme_bw(base_size = 12)
}

panel_a <- make_hist(rrr_df, "rrr_aligned", "RRR")
panel_b <- make_hist(ror_df, "ror_aligned", "ROR")

fig_combined <- plot_grid(panel_a, panel_b, labels = c("a", "b"), nrow = 1)

fig_path <- file.path(out_dir, paste0("fig3_rrr_ror_panels_", format(Sys.Date(), "%Y%m%d"), ".svg"))
ggsave(fig_path, fig_combined, width = 11, height = 5)
message("  Wrote: ", fig_path)
