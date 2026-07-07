#!/usr/bin/env Rscript
# additional_analysis_or.R
# Additional analysis (not pre-specified in the protocol): repeat the primary
# flip comparison using Mantel-Haenszel pooled odds ratios (OR) instead of
# risk ratios (RR), on the same meta-analyses, to test whether OR is less
# sensitive to flipping than RR (as argued in the Introduction/Discussion).
# Mirrors main_analysis.R's zero-handling and pooling method exactly, but
# does not compute GRADE imprecision or CER, which are RR-scale concepts
# tied to absolute risk difference.

suppressPackageStartupMessages({
  library(meta)      # metabin(), MH random-effects
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

base_dir     <- find_project_root()
studies_path <- file.path(base_dir, "data", "meta_analysis_studies.csv")
primary_path <- file.path(base_dir, "data", "results", "primary_analysis_results.csv")
out_dir      <- file.path(base_dir, "data", "results")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# MH random-effects pooled OR for one meta-analysis (same zero-handling as
# main_analysis.R's run_mh_rr: double-zero studies omitted, single-zero
# studies get a 0.5 continuity correction to all four cells).
run_mh_or <- function(e1, e2, n1, n2) {
  keep <- !(e1 == 0 & e2 == 0)
  e1 <- e1[keep]; e2 <- e2[keep]; n1 <- n1[keep]; n2 <- n2[keep]

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
      sm        = "OR",
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
    or = exp(fit$TE.random),
    lo = exp(fit$lower.random),
    hi = exp(fit$upper.random),
    k  = fit$k
  )
}

message("── Additional analysis: pooled OR vs flipped OR ──")
studies <- read.csv(studies_path, stringsAsFactors = FALSE)
for (col in c("events_1", "events_2", "total_1", "total_2")) {
  studies[[col]] <- as.numeric(studies[[col]])
}

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

  orig <- run_mh_or(e1, e2, n1, n2)
  flip <- run_mh_or(n1 - e1, n2 - e2, n1, n2)

  if (is.null(orig) || is.null(flip)) {
    results[[i]] <- NULL
    next
  }

  # Re-express the flipped OR in the original orientation, as for RR.
  flip_re <- list(
    or = 1 / flip$or,
    lo = 1 / flip$hi,
    hi = 1 / flip$lo,
    k  = flip$k
  )

  # Direction-aligned ORo'/ORf' (see main_analysis.R): both inverted together
  # when ORo > 1, so ROR' > 1 consistently means flipping moved the estimate
  # toward the null, regardless of whether ORo indicated benefit or harm.
  invert <- orig$or > 1
  or_orig_aligned    <- if (invert) 1 / orig$or    else orig$or
  or_flip_re_aligned <- if (invert) 1 / flip_re$or else flip_re$or

  results[[i]] <- data.frame(
    rm5_file         = key_file,
    comparison_id    = key_cmp,
    k_orig           = orig$k,
    k_flip           = flip_re$k,
    or_orig          = orig$or,
    lo_orig          = orig$lo,
    hi_orig          = orig$hi,
    or_flip          = flip$or,
    lo_flip          = flip$lo,
    hi_flip          = flip$hi,
    or_flip_re       = flip_re$or,
    lo_flip_re       = flip_re$lo,
    hi_flip_re       = flip_re$hi,
    ror              = flip_re$or / orig$or,   # ratio of odds ratios
    or_orig_aligned    = or_orig_aligned,         # ORo'
    or_flip_re_aligned = or_flip_re_aligned,      # ORf'
    ror_aligned        = or_flip_re_aligned / or_orig_aligned,  # ROR'
    stringsAsFactors = FALSE
  )
}

res <- bind_rows(results)
message(sprintf("  Estimable pairs: %d / %d meta-analyses", nrow(res), nrow(meta_keys)))

# Sanity check: this should be run on exactly the same meta-analyses as the
# RR-based primary analysis, since the >=2-estimable-study criterion does not
# depend on which effect measure is pooled.
primary <- read.csv(primary_path, stringsAsFactors = FALSE)
primary_keys <- paste(primary$rm5_file, primary$comparison_id)
or_keys <- paste(res$rm5_file, res$comparison_id)
if (!setequal(primary_keys, or_keys)) {
  stop(sprintf(
    "OR-estimable set (%d) does not match RR primary-analysis set (%d); only_in_or=%d only_in_rr=%d",
    length(or_keys), length(primary_keys),
    length(setdiff(or_keys, primary_keys)), length(setdiff(primary_keys, or_keys))
  ))
}

results_csv <- file.path(out_dir, "or_analysis_results.csv")
write.csv(res, results_csv, row.names = FALSE)
message("  Wrote: ", results_csv)

ror_df <- res %>% filter(is.finite(ror), ror > 0)
message("\n── Summary ──")
message(sprintf("  Median ROR: %.3f  [IQR: %.3f, %.3f]",
  median(ror_df$ror, na.rm = TRUE),
  quantile(ror_df$ror, 0.25, na.rm = TRUE),
  quantile(ror_df$ror, 0.75, na.rm = TRUE)))
message(sprintf("  ROR range: [%.3f, %.3f]", min(ror_df$ror, na.rm = TRUE), max(ror_df$ror, na.rm = TRUE)))

message("\n── Additional OR analysis complete ──")
