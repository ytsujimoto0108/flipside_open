#!/usr/bin/env Rscript
# subgroup_analysis_rrr.R
# 3.6.2 Subgroup analysis: compare RRR' distributions across pre-specified
# subgroups. Uses the direction-aligned RRR' (see main_analysis.R), not the
# unprimed RRR used in Table 2/Figure 2, so that values below 1 consistently
# mean flipping moved the estimate toward the null across all subgroups.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(scales)
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
results_path <- file.path(base_dir, "data", "results", "primary_analysis_results.csv")
studies_path <- file.path(base_dir, "data", "meta_analysis_studies.csv")
out_dir <- file.path(base_dir, "data", "results")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

message("── 3.6.2 Subgroup analysis (RRR) ──")

res <- read.csv(results_path, stringsAsFactors = FALSE)
studies <- read.csv(studies_path, stringsAsFactors = FALSE)
res$baseline_cer <- if ("cer_orig" %in% names(res)) res$cer_orig else res$cer

for (col in c("events_1", "events_2", "total_1", "total_2")) {
  studies[[col]] <- as.numeric(studies[[col]])
}

# Build subgroup metadata at meta-analysis level from study-level 2x2 data.
meta_info <- studies %>%
  group_by(rm5_file, comparison_id) %>%
  summarise(
    total_n = sum(total_1 + total_2, na.rm = TRUE),
    any_single_zero = any((events_1 == 0 & events_2 != 0) | (events_1 != 0 & events_2 == 0), na.rm = TRUE),
    any_double_zero = any(events_1 == 0 & events_2 == 0, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  left_join(
    res %>% select(rm5_file, comparison_id, baseline_cer),
    by = c("rm5_file", "comparison_id")
  ) %>%
  mutate(
    subgroup_total_n = ifelse(total_n < 1000, "<1000", "\u22651000"),
    subgroup_cer = case_when(
      is.na(baseline_cer) ~ NA_character_,
      baseline_cer < 0.05 ~ "<5%",
      TRUE ~ "\u22655%"
    ),
    subgroup_zero = ifelse(any_single_zero | any_double_zero, "Included", "Not included")
  ) %>%
  select(rm5_file, comparison_id, total_n, subgroup_total_n, subgroup_cer, subgroup_zero)

plot_input <- res %>%
  inner_join(meta_info, by = c("rm5_file", "comparison_id")) %>%
  filter(is.finite(rrr_aligned), rrr_aligned > 0, is.finite(baseline_cer))

summarize_group <- function(df, subgroup_col, subgroup_name) {
  lev <- df[[subgroup_col]]
  df %>%
    group_by(level = lev) %>%
    summarise(
      n = n(),
      median_rrr = median(rrr_aligned, na.rm = TRUE),
      q1_rrr = quantile(rrr_aligned, 0.25, na.rm = TRUE),
      q3_rrr = quantile(rrr_aligned, 0.75, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(subgroup = subgroup_name)
}

summary_df <- bind_rows(
  summarize_group(plot_input, "subgroup_total_n", "Total sample size"),
  summarize_group(plot_input, "subgroup_cer", "Baseline control event rate"),
  summarize_group(plot_input, "subgroup_zero", "Single-/double-zero studies")
) %>%
  mutate(
    subgroup = factor(
      subgroup,
      levels = c("Total sample size", "Baseline control event rate", "Single-/double-zero studies")
    ),
    level = dplyr::case_when(
      level == "<1000" ~ "<1000",
      level == "\u22651000" ~ "\u22651000",
      level == "<5%" ~ "<5%",
      level == "\u22655%" ~ "\u22655%",
      level == "Not included" ~ "Not included",
      level == "Included" ~ "Included",
      TRUE ~ as.character(level)
    )
  ) %>%
  mutate(
    level = factor(
      level,
      levels = c("<1000", "\u22651000", "<5%", "\u22655%", "Not included", "Included")
    ),
    left_label = paste(subgroup, level, sep = ": ")
  )

summary_csv <- file.path(out_dir, "subgroup_rrr_summary.csv")
write.csv(summary_df, summary_csv, row.names = FALSE)
message("  Wrote: ", summary_csv)

# Forest-style plot in a single panel: a non-plotted "header" row labels each
# subgroup category, and its two levels are listed indented beneath it, so
# the three categories are grouped without splitting the plot into facets.
# Display order (top to bottom): single-/double-zero studies, baseline
# control event rate, total sample size.
row_order_top_to_bottom <- c(
  "Single-/double-zero studies",
  "    Not included",
  "    Included",
  "Baseline control event rate",
  "    \u22655%",
  "    <5%",
  "Total sample size",
  "    \u22651000",
  "    <1000"
)

header_df <- summary_df %>%
  distinct(subgroup) %>%
  transmute(sort_key = as.character(subgroup), row_label = as.character(subgroup))

level_df <- summary_df %>%
  mutate(
    sort_key = paste0("    ", as.character(level)),
    row_label = paste0("    ", as.character(level),
                        " (n = ", formatC(n, format = "d", big.mark = ","), ")")
  )

plot_df <- bind_rows(header_df, level_df) %>%
  mutate(sort_key = factor(sort_key, levels = rev(row_order_top_to_bottom))) %>%
  arrange(sort_key) %>%
  mutate(row_label = factor(row_label, levels = unique(row_label)))

fig <- ggplot(plot_df, aes(y = row_label)) +
  geom_vline(xintercept = 1, linetype = "dashed", linewidth = 0.7, colour = "firebrick") +
  geom_segment(
    data = ~ filter(.x, !is.na(median_rrr)),
    aes(x = q1_rrr, xend = q3_rrr, yend = row_label),
    linewidth = 1.2,
    colour = "#2c7bb6"
  ) +
  geom_point(
    data = ~ filter(.x, !is.na(median_rrr)),
    aes(x = median_rrr), size = 2.4, colour = "#1b4f72"
  ) +
  scale_x_log10(
    limits = c(0.5, 2.0),
    breaks = c(0.5, 1.0, 2.0),
    labels = c("0.50", "1.0", "2.0")
  ) +
  scale_y_discrete(drop = FALSE) +
  labs(
    x = "RRR",
    y = NULL
  ) +
  theme_bw(base_size = 12) +
  theme(
    axis.text.y = element_text(hjust = 0),
    plot.margin = margin(8, 8, 8, 8)
  )

fig_path <- file.path(out_dir, paste0("fig_forest_subgroup_rrr_", format(Sys.Date(), "%Y%m%d"), ".svg"))
ggsave(fig_path, fig, width = 10.5, height = 6.5)
message("  Wrote: ", fig_path)

message("── 3.6.2 subgroup analysis complete ──")
