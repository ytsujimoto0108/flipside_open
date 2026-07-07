#!/usr/bin/env Rscript
# fig2_rr_or_scatter_panels.R
# Figure 2: (a) RR scatter (log(RRf) vs log(RRo)) and (b) OR scatter
# (log(ORf) vs log(ORo)), both coloured by single-/double-zero study status,
# combined into one figure with shared legend via patchwork.
# Supersedes fig_scatter_logrr_vs_logrro_by_zero.R as the source of the
# manuscript's Figure 2, which is now a two-panel figure.

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
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

studies <- read.csv(file.path(base_dir, "data", "meta_analysis_studies.csv"), stringsAsFactors = FALSE)
for (col in c("events_1", "events_2", "total_1", "total_2")) {
  studies[[col]] <- as.numeric(studies[[col]])
}

# A study contributes a zero cell to the original analysis if events_i == 0,
# and to the flipped analysis if events_i == total_i (so flipped events = 0).
# Independent of effect measure, so it is reused for both panels.
zero_info <- studies %>%
  mutate(
    zero_cell = (events_1 == 0) | (events_2 == 0) |
      (events_1 == total_1) | (events_2 == total_2)
  ) %>%
  group_by(rm5_file, comparison_id) %>%
  summarise(any_zero = any(zero_cell, na.rm = TRUE), .groups = "drop")

zero_levels <- c("No single-/double-zero study", "Includes single-/double-zero study")
zero_colours <- c(
  "No single-/double-zero study" = "#2c7bb6",
  "Includes single-/double-zero study" = "#fdae61"
)

fmt2sig <- function(x) {
  vapply(x, function(v) {
    if (!is.finite(v) || v <= 0) return(NA_character_)
    d <- max(0L, as.integer(1L - floor(log10(v))))
    formatC(v, format = "f", digits = d)
  }, character(1))
}

make_panel <- function(plot_df, x_lab, y_lab) {
  log_range <- range(c(log(plot_df$x), log(plot_df$y)), na.rm = TRUE)
  ax_lim <- exp(c(floor(log_range[1]), ceiling(log_range[2])))

  ggplot(plot_df, aes(x = x, y = y, colour = zero_group)) +
    geom_abline(slope = 1, intercept = 0, colour = "firebrick", linewidth = 0.7,
                linetype = "dashed") +
    geom_point(alpha = 0.35, size = 1.2) +
    scale_x_log10(limits = ax_lim, labels = fmt2sig) +
    scale_y_log10(limits = ax_lim, labels = fmt2sig) +
    coord_fixed() +
    scale_colour_manual(values = zero_colours, limits = zero_levels, drop = FALSE) +
    labs(x = x_lab, y = y_lab, colour = NULL) +
    theme_bw(base_size = 12) +
    theme(legend.position = "bottom")
}

# ── Panel (a): RR ──────────────────────────────────────────────────────────
rr_res <- read.csv(file.path(out_dir, "primary_analysis_results.csv"), stringsAsFactors = FALSE)
rr_df <- rr_res %>%
  left_join(zero_info, by = c("rm5_file", "comparison_id")) %>%
  mutate(
    x = rr_orig,
    y = rr_flip_re,
    zero_group = factor(
      ifelse(any_zero, zero_levels[2], zero_levels[1]),
      levels = zero_levels
    )
  ) %>%
  filter(is.finite(x), is.finite(y))

panel_a <- make_panel(rr_df, "RRo", "RRf")

# ── Panel (b): OR ───────────────────────────────────────────────────────────
or_res <- read.csv(file.path(out_dir, "or_analysis_results.csv"), stringsAsFactors = FALSE)
or_df <- or_res %>%
  left_join(zero_info, by = c("rm5_file", "comparison_id")) %>%
  mutate(
    x = or_orig,
    y = or_flip_re,
    zero_group = factor(
      ifelse(any_zero, zero_levels[2], zero_levels[1]),
      levels = zero_levels
    )
  ) %>%
  filter(is.finite(x), is.finite(y))

panel_b <- make_panel(or_df, "ORo", "ORf")

fig_combined <- plot_grid(panel_a, panel_b, labels = c("a", "b"), nrow = 1)

fig_path <- file.path(out_dir, paste0("fig2_rr_or_panels_", format(Sys.Date(), "%Y%m%d"), ".svg"))
ggsave(fig_path, fig_combined, width = 11, height = 6)
message("  Wrote: ", fig_path)
